#!/usr/bin/env bash
set -Eeuo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
project="$root/probes/mle/teavm-engine"
evidence="$root/artifacts/performance/pmle-presentation-decps"
candidate="$evidence/presentation-candidate-118c37717b36.js"
candidate_sha=118c37717b362d9e7669b5a3a1e73c87b3916479b6e53651f08e85be9ae8f2d3
candidate_bytes=1167481
tables="$root/client/dist/play/canonical-runtime-v2-058cd0df9444.bin"
fixture="$root/tests/fixtures/mle-live-deathmatch-2026-07-23.json"
iwad="$project/target/iwad-smoke/freedoom1.wad"
oracle100="$evidence/oci-presentation-oracle-100-118c3771-2026-07-26.log"
oracle300="$evidence/oci-presentation-oracle-300-118c3771-2026-07-26.log"
record_parser="$root/scripts/require-db-record.mjs"
stream_log="$evidence/oci-adb-presentation-stream-stage-v5-2026-07-26.log"
load_log="$evidence/oci-adb-presentation-load-118c3771-v5-2026-07-26.log"
bind_log="$evidence/oci-adb-presentation-bind-install-118c3771-v5-2026-07-26.log"
rank100="$evidence/oci-adb-presentation-locator-100-118c3771-v5-2026-07-26.log"
rank300="$evidence/oci-adb-presentation-locator-300-118c3771-v5-2026-07-26.log"
verdict100="$evidence/oci-adb-presentation-verdict-100-118c3771-v5-2026-07-26.log"
verdict300="$evidence/oci-adb-presentation-verdict-300-118c3771-v5-2026-07-26.log"
restore_log="$evidence/oci-adb-authority-restore-after-118c3771-v5-2026-07-26.log"
park_log="$evidence/oci-adb-presentation-pool-park-118c3771-v5-2026-07-26.log"

for name in ADB_CONNECTION_STRING ADB_USERNAME ADB_PASSWORD ADB_WALLET_DIR \
  SQL_CLIENT; do
  [[ -n "${!name:-}" ]] || {
    printf 'required OCI presentation authority is absent: %s\n' "$name" >&2
    exit 2
  }
done
[[ "$ADB_USERNAME" == DOOM ]] || {
  printf '%s\n' 'OCI presentation diagnostic requires DOOM schema' >&2
  exit 2
}
for input in "$candidate" "$tables" "$fixture" "$iwad" "$oracle100" \
  "$oracle300"; do
  [[ -s "$input" && ! -L "$input" ]] || {
    printf 'OCI presentation input is unavailable: %s\n' "$input" >&2
    exit 2
  }
done
[[ "$(wc -c <"$candidate" | tr -d '[:space:]')" == "$candidate_bytes" &&
    "$(shasum -a 256 "$candidate" | awk '{print $1}')" == "$candidate_sha" ]] ||
  { printf '%s\n' 'OCI presentation candidate pin mismatch' >&2; exit 1; }
for output in "$stream_log" "$load_log" "$bind_log" "$rank100" "$rank300" \
  "$verdict100" "$verdict300" "$restore_log" "$park_log"; do
  [[ ! -e "$output" ]] || {
    printf 'OCI presentation evidence already exists: %s\n' "$output" >&2
    exit 1
  }
done

node "$project/extract-presentation-frame-chain.mjs" --self-test
node "$project/evaluate-oci-presentation-decps.mjs" --self-test
node "$record_parser" --self-test

competing="$(ps ax -o command= | awk '
  /[v]erify-cloud-browser|[r]un-wan-matrix|[o]ci-command-stream-digest/ {print}
')"
[[ -z "$competing" ]] || {
  printf 'OCI presentation rank refuses a competing OCI cell:\n%s\n' \
    "$competing" >&2
  exit 1
}

