#!/usr/bin/env bash
set -Eeuo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
profiles_file="$root/tests/fixtures/wan-profiles.json"
cloud_upstream="${DOOMDB_WAN_UPSTREAM:-}"
cloud_play_path="${DOOMDB_WAN_PLAY_PATH:-}"
db_sql_client="${DOOMDB_DB_SQL_CLIENT:-$root/scripts/db_sql.sh}"
duration="${DOOMDB_MLE_WAN_SECONDS:-600}"
warmup="${DOOMDB_MLE_WAN_WARMUP_SECONDS:-90}"
startup_timeout="${DOOMDB_MLE_WAN_STARTUP_TIMEOUT_MS:-600000}"
tag="${PMLE_EVIDENCE_TAG:-2026-07-23-wan}"
requested_long_poll="${DOOMDB_WAN_LONG_POLL_ENABLED:-1}"
requested_hold_ms="${DOOMDB_WAN_HOLD_MS:-500}"
qualification_requested="${DOOMDB_WAN_QUALIFICATION:-NO}"
preflight_only="${DOOMDB_WAN_PREFLIGHT_ONLY:-NO}"
profile_filter="${DOOMDB_WAN_PROFILE_FILTER:-}"
approval_file="${DOOMDB_WAN_APPROVAL_FILE:-$root/artifacts/performance/pmle-wan/wait-free-transport-amendment-2026-07-26.md}"
record_parser="$root/scripts/require-db-record.mjs"

[[ "$duration" =~ ^[1-9][0-9]*$ && "$duration" -ge 20 && "$duration" -le 1800 ]] ||
  { printf 'invalid WAN duration: %s\n' "$duration" >&2;exit 2; }
[[ "$warmup" =~ ^[0-9]+$ && "$warmup" -le 600 ]] ||
  { printf 'invalid WAN warmup: %s\n' "$warmup" >&2;exit 2; }
[[ "$startup_timeout" =~ ^[1-9][0-9]*$ &&
   "$startup_timeout" -ge 60000 && "$startup_timeout" -le 600000 ]] ||
  { printf 'invalid WAN startup timeout: %s\n' "$startup_timeout" >&2;exit 2; }
[[ "$tag" =~ ^[A-Za-z0-9._-]+$ ]] ||
  { printf 'invalid evidence tag: %s\n' "$tag" >&2;exit 2; }
[[ "$requested_long_poll" =~ ^[01]$ ]] ||
  { printf 'invalid WAN long-poll mode: %s\n' "$requested_long_poll" >&2;exit 2; }
[[ "$requested_hold_ms" =~ ^[0-9]+$ && "$requested_hold_ms" -le 500 ]] ||
  { printf 'invalid WAN hold: %s\n' "$requested_hold_ms" >&2;exit 2; }
[[ "$qualification_requested" == NO ||
   "$qualification_requested" == YES ]] ||
  { printf 'invalid WAN qualification request\n' >&2;exit 2; }
[[ "$preflight_only" == NO || "$preflight_only" == YES ]] ||
  { printf 'invalid WAN preflight request\n' >&2;exit 2; }
[[ -z "$profile_filter" || "$profile_filter" =~ ^[a-z0-9-]+$ ]] ||
  { printf 'invalid WAN profile filter\n' >&2;exit 2; }
if [[ "$requested_long_poll" -eq 0 && "$requested_hold_ms" -ne 0 ]]; then
  printf 'wait-free WAN transport requires zero hold\n' >&2;exit 2
fi
[[ -s "$profiles_file" ]] || { printf 'WAN profile file missing\n' >&2;exit 2; }

mode=OFF
transport_legs=2
classification=DIAGNOSTIC_NOT_GATE
approval_sha256=NONE
[[ "$requested_long_poll" -eq 0 ]] || {
  mode=ON
  transport_legs=1
}
if [[ "$qualification_requested" == YES ]]; then
  [[ -z "$profile_filter" ]] ||
    { printf 'qualification may not filter WAN profiles\n' >&2;exit 2; }
  [[ "$requested_long_poll" -eq 0 && "$requested_hold_ms" -eq 0 ]] ||
    { printf 'qualification is authorized only for wait-free transport\n' >&2;exit 2; }
  [[ "$duration" -eq 600 && "$warmup" -eq 90 ]] ||
    { printf 'WAN qualification requires 600 scored seconds and 90 warmup seconds\n' >&2;exit 2; }
  [[ -s "$approval_file" && ! -L "$approval_file" ]] ||
    { printf 'wait-free charter approval artifact is absent\n' >&2;exit 2; }
  grep -Fqx \
    'WAN_TRANSPORT_AMENDMENT|APPROVED|authority=Brian Martin|transport=WAIT_FREE_IMMEDIATE_BATCHING|transport_legs=2' \
    "$approval_file" ||
    { printf 'wait-free charter approval marker is absent\n' >&2;exit 2; }
  approval_sha256="$(shasum -a 256 "$approval_file" | awk '{print $1}')"
  classification=QUALIFICATION
