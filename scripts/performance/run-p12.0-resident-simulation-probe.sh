#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
container="$(docker compose -f "$root/compose.yaml" ps -q db)"
java_home="/opt/oracle/product/26ai/dbhomeFree"
tmp="/tmp/doomdb-resident-simulation-$$"

if [[ -z "$container" ]]; then
  printf 'database container is not running\n' >&2
  exit 1
fi

cleanup() {
  docker exec "$container" rm -rf "$tmp" >/dev/null 2>&1 || true
}
trap cleanup EXIT

run_sql() {
  local script="$1"
  {
    printf 'connect DOOM/"'
    docker exec "$container" sh -c "tr -d '\r\n' < /run/secrets/doom_password"
    printf '"@FREEPDB1\n'
    cat "$script"
  } | docker exec -i "$container" "$java_home/bin/sqlplus" -s /nolog
}

docker exec "$container" mkdir -p "$tmp"
docker cp "$root/scripts/performance/DoomResidentSimulationBench.java" \
  "$container:$tmp/DoomResidentSimulationBench.java" >/dev/null
docker exec "$container" "$java_home/jdk/bin/javac" --release 11 \
  "$tmp/DoomResidentSimulationBench.java"
docker exec "$container" sh -c \
  "exec '$java_home/bin/loadjava' -force -resolve -user DOOM@FREEPDB1 \
  '$tmp/DoomResidentSimulationBench.class' < /run/secrets/doom_password"

run_sql "$root/scripts/performance/ojvm-resident-simulation-calls.sql"
run_sql "$root/scripts/performance/ojvm-resident-simulation-parity.sql"
run_sql "$root/scripts/performance/ojvm-resident-simulation-benchmark.sql"
