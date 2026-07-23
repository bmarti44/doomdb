#!/usr/bin/env bash
set -Eeuo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
output="${1:-}"
metadata="${2:-}"
release="${DOOMDB_OJVM_JAVA_RELEASE:-8}"
revision="c0af1322ee5fd168b5cf8aaaf504cab2d1aabe93"
extra_patch="${DOOMDB_MOCHA_EXTRA_PATCH:-}"
extra_adapter_patch="${DOOMDB_MOCHA_EXTRA_ADAPTER_PATCH:-}"
extra_adapter_source="${DOOMDB_MOCHA_EXTRA_ADAPTER_SOURCE:-}"
expected_class_count="${DOOMDB_MOCHA_EXPECTED_CLASS_COUNT:-830}"
container="${DOOMDB_JAVA_TOOL_CONTAINER:-$(docker compose -f "$root/compose.yaml" ps -q db)}"
java_home="${DOOMDB_JAVA_TOOL_HOME:-/opt/oracle/product/26ai/dbhomeFree}"
host_tmp=''; remote=''

[[ -n "$output" && -n "$metadata" ]] || {
  printf 'usage: build-ojvm-jar.sh OUTPUT_JAR OUTPUT_METADATA\n' >&2; exit 2;
}
[[ "$release" == 8 ]] || { printf 'cloud-compatible Java release must be 8\n' >&2; exit 2; }
[[ -n "$container" ]] || { printf 'pinned Java tool container is unavailable\n' >&2; exit 2; }
[[ "$(git -C "$root/third_party/mochadoom" rev-parse HEAD)" == "$revision" ]] || {
  printf 'Mocha Doom source revision drift\n' >&2; exit 1;
}
for tool in docker git patch perl rg shasum; do command -v "$tool" >/dev/null || {
  printf '%s is unavailable\n' "$tool" >&2; exit 2; }; done

cleanup(){
  [[ -z "$remote" ]] || docker exec "$container" rm -rf "$remote" >/dev/null 2>&1 || true
  [[ -z "$host_tmp" ]] || rm -rf "$host_tmp"
}
trap cleanup EXIT
host_tmp="$(mktemp -d "${TMPDIR:-/tmp}/doomdb-ojvm-build.XXXXXX")"
remote="/tmp/doomdb-ojvm-build-$$"
mkdir -p "$host_tmp/source" "$host_tmp/adapter"
cp -R "$root/third_party/mochadoom/src/." "$host_tmp/source"
cp -R "$root/java/mochadoom-ojvm/src/." "$host_tmp/adapter"
find "$host_tmp/source" -name '*.java' -exec perl -pi -e 's/\r$//' {} +
for overlay in "$root"/patches/mochadoom/*.patch; do
  patch --batch --forward --ignore-whitespace -d "$host_tmp/source" -p2 <"$overlay" >/dev/null
done
if [[ -n "$extra_patch" ]]; then
  IFS=',' read -r -a extra_patches <<<"$extra_patch"
  for patch_path in "${extra_patches[@]}"; do
    [[ -f "$patch_path" ]] || {
      printf 'extra Mocha patch not found: %s\n' "$patch_path" >&2; exit 2;
    }
    patch --batch --forward --ignore-whitespace \
      -d "$host_tmp/source" -p2 <"$patch_path" >/dev/null
  done
fi
if [[ -n "$extra_adapter_source" ]]; then
  [[ -d "$extra_adapter_source" ]] || { printf 'extra adapter source not found: %s\n' "$extra_adapter_source" >&2; exit 2; }
  cp -R "$extra_adapter_source/." "$host_tmp/adapter"
fi
if [[ -n "$extra_adapter_patch" ]]; then
  [[ -f "$extra_adapter_patch" ]] || { printf 'extra adapter patch not found: %s\n' "$extra_adapter_patch" >&2; exit 2; }
  patch --batch --forward --ignore-whitespace -d "$host_tmp/adapter" -p2 <"$extra_adapter_patch" >/dev/null
fi
find "$host_tmp/source" -name '*.orig' -delete
find "$host_tmp/source" -name '*.java' -exec perl -pi -e \
  's/System\.exit\((-?[0-9]+)\);/doomdb.mocha.OjvmExit.block($1);/g' {} +
if rg -n 'System\.exit\(' "$host_tmp/source" >/dev/null; then
  printf 'unfenced Mocha Doom System.exit path remains\n' >&2; exit 1
fi

docker exec "$container" mkdir -p "$remote/source" "$remote/adapter" "$remote/classes"
docker cp "$host_tmp/source/." "$container:$remote/source" >/dev/null
docker cp "$host_tmp/adapter/." "$container:$remote/adapter" >/dev/null
if ! docker exec "$container" bash -lc \
  "find '$remote/source' '$remote/adapter' -name '*.java' -print0 | \
   xargs -0 '$java_home/jdk/bin/javac' --release '$release' -encoding UTF-8 \
     -J-Xms64m -J-Xmx256m -cp '$java_home/jdbc/lib/ojdbc11.jar' \
     -d '$remote/classes' >'$remote/javac.log' 2>&1"; then
  printf 'Mocha OJVM compilation failed\n' >&2; exit 1
fi
docker exec "$container" bash -lc \
  "find '$remote/classes' -name '*.class' -exec touch -t 200001010000 {} +; \
   cd '$remote/classes'; find . -name '*.class' -print | LC_ALL=C sort >'$remote/classes.list'; \
   '$java_home/jdk/bin/jar' --create --file '$remote/mochadoom-ojvm.jar' \
     --no-manifest @'$remote/classes.list'"
docker cp "$container:$remote/mochadoom-ojvm.jar" "$host_tmp/mochadoom-ojvm.jar" >/dev/null
class_count="$(docker exec "$container" sh -c "wc -l <'$remote/classes.list'" | tr -d '[:space:]')"
jar_sha256="$(shasum -a 256 "$host_tmp/mochadoom-ojvm.jar" | awk '{print $1}')"
[[ "$class_count" == "$expected_class_count" ]] || {
  printf 'unexpected class count %s (expected %s)\n' "$class_count" "$expected_class_count" >&2; exit 1;
}

mkdir -p "$(dirname "$output")" "$(dirname "$metadata")"
chmod 600 "$host_tmp/mochadoom-ojvm.jar"
mv "$host_tmp/mochadoom-ojvm.jar" "$output"
node - "$metadata" "$release" "$revision" "$class_count" "$jar_sha256" <<'NODE'
import fs from 'node:fs';
const [path,release,revision,classCount,jarSha256]=process.argv.slice(2);
fs.writeFileSync(path,`${JSON.stringify({schema:1,javaRelease:Number(release),revision,classCount:Number(classCount),jarSha256})}\n`,{mode:0o600});
NODE
printf 'PASS MOCHADOOM-OJVM-ARTIFACT classes=%s release=%s sha256=%s\n' \
  "$class_count" "$release" "$jar_sha256"