fi

if [[ "$preflight_only" == YES ]]; then
  printf 'PMLE_WAN_PREFLIGHT|PASS|long_poll=%s|hold_ms=%s|transport_legs=%s|classification=%s|duration=%s|warmup=%s|approval_sha256=%s\n' \
    "$mode" "$requested_hold_ms" "$transport_legs" "$classification" \
    "$duration" "$warmup" "$approval_sha256"
  exit 0
fi

busy_host="$(ps ax -o command= | awk '
  /[d]ocker (build|compose .* build)|[b]uild-simulation[.]sh|[m]vn .*package|[j]avac|[v]erify-local-e2e/ {print}
')"
if [[ -n "$busy_host" ]]; then
  printf 'WAN matrix requires a quiet host; active work:\n%s\n' "$busy_host" >&2
  exit 1
fi

evidence="$root/artifacts/performance/pmle-wan"
mkdir -p "$evidence"
matrix_log="$evidence/matrix-${tag}.log"
[[ ! -e "$matrix_log" ]] ||
  { printf 'WAN matrix evidence already exists: %s\n' "$matrix_log" >&2;exit 1; }

proxy_pid=''
proxy_log=''
long_poll_enabled=0
cleanup_proxy() {
  if [[ -n "$proxy_pid" ]] && kill -0 "$proxy_pid" 2>/dev/null; then
    kill "$proxy_pid" 2>/dev/null || true
    wait "$proxy_pid" 2>/dev/null || true
  fi
  proxy_pid=''
  [[ -z "$proxy_log" ]] || rm -f "$proxy_log"
  proxy_log=''
}
cleanup() {
  cleanup_proxy
  if [[ "$long_poll_enabled" -eq 1 ]]; then
    "$db_sql_client" - >/dev/null <<'SQL' || true
update doom_match_poll_capacity set long_poll_enabled=0 where capacity_id=1;
commit;
SQL
  fi
}
trap cleanup EXIT

mapfile_compat() {
  node - "$profiles_file" "$cloud_upstream" "$profile_filter" <<'NODE'
const fs=require('node:fs');
const config=JSON.parse(fs.readFileSync(process.argv[2],'utf8'));
const override=process.argv[3];
const filter=process.argv[4];
if(config.schema!==1||!Number.isInteger(config.seed)||config.seed<=0)
  throw Error('invalid WAN profile metadata');
for(const profile of config.profiles) {
  if(filter&&profile.name!==filter)continue;
  if(!/^[a-z0-9-]+$/.test(profile.name)||
      !Number.isInteger(profile.port)||
      !Number.isFinite(profile.rttMs)||
      !Number.isFinite(profile.jitterMs))
    throw Error('invalid WAN profile');
  process.stdout.write([
    profile.name,profile.port,profile.rttMs,profile.jitterMs,
    config.seed,override||config.upstream
  ].join('|')+'\n');
}
NODE
}

{
  printf 'PMLE_HOST_QUIESCENCE|PASS|docker_builds=0|compiles=0|verifiers=0\n'
  printf 'PMLE_WAN_MATRIX|BEGIN|duration=%s|warmup=%s|profiles_sha256=%s\n' \
    "$duration" "$warmup" "$(shasum -a 256 "$profiles_file" | awk '{print $1}')"
  "$db_sql_client" \
    "$root/probes/mle/teavm-engine/environment-metadata.sql"
  "$db_sql_client" \
    "$root/probes/mle/teavm-engine/artifact-metadata.sql"
} | tee "$matrix_log"
node "$record_parser" --one "$matrix_log" 'PMLE_ENVIRONMENT|' >/dev/null
node "$record_parser" "$matrix_log" 'PMLE_ARTIFACT|' \
  'PMLE_ARTIFACT|source_bytes=1081335|source_sha256=5ec18cbe4cff7192d384e81d1010e0133d357d44ff17fa65821e1489c4fd1ee3|table_bytes=180272|table_sha256=058cd0df9444131b356762a096fd422d5131ac3aea91163aee056e8ad4965b44'
if rg -n '(^|[[:space:]])(SP2-|ORA-|PLS-|[A-Za-z0-9_]+ not found$)' \
    "$matrix_log"; then
  printf '%s\n' 'WAN database preflight emitted a SQLcl or Oracle error' >&2
  exit 1
