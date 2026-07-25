#!/usr/bin/env bash
set -Eeuo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
project="$root/probes/mle/teavm-engine"
evidence="$root/artifacts/performance/pmle-ledger-every-tic"
ledger="${PMLE_DECPS_LEDGER_LOG:-$evidence/run-decps-reproducible-5ec18cbe-2026-07-25.log}"
origin="${PMLE_DECPS_LEDGER_ORIGIN:-$evidence/run-decps-reproducible-5ec18cbe-2026-07-25-alert-origin.txt}"
log="${PMLE_DECPS_POSTFLIGHT_LOG:-$evidence/run-decps-reproducible-5ec18cbe-2026-07-25-postflight.log}"
alert_state="$(mktemp "${TMPDIR:-/tmp}/doomdb-decps-postflight-alert.XXXXXX")"
authority_sha=e485b9418e5845b78e9e1593918d8bbb6f3c441c41a43cb8f3faf046e595148b
authority_bytes=1171896
table_sha=058cd0df9444131b356762a096fd422d5131ac3aea91163aee056e8ad4965b44

cleanup() {
  rm -f "$alert_state"
}
trap cleanup EXIT
# A signal must terminate the attestation. A cleanup-only signal trap would
# return to the interrupted command and could let a partially interrupted
# postflight continue toward a PASS marker.
trap 'exit 130' HUP INT TERM

[[ "${PMLE_DECPS_LEDGER_POSTFLIGHT:-NO}" == YES ]] || {
  printf '%s\n' \
    'set PMLE_DECPS_LEDGER_POSTFLIGHT=YES after the ledger wrapper exits cleanly' >&2
  exit 2
}
for input in "$ledger" "$origin"; do
  [[ -s "$input" ]] || {
    printf 'ledger postflight input missing: %s\n' "$input" >&2
    exit 2
  }
done
[[ ! -e "$log" ]] || {
  printf 'ledger postflight evidence exists: %s\n' "$log" >&2
  exit 1
}
if pgrep -f '[r]un-decps-ledger|[b]uild-ledger-differential' >/dev/null; then
  printf '%s\n' 'ledger postflight refuses an active wrapper or builder' >&2
  exit 1
fi
test "$(grep -Ec \
  '^PMLE_TEAVM_LEDGER_DIFFERENTIAL[|]PASS[|]tics=13272[|]deep_every=1[|]route_runs=1152[|]vector_runs=1246[|]cumulative_sha256=[0-9a-f]{64}$' \
  "$ledger")" -eq 1
grep -Fqx \
  'PMLE_LEDGER_PROVENANCE|CONFIRMED|executions=1|terminal_markers=1' \
  "$ledger"

offset="$(awk -F= '$1=="alert_offset"{print $2}' "$origin")"
alert_started_utc="$(awk -F= '$1=="alert_started_utc"{print $2}' "$origin")"
ledger_started_utc="$(awk -F= '$1=="ledger_started_utc"{print $2}' "$origin")"
wrapper_pid="$(awk -F= '$1=="wrapper_pid"{print $2}' "$origin")"
launcher_pid="$(awk -F= '$1=="launcher_pid"{print $2}' "$origin")"
[[ "$offset" =~ ^[0-9]+$ ]] || {
  printf '%s\n' 'ledger postflight alert offset is malformed' >&2
  exit 1
}
for timestamp in "$alert_started_utc" "$ledger_started_utc"; do
  [[ "$timestamp" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$ ]] || {
    printf '%s\n' 'ledger postflight timestamp is malformed' >&2
    exit 1
  }
done
[[ "$wrapper_pid" =~ ^[1-9][0-9]*$ &&
    "$launcher_pid" =~ ^[1-9][0-9]*$ ]] || {
  printf '%s\n' 'ledger postflight process provenance is malformed' >&2
  exit 1
}
if kill -0 "$wrapper_pid" 2>/dev/null || kill -0 "$launcher_pid" 2>/dev/null; then
  printf '%s\n' 'ledger postflight process provenance is still live' >&2
  exit 1
fi
grep -Fqx \
  "PMLE_LEDGER_PROVENANCE|BEGIN|executions=1|log_mode=exclusive-create|started_utc=$ledger_started_utc|launcher_pid=$launcher_pid" \
  "$ledger"
printf 'offset=%s\nstarted_utc=%s\n' "$offset" "$alert_started_utc" >"$alert_state"

if [[ "$alert_started_utc" > "$ledger_started_utc" ]]; then
  printf '%s\n' 'ledger postflight start timestamp is malformed' >&2
  exit 1
fi

ready=0
attempt=0
while (( attempt < 60 )); do
  attempt=$((attempt+1))
  slot_state="$("$root/scripts/db_sql.sh" - <<'SQL'
set heading off feedback off pagesize 0
select 'SLOTS='||count(*)||'|'||
       'READY='||sum(case when slot_status='READY' then 1 else 0 end)||'|'||
       'BOUND='||sum(case when assigned_match is not null then 1 else 0 end)
  from doom_mle_warm_slot;
SQL
  )"
  if grep -Fqx 'SLOTS=2|READY=2|BOUND=0' <<<"$slot_state"; then
    ready=1
    break
  fi
  sleep 3
done
[[ "$ready" == 1 ]] || {
  printf 'ledger postflight warm pool did not become clean after %s attempts: %s\n' \
    "$attempt" "$slot_state" >&2
  exit 1
}

{
  printf 'PMLE_DECPS_LEDGER_WRAPPER|TERMINATED_ENVIRONMENT_VERIFIED|wrapper_pid=%s|launcher_pid=%s\n' \
    "$wrapper_pid" "$launcher_pid"
  "$root/scripts/db_sql.sh" "$project/artifact-metadata.sql"
  printf 'PMLE_DECPS_LEDGER_POOL|PASS|slots=2|ready=2|bound=0\n'
  "$root/scripts/oracle-alert-window.sh" end "$alert_state" DECPS_LEDGER
} | tee "$log"

grep -Fqx \
  "PMLE_ARTIFACT|source_bytes=$authority_bytes|source_sha256=$authority_sha|table_bytes=180272|table_sha256=$table_sha" \
  "$log"
test "$(grep -Ec \
  '^PMLE_ALERT_WINDOW[|]PASS[|]label=DECPS_LEDGER[|]new_ora_incidents=0[|]bytes=[0-9]+$' \
  "$log")" -eq 1
printf 'PMLE_DECPS_LEDGER_POSTFLIGHT|PASS|authority_sha256=%s|slots=2|alert_offset=%s|alert_started_utc=%s|ledger_started_utc=%s\n' \
  "$authority_sha" "$offset" "$alert_started_utc" "$ledger_started_utc" |
  tee -a "$log"
