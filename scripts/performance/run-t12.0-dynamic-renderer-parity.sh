#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
container="$(docker compose -f "$root/compose.yaml" ps -q db)"
java_home=/opt/oracle/product/26ai/dbhomeFree
tmp=/tmp/doomdb-dynamic-renderer-$$

if [[ -z "$container" ]]; then printf 'database container is not running\n' >&2;exit 1;fi
cleanup(){ docker exec "$container" rm -rf "$tmp" >/dev/null 2>&1 || true; }
trap cleanup EXIT
run_sql(){
  { printf 'connect DOOM/"';docker exec "$container" sh -c \
      "tr -d '\\r\\n' < /run/secrets/doom_password";printf '"@FREEPDB1\n';cat "$1"; } |
    docker exec -i "$container" "$java_home/bin/sqlplus" -s /nolog
}

docker exec "$container" mkdir -p "$tmp"
docker cp "$root/scripts/performance/DoomBspKernelBench.java" \
  "$container:$tmp/DoomBspKernelBench.java" >/dev/null
docker cp "$root/scripts/performance/DoomRetainedRenderSceneBench.java" \
  "$container:$tmp/DoomRetainedRenderSceneBench.java" >/dev/null
docker exec "$container" "$java_home/jdk/bin/javac" --release 11 \
  -cp "$java_home/jdbc/lib/ojdbc11.jar" "$tmp/DoomBspKernelBench.java" \
  "$tmp/DoomRetainedRenderSceneBench.java"
docker exec "$container" sh -c \
  "exec '$java_home/bin/loadjava' -force -resolve -user DOOM@FREEPDB1 \
  '$tmp'/DoomBspKernelBench*.class '$tmp'/DoomRetainedRenderSceneBench*.class \
  < /run/secrets/doom_password"
run_sql "$root/sql/accel/017_renderer_dynamic_snapshot.sql"
run_sql "$root/sql/accel/020_ojvm_renderer_calls.sql"
run_sql "$root/scripts/performance/ojvm-renderer-dynamic-parity.sql"
run_sql "$root/scripts/performance/ojvm-renderer-dynamic-benchmark.sql"
run_sql "$root/scripts/performance/ojvm-retained-render-scene-benchmark.sql"