fi
"$db_sql_client" - >/dev/null <<SQL
update doom_match_poll_capacity set long_poll_enabled=$requested_long_poll where capacity_id=1;
commit;
SQL
long_poll_enabled=$requested_long_poll
printf '%s\n' \
  "PMLE_WAN_TRANSPORT|long_poll=$mode|hold_ms=$requested_hold_ms|transport_legs=$transport_legs|classification=$classification|approval_sha256=$approval_sha256|ords_pool_sessions=6|pool_reserve=2|max_held_polls=4|resmgr_running_sessions=2|worker_reserve=1|max_concurrent_poll_returns=1|background_refocus=ON" \
  "PMLE_WAN_PRESENTATION_CONTRACT|max_playout_tics=6|low_rtt_max_selected_tics=6|controller=FREE_CLOCK_CONFIRMED_OCCUPANCY_SETPOINT|setpoint=selected_depth|acceleration_margin_tics=2|deceleration_margin_tics=2|max_decelerated_interval_ms=31.4|presentation_lag_p95_formula=selected_max+batch_count_p95+2|confirmed_to_presented_p95_formula=(selected_max+batch_count_p95+2)*1000/35|presentation_interval_p99_ms=57.143|depth_comparison=DEPTH6_COMPARISON" \
  | tee -a "$matrix_log"

profile_count=0
while IFS='|' read -r name port rtt jitter seed upstream; do
  profile_count=$((profile_count + 1))
  profile_log="$evidence/${name}-${tag}.log"
  [[ ! -e "$profile_log" ]] ||
    { printf 'WAN profile evidence already exists: %s\n' "$profile_log" >&2;exit 1; }
  proxy_log="$(mktemp "${TMPDIR:-/tmp}/doomdb-wan-proxy.XXXXXX")"
  node "$root/tests/wan-latency-proxy.mjs" \
    "--port=$port" "--rtt-ms=$rtt" "--jitter-ms=$jitter" \
    "--seed=$seed" "--upstream=$upstream" >"$proxy_log" 2>&1 &
  proxy_pid=$!
  ready=0
  for _ in $(seq 1 120); do
    if grep -q 'PMLE_WAN_PROXY|READY' "$proxy_log"; then ready=1;break;fi
    kill -0 "$proxy_pid" 2>/dev/null || break
    sleep .25
  done
  cat "$proxy_log" | tee -a "$profile_log" "$matrix_log"
  [[ "$ready" -eq 1 ]] || { printf 'WAN proxy failed for %s\n' "$name" >&2;exit 1; }
  {
    printf 'PMLE_WAN_PROFILE|BEGIN|name=%s|rtt_ms=%s|jitter_ms=%s|seed=%s\n' \
      "$name" "$rtt" "$jitter" "$seed"
    DOOMDB_PLAY_BASE_URL="http://127.0.0.1:$port" \
    DOOMDB_PLAY_PATH="${cloud_play_path:-/play/multiplayer}" \
    DOOMDB_SOAK_HEALTH_URL="http://127.0.0.1:$port/ords/doom/public_health/" \
    DOOMDB_DB_SQL_CLIENT="$db_sql_client" \
    DOOMDB_MULTIPLAYER_SOAK_SECONDS="$duration" \
    DOOMDB_MULTIPLAYER_SOAK_WARMUP_SECONDS="$warmup" \
    DOOMDB_MULTIPLAYER_STARTUP_TIMEOUT_MS="$startup_timeout" \
    DOOMDB_WAN_GATE=1 \
    DOOMDB_WAN_RTT_MS="$rtt" \
    DOOMDB_WAN_JITTER_MS="$jitter" \
    DOOMDB_WAN_HOLD_MS="$requested_hold_ms" \
    DOOMDB_WAN_TRANSPORT_LEGS="$transport_legs" \
    DOOMDB_WAN_BACKGROUND_SCENARIO=1 \
    DOOMDB_MANAGED_ADB=1 \
      bash "$root/tests/verify-p13.5-multiplayer-soak.sh"
  } 2>&1 | tee -a "$profile_log" "$matrix_log"
  grep -q "PMLE_WAN_GATE|PASS|rtt_ms=$rtt|jitter_ms=$jitter|seconds=$duration" \
    "$profile_log" ||
    { printf 'WAN PASS marker missing for %s\n' "$name" >&2;exit 1; }
  printf 'PMLE_WAN_PROFILE|PASS|name=%s\n' "$name" | tee -a "$profile_log" "$matrix_log"
  cleanup_proxy
done < <(mapfile_compat)

expected_profiles=3
[[ -z "$profile_filter" ]] || expected_profiles=1
[[ "$profile_count" -eq "$expected_profiles" ]] ||
  { printf 'WAN matrix expected %s profiles, found %s\n' \
      "$expected_profiles" "$profile_count" >&2;exit 1; }
printf 'PMLE_WAN_MATRIX|PASS|profiles=%s|duration=%s|warmup=%s|classification=%s|transport_legs=%s|approval_sha256=%s\n' \
  "$profile_count" "$duration" "$warmup" "$classification" \
  "$transport_legs" "$approval_sha256" | tee -a "$matrix_log"
