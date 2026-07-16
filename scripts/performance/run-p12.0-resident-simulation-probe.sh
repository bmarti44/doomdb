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

if [[ "${DOOMDB_SKIP_LOADJAVA:-0}" != 1 ]]; then
docker exec "$container" mkdir -p "$tmp"
docker cp "$root/scripts/performance/DoomResidentSimulationBench.java" \
  "$container:$tmp/DoomResidentSimulationBench.java" >/dev/null
docker cp "$root/scripts/performance/DoomOracleNumberParityBench.java" \
  "$container:$tmp/DoomOracleNumberParityBench.java" >/dev/null
docker cp "$root/scripts/performance/DoomSimCatalogBench.java" \
  "$container:$tmp/DoomSimCatalogBench.java" >/dev/null
docker cp "$root/scripts/performance/DoomPlayerMovementBench.java" \
  "$container:$tmp/DoomPlayerMovementBench.java" >/dev/null
docker cp "$root/scripts/performance/DoomCommonActorTickBench.java" \
  "$container:$tmp/DoomCommonActorTickBench.java" >/dev/null
docker cp "$root/scripts/performance/DoomActorWakeBench.java" \
  "$container:$tmp/DoomActorWakeBench.java" >/dev/null
docker cp "$root/scripts/performance/DoomRetainedLosBench.java" \
  "$container:$tmp/DoomRetainedLosBench.java" >/dev/null
docker cp "$root/scripts/performance/DoomMonsterChaseBench.java" \
  "$container:$tmp/DoomMonsterChaseBench.java" >/dev/null
docker cp "$root/scripts/performance/DoomFreshDeathTickBench.java" \
  "$container:$tmp/DoomFreshDeathTickBench.java" >/dev/null
docker cp "$root/scripts/performance/DoomRetainedWorldStateBench.java" \
  "$container:$tmp/DoomRetainedWorldStateBench.java" >/dev/null
docker cp "$root/scripts/performance/DoomBspKernelBench.java" \
  "$container:$tmp/DoomBspKernelBench.java" >/dev/null
docker cp "$root/scripts/performance/DoomRetainedRenderSceneBench.java" \
  "$container:$tmp/DoomRetainedRenderSceneBench.java" >/dev/null
docker cp "$root/scripts/performance/DoomUnifiedActorStateBench.java" \
  "$container:$tmp/DoomUnifiedActorStateBench.java" >/dev/null
docker exec "$container" "$java_home/jdk/bin/javac" --release 11 \
  -cp "$java_home/jdbc/lib/ojdbc11.jar" "$tmp/DoomResidentSimulationBench.java" \
  "$tmp/DoomOracleNumberParityBench.java" "$tmp/DoomSimCatalogBench.java" \
  "$tmp/DoomPlayerMovementBench.java" "$tmp/DoomCommonActorTickBench.java" \
  "$tmp/DoomActorWakeBench.java" "$tmp/DoomRetainedLosBench.java" \
  "$tmp/DoomMonsterChaseBench.java" "$tmp/DoomFreshDeathTickBench.java" \
  "$tmp/DoomRetainedWorldStateBench.java" "$tmp/DoomBspKernelBench.java" \
  "$tmp/DoomRetainedRenderSceneBench.java" "$tmp/DoomUnifiedActorStateBench.java"
docker exec "$container" sh -c \
  "exec '$java_home/bin/loadjava' -force -resolve -user DOOM@FREEPDB1 \
  '$tmp/DoomResidentSimulationBench.class' '$tmp/DoomOracleNumberParityBench.class' \
  '$tmp/DoomSimCatalogBench.class' '$tmp/DoomPlayerMovementBench.class' \
  '$tmp'/DoomCommonActorTickBench*.class \
  '$tmp'/DoomActorWakeBench*.class \
  '$tmp'/DoomRetainedLosBench*.class \
  '$tmp'/DoomMonsterChaseBench*.class \
  '$tmp'/DoomFreshDeathTickBench*.class \
  '$tmp'/DoomRetainedWorldStateBench*.class \
  '$tmp'/DoomBspKernelBench*.class \
  '$tmp'/DoomRetainedRenderSceneBench*.class \
  '$tmp'/DoomUnifiedActorStateBench*.class \
  < /run/secrets/doom_password"
fi

run_sql "$root/scripts/performance/ojvm-resident-simulation-calls.sql"
run_sql "$root/scripts/performance/ojvm-number-parity-calls.sql"
run_sql "$root/scripts/performance/ojvm-sim-catalog-calls.sql"
run_sql "$root/scripts/performance/ojvm-common-actor-calls.sql"
run_sql "$root/scripts/performance/ojvm-actor-wake-calls.sql"
run_sql "$root/scripts/performance/ojvm-retained-los-calls.sql"
run_sql "$root/scripts/performance/ojvm-monster-chase-calls.sql"
run_sql "$root/scripts/performance/ojvm-fresh-death-calls.sql"
run_sql "$root/scripts/performance/ojvm-retained-world-state-calls.sql"
run_sql "$root/scripts/performance/ojvm-retained-render-scene-calls.sql"
run_sql "$root/scripts/performance/ojvm-unified-actor-state-calls.sql"
run_sql "$root/sql/accel/019_simulation_kernel_pack.sql"
run_sql "$root/scripts/performance/ojvm-resident-simulation-parity.sql"
run_sql "$root/scripts/performance/ojvm-number-parity.sql"
run_sql "$root/scripts/performance/ojvm-sim-catalog-parity.sql"
run_sql "$root/scripts/performance/ojvm-retained-los-parity.sql"
run_sql "$root/scripts/performance/ojvm-sim-movement-parity.sql"
run_sql "$root/scripts/performance/ojvm-resident-movement-parity.sql"
run_sql "$root/scripts/performance/ojvm-common-actor-parity.sql"
run_sql "$root/scripts/performance/ojvm-actor-wake-parity.sql"
run_sql "$root/scripts/performance/ojvm-actor-pain-parity.sql"
run_sql "$root/scripts/performance/ojvm-actor-state-tick-parity.sql"
run_sql "$root/scripts/performance/ojvm-actor-corpse-state-parity.sql"
run_sql "$root/scripts/performance/ojvm-monster-chase-parity.sql"
run_sql "$root/scripts/performance/ojvm-fresh-death-parity.sql"
run_sql "$root/scripts/performance/ojvm-retained-world-state-parity.sql"
run_sql "$root/scripts/performance/ojvm-unified-world-owner-parity.sql"
run_sql "$root/scripts/performance/ojvm-unified-actor-state-parity.sql"
run_sql "$root/scripts/performance/ojvm-unified-actor-attack-parity.sql"
run_sql "$root/scripts/performance/ojvm-unified-tic-parity.sql"
run_sql "$root/scripts/performance/ojvm-retained-render-dtic-parity.sql"
run_sql "$root/scripts/performance/ojvm-unified-recovery-parity.sql"
run_sql "$root/scripts/performance/ojvm-unified-command-tic-parity.sql"
run_sql "$root/scripts/performance/ojvm-resident-simulation-benchmark.sql"
