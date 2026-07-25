#!/usr/bin/env bash
set -Eeuo pipefail

spike="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
root="$(cd "$spike/../../../.." && pwd)"
project="$root/probes/mle/teavm-engine"
artifact="${DOOMDB_WASM2JS_RANK_ARTIFACT:-$spike/target/wasm/doom-wasm2js-authority.serializer-workaround.o0.bundle.mjs}"
workaround_log="${artifact%.o0.bundle.mjs}.log"
parity_log="${artifact%.o0.bundle.mjs}.100tic.log"
baseline="$root/artifacts/performance/pmle-decps-rank/interpreter-2848ef7a8dc4-5250.log"
evidence="$root/artifacts/performance/pmle-wasm2js"
tag="${PMLE_WASM2JS_RANK_TAG:-serializer-workaround-2026-07-24}"
install_log="$evidence/mle-install-$tag.log"
rank_log="$evidence/mle-rank-$tag.log"
decision_log="$evidence/mle-decision-$tag.log"
metadata_log="$evidence/mle-metadata-$tag.log"
extractor="$spike/extract-node-parity.mjs"
mle_extractor="$spike/extract-mle-parity.mjs"
comparator="$spike/compare-mle-rank.mjs"
alert_state="$(mktemp "${TMPDIR:-/tmp}/doomdb-wasm2js-rank-alert.XXXXXX")"
pool_parked=0
alert_started=0

finish() {
  local status=$?
  local safe_to_start_pool=1
  trap - EXIT
  if ! "$root/scripts/db_sql.sh" \
      "$spike/cleanup-mle-rank.sql" >/dev/null 2>&1; then
    status=1
    safe_to_start_pool=0
  fi
  if ! remaining="$("$root/scripts/db_sql.sh" - <<'SQL' 2>/dev/null |
set heading off feedback off pagesize 0
select count(*) from user_objects
where object_name like 'DOOM_WASM2JS_RANK%';
SQL
    tr -d '[:space:]'
  )"; then
    status=1
    safe_to_start_pool=0
  elif [[ "$remaining" != 0 ]]; then
    status=1
    safe_to_start_pool=0
  fi
  if [[ "$alert_started" == 1 ]]; then
    if ! "$root/scripts/oracle-alert-window.sh" end \
        "$alert_state" WASM2JS_MLE_RANK; then
      status=1
      safe_to_start_pool=0
    fi
  fi
  if [[ "$pool_parked" == 1 && "$safe_to_start_pool" == 1 ]]; then
    "$root/scripts/db_sql.sh" - >/dev/null <<'SQL' || status=1
begin doom_match_worker.start_warm_pool;end;
/
SQL
  elif [[ "$pool_parked" == 1 ]]; then
    printf '%s\n' \
      'PMLE_WASM2JS_MLE_CAPACITY|HELD_CLOSED|reason=cleanup_or_alert_unproven' >&2
  fi
  exit "$status"
}

[[ "${PMLE_WASM2JS_RANK_EXECUTE:-NO}" == YES ]] || {
  printf '%s\n' 'set PMLE_WASM2JS_RANK_EXECUTE=YES to run Oracle MLE rank' >&2
  exit 2
}
[[ "$tag" =~ ^[A-Za-z0-9._-]+$ ]] || {
  printf 'invalid wasm2js rank tag: %s\n' "$tag" >&2
  exit 2
}
for input in "$artifact" "$workaround_log" "$parity_log" "$baseline" \
    "$extractor" "$mle_extractor" "$comparator"; do
  [[ -s "$input" ]] || {
    printf 'wasm2js MLE rank input missing: %s\n' "$input" >&2
    exit 1
  }
done
for output in "$install_log" "$rank_log" "$decision_log" "$metadata_log"; do
  [[ ! -e "$output" ]] || {
    printf 'wasm2js MLE rank evidence exists: %s\n' "$output" >&2
    exit 1
  }
done
node "$extractor" --self-test
node "$mle_extractor" --self-test
node "$comparator" --self-test
expected_parity_sha="$(node "$extractor" "$parity_log" 100)"
expected_parity_bytes="$(node "$extractor" \
  "$parity_log" 100 canonical_bytes)"

competing_gate="$(ps ax -o command= | awk '
  /[r]un-ledger-differential|[r]un-decps-ledger|[b]uild-ledger-differential|[r]un-worker-soak|[r]un-decps-rank-mle|[r]un-presentation-decps-rank/ {print}
')"
[[ -z "$competing_gate" ]] || {
  printf 'wasm2js MLE rank refuses a competing evidence gate:\n%s\n' \
    "$competing_gate" >&2
  exit 1
}
busy_host="$(ps ax -o command= | awk '
  /[d]ocker (build|compose .* build)|[b]uild-simulation[.]sh|[m]vn .*package|[j]avac|[v]erify-local-e2e/ {print}
')"
[[ -z "$busy_host" ]] || {
  printf 'wasm2js MLE rank requires a quiet host:\n%s\n' "$busy_host" >&2
  exit 1
}
active="$("$root/scripts/db_sql.sh" - <<'SQL' |
set heading off feedback off pagesize 0
select count(*) from doom_match
where match_state in('LOBBY','ACTIVE')
  and expires_at>(localtimestamp at time zone 'UTC');
