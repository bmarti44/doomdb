#!/usr/bin/env bash
set -Eeuo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
profiles_file="$root/tests/fixtures/wan-profiles.json"
duration="${DOOMDB_MLE_WAN_SECONDS:-600}"
warmup="${DOOMDB_MLE_WAN_WARMUP_SECONDS:-90}"
tag="${PMLE_EVIDENCE_TAG:-2026-07-23-wan}"

[[ "$duration" =~ ^[1-9][0-9]*$ && "$duration" -ge 20 && "$duration" -le 1800 ]] ||
  { printf 'invalid WAN duration: %s\n' "$duration" >&2;exit 2; }
[[ "$warmup" =~ ^[0-9]+$ && "$warmup" -le 600 ]] ||
  { printf 'invalid WAN warmup: %s\n' "$warmup" >&2;exit 2; }
[[ "$tag" =~ ^[A-Za-z0-9._-]+$ ]] ||
  { printf 'invalid evidence tag: %s\n' "$tag" >&2;exit 2; }
[[ -s "$profiles_file" ]] || { printf 'WAN profile file missing\n' >&2;exit 2; }

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
    "$root/scripts/db_sql.sh" - >/dev/null <<'SQL' || true
update doom_match_poll_capacity set long_poll_enabled=0 where capacity_id=1;
commit;
SQL
  fi
}
trap cleanup EXIT

mapfile_compat() {
  node - "$profiles_file" <<'NODE'
const fs=require('node:fs');
const config=JSON.parse(fs.readFileSync(process.argv[2],'utf8'));
if(config.schema!==1||!Number.isInteger(config.seed)||config.seed<=0)
  throw Error('invalid WAN profile metadata');
for(const profile of config.profiles) {
  if(!/^[a-z0-9-]+$/.test(profile.name)||
      !Number.isInteger(profile.port)||
      !Number.isFinite(profile.rttMs)||
      !Number.isFinite(profile.jitterMs))
    throw Error('invalid WAN profile');
  process.stdout.write([
    profile.name,profile.port,profile.rttMs,profile.jitterMs,
    config.seed,config.upstream
  ].join('|')+'\n');
}
NODE
}

{
  printf 'PMLE_HOST_QUIESCENCE|PASS|docker_builds=0|compiles=0|verifiers=0\n'
  printf 'PMLE_WAN_MATRIX|BEGIN|duration=%s|warmup=%s|profiles_sha256=%s\n' \
    "$duration" "$warmup" "$(shasum -a 256 "$profiles_file" | awk '{print $1}')"
  "$root/scripts/db_sql.sh" "$root/probes/mle/teavm-engine/environment-metadata.sql"
  "$root/scripts/db_sql.sh" "$root/probes/mle/teavm-engine/artifact-metadata.sql"
} | tee "$matrix_log"
"$root/scripts/db_sql.sh" - >/dev/null <<'SQL'
update doom_match_poll_capacity set long_poll_enabled=1 where capacity_id=1;
commit;
SQL
long_poll_enabled=1
printf '%s\n' \
  'PMLE_WAN_TRANSPORT|long_poll=ON|hold_ms=500|ords_pool_sessions=6|pool_reserve=2|max_held_polls=4|resmgr_running_sessions=2|worker_reserve=1|max_concurrent_poll_returns=1|background_refocus=ON' \
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
    DOOMDB_MULTIPLAYER_SOAK_SECONDS="$duration" \
    DOOMDB_MULTIPLAYER_SOAK_WARMUP_SECONDS="$warmup" \
    DOOMDB_MULTIPLAYER_STARTUP_TIMEOUT_MS=600000 \
    DOOMDB_WAN_GATE=1 \
    DOOMDB_WAN_RTT_MS="$rtt" \
    DOOMDB_WAN_JITTER_MS="$jitter" \
    DOOMDB_WAN_HOLD_MS=500 \
    DOOMDB_WAN_BACKGROUND_SCENARIO=1 \
      bash "$root/tests/verify-p13.5-multiplayer-soak.sh"
  } 2>&1 | tee -a "$profile_log" "$matrix_log"
  grep -q "PMLE_WAN_GATE|PASS|rtt_ms=$rtt|jitter_ms=$jitter|seconds=$duration" \
    "$profile_log" ||
    { printf 'WAN PASS marker missing for %s\n' "$name" >&2;exit 1; }
  printf 'PMLE_WAN_PROFILE|PASS|name=%s\n' "$name" | tee -a "$profile_log" "$matrix_log"
  cleanup_proxy
done < <(mapfile_compat)

[[ "$profile_count" -eq 3 ]] ||
  { printf 'WAN matrix expected 3 profiles, found %s\n' "$profile_count" >&2;exit 1; }
printf 'PMLE_WAN_MATRIX|PASS|profiles=%s|duration=%s|warmup=%s\n' \
  "$profile_count" "$duration" "$warmup" | tee -a "$matrix_log"
