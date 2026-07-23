#!/usr/bin/env bash
set -Eeuo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
container="${DOOMDB_ASSET_TOOL_CONTAINER:-$(docker compose -f "$root/compose.yaml" ps -q db)}"
java_home="${DOOMDB_ASSET_TOOL_HOME:-/opt/oracle/product/26ai/dbhomeFree}"
iwad_zip="$root/vendor/freedoom/0.13.0/freedoom-0.13.0.zip"
iwad_sha="7323bcc168c5a45ff10749b339960e98314740a734c30d4b9f3337001f9e703d"
revision="c0af1322ee5fd168b5cf8aaaf504cab2d1aabe93"
host_tmp=''
remote=''

for name in ADB_CONNECTION_STRING ADB_USERNAME ADB_PASSWORD ADB_WALLET_DIR; do
  [[ -n "${!name:-}" ]] || {
    printf 'required environment variable is absent: %s\n' "$name" >&2;exit 2; }
done
[[ "$ADB_USERNAME" =~ ^[A-Za-z][A-Za-z0-9_\$#]{0,127}$ ]] || {
  printf 'ADB_USERNAME is not a simple Oracle identifier\n' >&2;exit 2; }
[[ -n "$container" ]] || {
  printf 'pinned JDBC asset tool container is unavailable\n' >&2;exit 2; }
[[ -d "$ADB_WALLET_DIR" && ! -L "$ADB_WALLET_DIR" ]] || {
  printf 'wallet directory is invalid\n' >&2;exit 2; }
for tool in docker unzip shasum; do
  command -v "$tool" >/dev/null || {
    printf '%s is unavailable\n' "$tool" >&2;exit 2; }
done

cleanup(){
  [[ -z "$remote" ]] ||
    docker exec "$container" rm -rf "$remote" >/dev/null 2>&1 || true
  [[ -z "$host_tmp" ]] || rm -rf "$host_tmp"
}
trap cleanup EXIT

host_tmp="$(mktemp -d "${TMPDIR:-/tmp}/doomdb-cloud-assets.XXXXXX")"
remote="/tmp/doomdb-cloud-assets-$$"
mkdir -p "$host_tmp/wallet"
cp -R "$ADB_WALLET_DIR/." "$host_tmp/wallet"
unzip -p "$iwad_zip" freedoom-0.13.0/freedoom1.wad \
  >"$host_tmp/freedoom1.wad"
[[ "$(shasum -a 256 "$host_tmp/freedoom1.wad" | awk '{print $1}')" == \
  "$iwad_sha" ]] || {
  printf 'Freedoom IWAD provenance mismatch\n' >&2;exit 1; }
chmod -R go-rwx "$host_tmp"

docker exec "$container" install -d -m 700 "$remote" "$remote/wallet"
docker cp "$host_tmp/wallet/." "$container:$remote/wallet" >/dev/null
docker cp "$host_tmp/freedoom1.wad" \
  "$container:$remote/freedoom1.wad" >/dev/null
docker cp "$root/tools/mochadoom/DoomMochaIwadLoader.java" \
  "$container:$remote/DoomMochaIwadLoader.java" >/dev/null
printf '%s\n' "$ADB_PASSWORD" | docker exec -i "$container" sh -c \
  "umask 077; cat > '$remote/password'"
docker exec -u 0 "$container" chown -R oracle:oinstall "$remote"
docker exec "$container" chmod -R go-rwx "$remote"
docker exec "$container" "$java_home/jdk/bin/javac" --release 11 \
  -cp "$java_home/jdbc/lib/ojdbc11.jar" -d "$remote" \
  "$remote/DoomMochaIwadLoader.java"

if ! docker exec -e "TNS_ADMIN=$remote/wallet" "$container" sh -c \
  'password=$1; shift; exec "$@" < "$password"' sh "$remote/password" \
  "$java_home/jdk/bin/java" \
  -cp "$remote:$java_home/jdbc/lib/ojdbc11.jar" DoomMochaIwadLoader \
  "jdbc:oracle:thin:@$ADB_CONNECTION_STRING" "$ADB_USERNAME" \
  "$remote/freedoom1.wad" "$iwad_sha" "$revision" \
  >"$host_tmp/iwad.log" 2>&1; then
  printf 'Autonomous IWAD load failed (private diagnostics discarded)\n' >&2
  exit 1
fi
printf 'PASS T11.1-CLOUD-ASSETS pinned IWAD loaded with database SHA fence\n'
