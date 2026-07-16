#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source_file="$root/scripts/performance/DoomBspKernelBench.java"
container="$(docker compose -f "$root/compose.yaml" ps -q db)"

if [[ -z "$container" ]]; then
  printf 'database container is not running\n' >&2
  exit 1
fi

tmp="/tmp/doomdb-bsp-kernel-$$"
java_home="/opt/oracle/product/26ai/dbhomeFree"
cleanup() {
  docker exec "$container" rm -rf "$tmp" >/dev/null 2>&1 || true
}
trap cleanup EXIT

docker exec "$container" mkdir -p "$tmp"
docker cp "$source_file" "$container:$tmp/DoomBspKernelBench.java" >/dev/null
docker exec "$container" "$java_home/jdk/bin/javac" \
  -cp "$java_home/jdbc/lib/ojdbc11.jar" "$tmp/DoomBspKernelBench.java"
docker exec "$container" "$java_home/jdk/bin/java" \
  -Xms32m -Xmx64m -XX:+UseSerialGC \
  -cp "$tmp:$java_home/jdbc/lib/ojdbc11.jar" \
  DoomBspKernelBench /run/secrets/doom_password "$@"
