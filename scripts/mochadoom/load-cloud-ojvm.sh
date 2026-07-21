#!/usr/bin/env bash
set -Eeuo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
jar="${1:-}"
metadata="${2:-}"
container="${DOOMDB_JAVA_TOOL_CONTAINER:-$(docker compose -f "$root/compose.yaml" ps -q db)}"
java_home="${DOOMDB_JAVA_TOOL_HOME:-/opt/oracle/product/26ai/dbhomeFree}"
iwad_zip="$root/vendor/freedoom/0.13.0/freedoom-0.13.0.zip"
iwad_sha="7323bcc168c5a45ff10749b339960e98314740a734c30d4b9f3337001f9e703d"
revision="c0af1322ee5fd168b5cf8aaaf504cab2d1aabe93"
host_tmp=''; remote=''

[[ -f "$jar" && -f "$metadata" ]] || { printf 'OJVM artifact is absent\n' >&2; exit 2; }
for name in ADB_CONNECTION_STRING ADB_USERNAME ADB_PASSWORD ADB_WALLET_DIR; do
  [[ -n "${!name:-}" ]] || { printf 'required environment variable is absent: %s\n' "$name" >&2; exit 2; }
done
[[ -n "$container" ]] || { printf 'pinned Java/loadjava tool container is unavailable\n' >&2; exit 2; }
[[ -d "$ADB_WALLET_DIR" && ! -L "$ADB_WALLET_DIR" ]] || { printf 'wallet directory is invalid\n' >&2; exit 2; }
for tool in docker unzip shasum node; do command -v "$tool" >/dev/null || {
  printf '%s is unavailable\n' "$tool" >&2; exit 2; }; done

node - "$jar" "$metadata" <<'NODE'
import assert from 'node:assert/strict';import crypto from 'node:crypto';import fs from 'node:fs';
const [jar,metadataPath]=process.argv.slice(2),metadata=JSON.parse(fs.readFileSync(metadataPath));
assert.equal(metadata.schema,1);assert.equal(metadata.javaRelease,8);assert.equal(metadata.classCount,830);
assert.equal(metadata.revision,'c0af1322ee5fd168b5cf8aaaf504cab2d1aabe93');
assert.equal(crypto.createHash('sha256').update(fs.readFileSync(jar)).digest('hex'),metadata.jarSha256);
NODE

cleanup(){
  [[ -z "$remote" ]] || docker exec "$container" rm -rf "$remote" >/dev/null 2>&1 || true
  [[ -z "$host_tmp" ]] || rm -rf "$host_tmp"
}
trap cleanup EXIT
host_tmp="$(mktemp -d "${TMPDIR:-/tmp}/doomdb-cloud-ojvm.XXXXXX")"
remote="/tmp/doomdb-cloud-ojvm-$$"
mkdir -p "$host_tmp/wallet"
cp -R "$ADB_WALLET_DIR/." "$host_tmp/wallet"
unzip -p "$iwad_zip" freedoom-0.13.0/freedoom1.wad >"$host_tmp/freedoom1.wad"
[[ "$(shasum -a 256 "$host_tmp/freedoom1.wad" | awk '{print $1}')" == "$iwad_sha" ]] || {
  printf 'Freedoom IWAD provenance mismatch\n' >&2; exit 1; }
chmod -R go-rwx "$host_tmp"

docker exec "$container" install -d -m 700 "$remote" "$remote/wallet"
docker cp "$host_tmp/wallet/." "$container:$remote/wallet" >/dev/null
docker cp "$host_tmp/freedoom1.wad" "$container:$remote/freedoom1.wad" >/dev/null
docker cp "$jar" "$container:$remote/mochadoom-ojvm.jar" >/dev/null
docker cp "$root/tools/mochadoom/DoomMochaIwadLoader.java" "$container:$remote/DoomMochaIwadLoader.java" >/dev/null
docker exec "$container" chmod -R go-rwx "$remote"
docker exec "$container" "$java_home/jdk/bin/javac" --release 11 \
  -cp "$java_home/jdbc/lib/ojdbc11.jar" -d "$remote" "$remote/DoomMochaIwadLoader.java"

if ! printf '%s\n' "$ADB_PASSWORD" | docker exec -i -e "TNS_ADMIN=$remote/wallet" \
  "$container" "$java_home/bin/loadjava" -oci8 -force -resolve \
  -user "$ADB_USERNAME@$ADB_CONNECTION_STRING" "$remote/mochadoom-ojvm.jar" \
  >"$host_tmp/loadjava.log" 2>&1; then
  printf 'client-side loadjava failed (private diagnostics discarded)\n' >&2; exit 1
fi
if ! printf '%s\n' "$ADB_PASSWORD" | docker exec -i -e "TNS_ADMIN=$remote/wallet" \
  "$container" "$java_home/jdk/bin/java" \
  -cp "$remote:$java_home/jdbc/lib/ojdbc11.jar" DoomMochaIwadLoader \
  "jdbc:oracle:thin:@$ADB_CONNECTION_STRING" "$ADB_USERNAME" \
  "$remote/freedoom1.wad" "$iwad_sha" "$revision" \
  >"$host_tmp/iwad.log" 2>&1; then
  printf 'Autonomous IWAD load failed (private diagnostics discarded)\n' >&2; exit 1
fi
printf 'PASS T11.1-CLOUD-OJVM (830 Java 8 classes and pinned IWAD loaded client-side)\n'
