#!/usr/bin/env bash
set -Eeuo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
build="${1:-}"
manifest="${2:-}"
container="${DOOMDB_ASSET_TOOL_CONTAINER:-$(docker compose -f "$root/compose.yaml" ps -q db)}"
java_home="${DOOMDB_ASSET_TOOL_HOME:-/opt/oracle/product/26ai/dbhomeFree}"
ojdbc="$java_home/jdbc/lib/ojdbc11.jar"
oraclepki="$java_home/jlib/oraclepki.jar"
osdt_core="$java_home/OPatch/modules/oracle.osdt/osdt_core.jar"
osdt_cert="$java_home/OPatch/modules/oracle.osdt/osdt_cert.jar"
jdbc_runtime="$ojdbc:$oraclepki:$osdt_core:$osdt_cert"
host_tmp=''
remote=''

for name in ADB_CONNECTION_STRING ADB_USERNAME ADB_PASSWORD ADB_WALLET_DIR; do
  [[ -n "${!name:-}" ]] || {
    printf 'required environment variable is absent: %s\n' "$name" >&2
    exit 2
  }
done
[[ "$ADB_USERNAME" =~ ^[A-Za-z][A-Za-z0-9_\$#]{0,127}$ ]] || {
  printf 'ADB_USERNAME is not a simple Oracle identifier\n' >&2; exit 2; }
[[ -d "$build" && ! -L "$build" && -f "$manifest" && ! -L "$manifest" ]] || {
  printf 'hosted-static build or loader manifest is invalid\n' >&2; exit 2; }
[[ -n "$container" ]] || {
  printf 'pinned JDBC asset tool container is unavailable\n' >&2; exit 2; }
[[ -d "$ADB_WALLET_DIR" && ! -L "$ADB_WALLET_DIR" ]] || {
  printf 'wallet directory is invalid\n' >&2; exit 2; }
for tool in docker node; do
  command -v "$tool" >/dev/null || {
    printf '%s is unavailable\n' "$tool" >&2; exit 2; }
done

cleanup(){
  [[ -z "$remote" ]] ||
    docker exec "$container" rm -rf "$remote" >/dev/null 2>&1 || true
  [[ -z "$host_tmp" ]] || rm -rf "$host_tmp"
}
trap cleanup EXIT HUP INT TERM

host_tmp="$(mktemp -d "${TMPDIR:-/tmp}/doomdb-hosted-statics.XXXXXX")"
remote="/tmp/doomdb-hosted-statics-$$"
mkdir -p "$host_tmp/wallet"
cp -R "$ADB_WALLET_DIR/." "$host_tmp/wallet"
cp "$manifest" "$host_tmp/loader-manifest.tsv"
cp "$root/tools/cloud/DoomHostedStaticLoader.java" "$host_tmp/"
chmod -R go-rwx "$host_tmp"

docker exec "$container" install -d -m 700 "$remote" "$remote/wallet" \
  "$remote/build"
docker cp "$host_tmp/wallet/." "$container:$remote/wallet" >/dev/null
docker cp "$build/." "$container:$remote/build" >/dev/null
docker cp "$host_tmp/loader-manifest.tsv" "$container:$remote/" >/dev/null
docker cp "$host_tmp/DoomHostedStaticLoader.java" "$container:$remote/" >/dev/null
printf '%s\n' "$ADB_PASSWORD" | docker exec -i "$container" sh -c \
  "umask 077; cat > '$remote/password'"
docker exec -u 0 "$container" chown -R oracle:oinstall "$remote"
docker exec "$container" chmod -R go-rwx "$remote"
docker exec "$container" "$java_home/jdk/bin/javac" --release 11 \
  -cp "$ojdbc" -d "$remote" "$remote/DoomHostedStaticLoader.java"

if ! docker exec -e "TNS_ADMIN=$remote/wallet" "$container" sh -c \
  'password=$1; shift; exec "$@" < "$password"' sh "$remote/password" \
  "$java_home/jdk/bin/java" -Xms32m -Xmx256m \
  -cp "$remote:$jdbc_runtime" \
  DoomHostedStaticLoader "jdbc:oracle:thin:@$ADB_CONNECTION_STRING" \
  "$ADB_USERNAME" "$remote/build" "$remote/loader-manifest.tsv" \
  >"$host_tmp/load.log" 2>&1; then
  node "$root/scripts/redact-cloud-output.mjs" <"$host_tmp/load.log" |
    tail -80 >&2
  printf 'Hosted-static load failed (redacted underlying diagnostics shown above)\n' >&2
  exit 1
fi
node "$root/scripts/redact-cloud-output.mjs" <"$host_tmp/load.log"
