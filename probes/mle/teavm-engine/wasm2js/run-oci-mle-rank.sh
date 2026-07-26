#!/usr/bin/env bash
set -Eeuo pipefail

spike="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
root="$(cd "$spike/../../../.." && pwd)"
project="$root/probes/mle/teavm-engine"
artifact="${DOOMDB_WASM2JS_RANK_ARTIFACT:-$spike/target/wasm/doom-wasm2js-authority.serializer-workaround.o0.bundle.mjs}"
workaround_stem="${artifact%.o0.bundle.mjs}"
parity_log="$workaround_stem.100tic.log"
fixture="$root/tests/fixtures/mle-live-deathmatch-2026-07-23.json"
evidence="$root/artifacts/performance/pmle-database-frames"
tag="${PMLE_WASM2JS_OCI_RANK_TAG:-linear-memory-authority-2026-07-26}"
pool_log="$evidence/oci-wasm2js-$tag-pool.log"
stream_log="$evidence/oci-wasm2js-$tag-stream.log"
install_log="$evidence/oci-wasm2js-$tag-install.log"
rank_log="$evidence/oci-wasm2js-$tag-rank.log"
cleanup_log="$evidence/oci-wasm2js-$tag-cleanup.log"
extractor="$spike/extract-node-parity.mjs"
mle_extractor="$spike/extract-mle-parity.mjs"

[[ "${PMLE_WASM2JS_OCI_RANK_EXECUTE:-NO}" == YES ]] || {
  printf '%s\n' \
    'set PMLE_WASM2JS_OCI_RANK_EXECUTE=YES to run the OCI MLE rank' >&2
  exit 2
}
[[ "$tag" =~ ^[a-z0-9][a-z0-9-]{2,63}$ ]] || {
  printf 'invalid OCI wasm2js rank tag: %s\n' "$tag" >&2
  exit 2
}
for name in ADB_CONNECTION_STRING ADB_USERNAME ADB_PASSWORD ADB_WALLET_DIR \
    SQL_CLIENT; do
  [[ -n "${!name:-}" ]] || {
    printf 'required OCI rank authority is absent: %s\n' "$name" >&2
    exit 2
  }
done
[[ "$ADB_USERNAME" == DOOM ]]
for input in "$artifact" "$parity_log" "$fixture" "$extractor" \
    "$mle_extractor" "$spike/benchmark-mle-rank.sql"; do
  [[ -s "$input" && ! -L "$input" ]] || {
    printf 'OCI wasm2js rank input is unavailable: %s\n' "$input" >&2
    exit 2
  }
done
mkdir -p "$evidence"
for output in "$pool_log" "$stream_log" "$install_log" "$rank_log" \
    "$cleanup_log"; do
  [[ ! -e "$output" ]] || {
    printf 'OCI wasm2js rank evidence already exists: %s\n' "$output" >&2
    exit 1
  }
done
node "$extractor" --self-test
node "$mle_extractor" --self-test
expected_sha="$(node "$extractor" "$parity_log" 100)"
expected_bytes="$(node "$extractor" "$parity_log" 100 canonical_bytes)"

competing="$(ps ax -o command= | awk '
  /[v]erify-cloud-browser|[r]un-wan-matrix|[r]un-oci-presentation|[r]un-oci-dvr-compression|[r]un-oci-raw-frame/ {print}
')"
[[ -z "$competing" ]] || {
  printf 'OCI wasm2js rank refuses competing OCI work:\n%s\n' "$competing" >&2
  exit 1
}

