#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
container="$(docker compose -f "$root/compose.yaml" ps -q db)"
java_home=/opt/oracle/product/26ai/dbhomeFree
tmp=/tmp/doomdb-retained-render-scene-$$
if [[ -z "$container" ]]; then printf 'database container is not running\n' >&2;exit 1;fi
cleanup(){ docker exec "$container" rm -rf "$tmp" >/dev/null 2>&1||true; }
trap cleanup EXIT
run_sql(){
  { printf 'connect DOOM/"';docker exec "$container" sh -c \
      "tr -d '\\r\\n' < /run/secrets/doom_password";printf '"@FREEPDB1\n';cat "$1"; }|
    docker exec -i "$container" "$java_home/bin/sqlplus" -s /nolog
}
docker exec "$container" mkdir -p "$tmp"
for source in DoomBspKernelBench.java DoomRetainedRenderSceneBench.java;do
  docker cp "$root/scripts/performance/$source" "$container:$tmp/$source" >/dev/null
done
docker exec "$container" "$java_home/jdk/bin/javac" --release 11 \
  -cp "$java_home/jdbc/lib/ojdbc11.jar" "$tmp/DoomBspKernelBench.java" \
  "$tmp/DoomRetainedRenderSceneBench.java"
docker exec "$container" sh -c \
  "exec '$java_home/bin/loadjava' -force -resolve -user DOOM@FREEPDB1 \
  '$tmp'/DoomBspKernelBench*.class '$tmp'/DoomRetainedRenderSceneBench*.class \
  < /run/secrets/doom_password"
run_sql "$root/scripts/performance/ojvm-renderer-warmup.sql"
run_sql <(printf '%s\n' 'whenever sqlerror exit failure rollback' \
  "select 'RETAINED_RENDER_SCENE_COMPILED='||dbms_java.compile_class('DoomRetainedRenderSceneBench') from dual;" \
  'exit')
run_sql "$root/sql/accel/017_renderer_dynamic_snapshot.sql"
run_sql "$root/scripts/performance/ojvm-retained-render-scene-calls.sql"
printf 'retained render scene deployed\n'