restoration_required=0
pool_parked=0
stream_staged=0
restore_production() {
  local status=$?
  local environment_safe=1
  trap - EXIT HUP INT TERM
  if [[ "$restoration_required" == 1 ]]; then
    if "$project/load-mle-module.sh" --production --emit-sql |
        "$root/scripts/adb-doom-sql.sh" - >"$restore_log" &&
      node "$record_parser" "$restore_log" 'PMLE_TEAVM_STAGING_GATE|' \
        'PMLE_TEAVM_STAGING_GATE|PASS|source_bytes=1081335|source_sha256=5ec18cbe4cff7192d384e81d1010e0133d357d44ff17fa65821e1489c4fd1ee3|table_bytes=180272|table_sha256=058cd0df9444131b356762a096fd422d5131ac3aea91163aee056e8ad4965b44' &&
      "$root/scripts/adb-doom-sql.sh" - >>"$restore_log" <<'SQL'
alter package doom_mle_match_runtime compile body;
set heading off feedback off pagesize 0 linesize 32767 trimspool on
select 'PMLE_OCI_PRESENTATION_ROLLBACK_COMPILE|PASS|status='||status
from user_objects
where object_name='DOOM_MLE_MATCH_RUNTIME'
  and object_type='PACKAGE BODY'
  and status='VALID';
SQL
      node "$record_parser" "$restore_log" \
        'PMLE_OCI_PRESENTATION_ROLLBACK_COMPILE|' \
        'PMLE_OCI_PRESENTATION_ROLLBACK_COMPILE|PASS|status=VALID' &&
      "$root/scripts/adb-doom-sql.sh" \
        "$project/artifact-metadata.sql" >>"$restore_log" &&
      node "$record_parser" "$restore_log" 'PMLE_ARTIFACT|' \
        'PMLE_ARTIFACT|source_bytes=1081335|source_sha256=5ec18cbe4cff7192d384e81d1010e0133d357d44ff17fa65821e1489c4fd1ee3|table_bytes=180272|table_sha256=058cd0df9444131b356762a096fd422d5131ac3aea91163aee056e8ad4965b44' &&
      "$root/scripts/adb-doom-sql.sh" - >>"$restore_log" <<'SQL'
set heading off feedback off pagesize 0 linesize 32767 trimspool on
select 'PMLE_OCI_PRESENTATION_ROLLBACK_CONTRACT|PASS|sha256=5ec18cbe4cff7192d384e81d1010e0133d357d44ff17fa65821e1489c4fd1ee3'
from dual
where (select count(*) from user_source
       where name='DOOM_MLE_MATCH_RUNTIME' and type='PACKAGE BODY'
         and text like '%5ec18cbe4cff7192d384e81d1010e0133d357d44ff17fa65821e1489c4fd1ee3%')=1
  and (select count(*) from user_objects
       where object_name='DOOM_MLE_MATCH_RUNTIME'
         and object_type='PACKAGE BODY' and status='VALID')=1;
SQL
      node "$record_parser" "$restore_log" \
        'PMLE_OCI_PRESENTATION_ROLLBACK_CONTRACT|' \
        'PMLE_OCI_PRESENTATION_ROLLBACK_CONTRACT|PASS|sha256=5ec18cbe4cff7192d384e81d1010e0133d357d44ff17fa65821e1489c4fd1ee3'; then
      :
    else
      environment_safe=0
    fi
  fi
  if [[ "$stream_staged" == 1 ]]; then
    if ! "$root/scripts/adb-doom-sql.sh" - >>"$restore_log" <<'SQL'
begin
  execute immediate 'drop table doom_mle_perf_vector purge';
exception when others then
  if sqlcode<>-942 then raise;end if;
end;
/
SQL
    then
      environment_safe=0
    fi
  fi
  if [[ "$pool_parked" == 1 && "$environment_safe" == 1 ]]; then
    if ! "$root/scripts/adb-doom-sql.sh" - >>"$restore_log" <<'SQL'
begin doom_match_worker.start_warm_pool;end;
/
SQL
    then
      environment_safe=0
    fi
  fi
  if [[ "$environment_safe" != 1 ]]; then
    status=1
    printf '%s\n' \
      'PMLE_OCI_PRESENTATION_DECPS_CAPACITY|HELD_CLOSED|reason=diagnostic_or_restore_failed' >&2
  fi
  exit "$status"
}
trap restore_production EXIT HUP INT TERM

"$root/scripts/adb-doom-sql.sh" - >"$park_log" <<'SQL'
set serveroutput on size unlimited heading off feedback off pagesize 0
declare
  l_active number;l_assigned number;l_live number;