pool_parked=0
stream_staged=0
diagnostic_loaded=0
finish() {
  local status=$? safe=1
  trap - EXIT HUP INT TERM
  if [[ "$diagnostic_loaded" == 1 ]]; then
    if ! "$root/scripts/adb-doom-sql.sh" \
        "$spike/cleanup-mle-rank.sql" >"$cleanup_log"; then
      safe=0
    fi
  else
    : >"$cleanup_log"
  fi
  if [[ "$stream_staged" == 1 ]]; then
    if ! "$root/scripts/adb-doom-sql.sh" - >>"$cleanup_log" <<'SQL'
begin execute immediate 'drop table doom_mle_perf_vector purge';
exception when others then if sqlcode<>-942 then raise;end if;end;
/
SQL
    then safe=0; fi
  fi
  if [[ "$pool_parked" == 1 && "$safe" == 1 ]]; then
    if ! "$root/scripts/adb-doom-sql.sh" - >>"$cleanup_log" <<'SQL'
begin doom_match_worker.start_warm_pool;end;
/
SQL
    then safe=0; fi
  fi
  if [[ "$safe" != 1 ]]; then
    printf '%s\n' \
      'PMLE_WASM2JS_OCI_CAPACITY|HELD_CLOSED|reason=cleanup_unproven' >&2
    status=1
  fi
  exit "$status"
}
trap finish EXIT HUP INT TERM

"$root/scripts/adb-doom-sql.sh" - >"$pool_log" <<'SQL'
set serveroutput on size unlimited heading off feedback off pagesize 0
declare l_active number;l_assigned number;l_live number;
begin
  select count(*) into l_active from doom_match
    where match_state in('LOBBY','STARTING','ACTIVE','RECOVERING');
  select count(*) into l_assigned from doom_mle_warm_slot
    where assigned_match is not null;
  if l_active<>0 or l_assigned<>0 then
    raise_application_error(-20796,'OCI wasm2js rank requires idle capacity');
  end if;
  for slot_ in (
    select job_name,incarnation_token,worker_sid,worker_serial,
      worker_spid,worker_job_run from doom_mle_warm_slot
    where slot_status in('WARMING','READY','CLAIMED','RUNNING')
  ) loop
    doom_worker_lifecycle.stop_job(
      slot_.job_name,true,'OCI wasm2js direct rank',
      slot_.incarnation_token,slot_.worker_sid,slot_.worker_serial,
      slot_.worker_spid,slot_.worker_job_run);
  end loop;
  select count(*) into l_live from doom_mle_warm_slot
    where slot_status in('WARMING','READY','CLAIMED','RUNNING');
  if l_live<>0 then raise_application_error(-20796,'pool did not park');end if;
  dbms_output.put_line(
    'PMLE_WASM2JS_OCI_POOL|PASS|active_matches=0|assigned_slots=0|live_slots=0');
end;
/
SQL
pool_parked=1
grep -Fqx \
  'PMLE_WASM2JS_OCI_POOL|PASS|active_matches=0|assigned_slots=0|live_slots=0' \
  "$pool_log"

stream_staged=1
node "$project/emit-command-stream-sql.mjs" "$fixture" |
  "$root/scripts/adb-doom-sql.sh" - | tee "$stream_log"

diagnostic_loaded=1
"$spike/install-mle-rank.sh" "--artifact=$artifact" --emit-sql |
  "$root/scripts/adb-doom-sql.sh" - | tee "$install_log"

{
  printf '%s\n' \
    "begin dbms_session.set_identifier('OCI_WASM2JS_RANK_5250');end;" /
  cat "$spike/benchmark-mle-rank.sql"
} | "$root/scripts/adb-doom-sql.sh" - | tee "$rank_log"

actual_sha="$(node "$mle_extractor" "$rank_log" 100)"
actual_bytes="$(node "$mle_extractor" "$rank_log" 100 canonical_bytes)"
[[ "$actual_sha" == "$expected_sha" && "$actual_bytes" == "$expected_bytes" ]]
grep -Eq \
  '^PMLE_WASM2JS_MLE_RANK\|PASS\|stream=live-dm-2026-07-23\|tics=5250\|' \
  "$rank_log"

printf 'PASS PMLE-WASM2JS-OCI-RANK artifact_sha256=%s parity_sha256=%s rank_log=%s\n' \
  "$(shasum -a 256 "$artifact" | awk '{print $1}')" \
  "$actual_sha" "${rank_log#"$root"/}"