SQL
  tr -d '[:space:]'
)"
[[ "$active" == 0 ]] || {
  printf 'wasm2js MLE rank refuses %s active match(es)\n' "$active" >&2
  exit 1
}

trap finish EXIT
"$root/scripts/oracle-alert-window.sh" begin \
  "$alert_state" WASM2JS_MLE_RANK
alert_started=1
mkdir -p "$evidence"

before_metadata="$("$root/scripts/db_sql.sh" "$project/artifact-metadata.sql" |
  grep '^PMLE_ARTIFACT|')"
[[ -n "$before_metadata" ]]
printf '%s\n' "$before_metadata" >"$metadata_log"

pool_parked=1
"$root/scripts/db_sql.sh" - >>"$metadata_log" <<'SQL'
declare
  l_live number;
begin
  for slot_ in (
    select job_name,incarnation_token,worker_sid,worker_serial,
      worker_spid,worker_job_run
    from doom_mle_warm_slot
    where slot_status in('WARMING','READY','CLAIMED','RUNNING')
  ) loop
    doom_worker_lifecycle.stop_job(
      slot_.job_name,true,'wasm2js direct MLE rank',
      slot_.incarnation_token,slot_.worker_sid,slot_.worker_serial,
      slot_.worker_spid,slot_.worker_job_run);
  end loop;
  select count(*) into l_live from doom_mle_warm_slot
    where slot_status in('WARMING','READY','CLAIMED','RUNNING');
  if l_live<>0 then
    raise_application_error(-20796,'warm pool did not park for wasm2js rank');
  end if;
end;
/
SQL

"$spike/install-mle-rank.sh" "--artifact=$artifact" |
  tee "$install_log"
{
  printf 'PMLE_HOST_QUIESCENCE|PASS|docker_builds=0|compiles=0|verifiers=0\n'
  printf 'PMLE_WASM2JS_MLE_ARTIFACT|sha256=%s|bytes=%s|classification=UNPROMOTED_CANDIDATE\n' \
    "$(shasum -a 256 "$artifact" | awk '{print $1}')" \
    "$(wc -c <"$artifact" | tr -d '[:space:]')"
  "$root/scripts/db_sql.sh" "$project/environment-metadata.sql"
  timeout --signal=TERM 3600 "$root/scripts/db_sql.sh" \
    "$spike/benchmark-mle-rank.sql"
} | tee "$rank_log"

actual_parity_sha="$(node "$mle_extractor" "$rank_log" 100)"
actual_parity_bytes="$(node "$mle_extractor" \
  "$rank_log" 100 canonical_bytes)"
[[ "$actual_parity_bytes" == "$expected_parity_bytes" &&
    "$actual_parity_sha" == "$expected_parity_sha" ]] || {
  printf 'wasm2js Node/MLE parity mismatch: expected=%s/%s actual=%s\n' \
    "$expected_parity_bytes" "$expected_parity_sha" \
    "$actual_parity_bytes/$actual_parity_sha" >&2
  exit 1
}
node "$comparator" "$baseline" "$rank_log" | tee "$decision_log"

"$root/scripts/db_sql.sh" "$spike/cleanup-mle-rank.sql" >/dev/null
remaining="$("$root/scripts/db_sql.sh" - <<'SQL' |
set heading off feedback off pagesize 0
select count(*) from user_objects
where object_name like 'DOOM_WASM2JS_RANK%';
SQL
  tr -d '[:space:]'
)"
[[ "$remaining" == 0 ]] || {
  printf 'wasm2js rank cleanup left %s object(s)\n' "$remaining" >&2
  exit 1
}
printf '%s\n' 'PMLE_WASM2JS_MLE_CLEANUP|PASS|objects=0' >>"$metadata_log"
after_metadata="$("$root/scripts/db_sql.sh" "$project/artifact-metadata.sql" |
  grep '^PMLE_ARTIFACT|')"
printf '%s\n' "$after_metadata" >>"$metadata_log"
[[ "$before_metadata" == "$after_metadata" ]] || {
  printf '%s\n' 'wasm2js rank changed the production authority metadata' >&2
  exit 1
}
"$root/scripts/oracle-alert-window.sh" end \
  "$alert_state" WASM2JS_MLE_RANK | tee -a "$metadata_log"
alert_started=0
"$root/scripts/db_sql.sh" - >>"$metadata_log" <<'SQL'
declare
  l_started number;
begin
  doom_match_worker.start_warm_pool;
  select count(*) into l_started from doom_mle_warm_slot
   where slot_status in('WARMING','READY');
  if l_started=0 then
    raise_application_error(-20796,'warm pool did not restart after wasm2js rank');
  end if;
  dbms_output.put_line(
    'PMLE_WASM2JS_MLE_CAPACITY|RESTORED|slots='||l_started);
end;
/
SQL
pool_parked=0
trap - EXIT
printf 'PASS PMLE-WASM2JS-MLE-RANK artifact_sha256=%s parity_sha256=%s decision=%s\n' \
  "$(shasum -a 256 "$artifact" | awk '{print $1}')" \
  "$actual_parity_sha" "${decision_log#"$root"/}"