begin
  select count(*) into l_active from doom_match
    where match_state in('LOBBY','STARTING','ACTIVE','RECOVERING');
  select count(*) into l_assigned from doom_mle_warm_slot
    where assigned_match is not null;
  if l_active<>0 or l_assigned<>0 then
    raise_application_error(-20796,'OCI presentation rank requires idle capacity');
  end if;
  for slot_ in (
    select job_name,incarnation_token,worker_sid,worker_serial,
      worker_spid,worker_job_run
    from doom_mle_warm_slot
    where slot_status in('WARMING','READY','CLAIMED','RUNNING')
  ) loop
    doom_worker_lifecycle.stop_job(
      slot_.job_name,true,'OCI de-CPS presentation diagnostic',
      slot_.incarnation_token,slot_.worker_sid,slot_.worker_serial,
      slot_.worker_spid,slot_.worker_job_run);
  end loop;
  select count(*) into l_live from doom_mle_warm_slot
    where slot_status in('WARMING','READY','CLAIMED','RUNNING');
  if l_live<>0 then
    raise_application_error(-20796,'OCI retained pool did not park');
  end if;
  dbms_output.put_line(
    'PMLE_OCI_PRESENTATION_POOL|PASS|active_matches=0|assigned_slots=0|live_slots=0');
end;
/
SQL
pool_parked=1
node "$record_parser" "$park_log" 'PMLE_OCI_PRESENTATION_POOL|' \
  'PMLE_OCI_PRESENTATION_POOL|PASS|active_matches=0|assigned_slots=0|live_slots=0'
restoration_required=1

stream_staged=1
node "$project/emit-command-stream-sql.mjs" "$fixture" |
  "$root/scripts/adb-doom-sql.sh" - | tee "$stream_log"
node "$record_parser" "$stream_log" 'PMLE_OCI_COMMAND_STREAM|' \
  'PMLE_OCI_COMMAND_STREAM|PASS|stream=live-dm-2026-07-23|tics=5250|bytes=173250|sha256=fa7637570c30d3a33cbf8456e98268890e9f5bd82f5ba39fd7f69b139ddc4085'

"$project/load-mle-module.sh" --emit-sql "--javascript=$candidate" \
  "--table-pack=$tables" |
  "$root/scripts/adb-doom-sql.sh" - | tee "$load_log"
node "$record_parser" "$load_log" 'PMLE_TEAVM_STAGING_GATE|' \
  "PMLE_TEAVM_STAGING_GATE|PASS|source_bytes=$candidate_bytes|source_sha256=$candidate_sha|table_bytes=180272|table_sha256=058cd0df9444131b356762a096fd422d5131ac3aea91163aee056e8ad4965b44"

"$project/install-presentation-bind-wrapper.sh" --emit-sql \
  "--engine-sha256=$candidate_sha" |
  "$root/scripts/adb-doom-sql.sh" - | tee "$bind_log"
node "$record_parser" "$bind_log" 'PMLE_PRESENTATION_BIND_INSTALL|' \
  "PMLE_PRESENTATION_BIND_INSTALL|PASS|transports=direct_uint8array_blob_insert,persistent_returning_oracle_blob|direct_supported=YES|direct_mode=explicit_db_type_blob|frame_bytes=64000|imports=1|source_bytes=5408|source_sha256=e2410f67c81c007aca7ab881fb8aa922026418b630299390fdc5cf97e0219576|engine_sha256=$candidate_sha"

run_rank() {
  local identifier=$1 output=$2
  {
    printf '%s\n' \
      "begin dbms_session.set_identifier('$identifier');end;" \
      '/'
    cat "$project/benchmark-oci-presentation-command-stream.sql"
  } | "$root/scripts/adb-doom-sql.sh" - | tee "$output"
}

run_rank OCI_PRESENTATION_LOCATOR_100 "$rank100"
node "$project/evaluate-oci-presentation-decps.mjs" \
  "$oracle100" "$rank100" 100 | tee "$verdict100"

if grep -Fq '|exact_30fps=PASS|' "$verdict100" &&
    grep -Fq '|locator_hygiene=PASS|' "$verdict100"; then
  run_rank OCI_PRESENTATION_LOCATOR_300 "$rank300"
  node "$project/evaluate-oci-presentation-decps.mjs" \
    "$oracle300" "$rank300" 300 | tee "$verdict300"
else
  printf 'PMLE_OCI_PRESENTATION_DECPS_VERDICT|DIAGNOSTIC_NOT_GATE|' \
    >"$verdict300"
  printf 'samples=300|exact_30fps=NOT_RUN_100_FRAME_MISS|' \
    >>"$verdict300"
  printf 'locator_hygiene=NOT_RUN_100_FRAME_MISS|' \
    >>"$verdict300"
  printf 'artifact_sha256=%s\n' "$candidate_sha" >>"$verdict300"
fi

printf 'PASS PMLE-OCI-PRESENTATION-DECPS-RANK candidate_sha256=%s ' \
  "$candidate_sha"
printf 'candidate_bytes=%s verdict100=%s verdict300=%s\n' \
  "$candidate_bytes" "$verdict100" "$verdict300"
