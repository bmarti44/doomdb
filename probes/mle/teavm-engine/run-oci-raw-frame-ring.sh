#!/usr/bin/env bash
set -Eeuo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
project="$root/probes/mle/teavm-engine"
evidence="$root/artifacts/performance/pmle-database-frames"
candidate="${RAW_FRAME_CANDIDATE:-$root/artifacts/performance/pmle-presentation-decps/presentation-candidate-118c37717b36.js}"
candidate_sha="${RAW_FRAME_CANDIDATE_SHA256:-118c37717b362d9e7669b5a3a1e73c87b3916479b6e53651f08e85be9ae8f2d3}"
evidence_tag="${RAW_FRAME_EVIDENCE_TAG:-baseline}"
require_30fps="${RAW_FRAME_REQUIRE_30FPS:-YES}"
render_warm_calls="${RAW_FRAME_RENDER_WARM_CALLS:-0}"
tables="$root/client/dist/play/canonical-runtime-v2-058cd0df9444.bin"
fixture="$root/tests/fixtures/mle-live-deathmatch-2026-07-23.json"
parser="$root/scripts/require-db-record.mjs"
mkdir -p "$evidence"

[[ "$evidence_tag" =~ ^[a-z0-9][a-z0-9-]{2,63}$ ]] || {
  printf 'invalid raw-frame evidence tag: %s\n' "$evidence_tag" >&2;exit 2; }
[[ "$require_30fps" == YES || "$require_30fps" == NO ]] || {
  printf 'RAW_FRAME_REQUIRE_30FPS must be YES or NO\n' >&2;exit 2; }
[[ "$render_warm_calls" == 0 || "$render_warm_calls" == 3000 ]] || {
  printf 'RAW_FRAME_RENDER_WARM_CALLS must be 0 or 3000\n' >&2;exit 2; }
pool_log="$evidence/oci-raw-frame-${evidence_tag}-pool-park-2026-07-26.log"
stream_log="$evidence/oci-raw-frame-${evidence_tag}-stream-stage-2026-07-26.log"
load_log="$evidence/oci-raw-frame-${evidence_tag}-presentation-load-2026-07-26.log"
bind_log="$evidence/oci-raw-frame-${evidence_tag}-bind-install-2026-07-26.log"
rank_log="$evidence/oci-raw-frame-${evidence_tag}-ring-300-2026-07-26.log"
restore_log="$evidence/oci-raw-frame-${evidence_tag}-production-restore-2026-07-26.log"

for name in ADB_CONNECTION_STRING ADB_USERNAME ADB_PASSWORD ADB_WALLET_DIR \
  SQL_CLIENT; do
  [[ -n "${!name:-}" ]] || {
    printf 'required OCI raw-frame authority is absent: %s\n' "$name" >&2
    exit 2
  }
done
[[ "$ADB_USERNAME" == DOOM ]]
for input in "$candidate" "$tables" "$fixture" \
    "$project/benchmark-oci-raw-frame-ring.sql"; do
  [[ -s "$input" && ! -L "$input" ]] || {
    printf 'raw-frame input is unavailable: %s\n' "$input" >&2; exit 2; }
done
[[ "$(shasum -a 256 "$candidate" | awk '{print $1}')" == "$candidate_sha" ]]
for output in "$pool_log" "$stream_log" "$load_log" "$bind_log" "$rank_log" \
    "$restore_log"; do
  [[ ! -e "$output" ]] || {
    printf 'raw-frame evidence already exists: %s\n' "$output" >&2; exit 1; }
done
node "$parser" --self-test
competing="$(ps ax -o command= | awk '
  /[v]erify-cloud-browser|[r]un-wan-matrix|[o]ci-command-stream|[r]un-oci-presentation|[r]un-oci-dvr-compression/ {print}
')"
[[ -z "$competing" ]] || {
  printf 'raw-frame rank refuses competing OCI work:\n%s\n' "$competing" >&2
  exit 1
}

pool_parked=0
diagnostic_loaded=0
stream_staged=0
restore() {
  local status=$? safe=1
  trap - EXIT HUP INT TERM
  if [[ "$diagnostic_loaded" == 1 ]]; then
    if ! "$root/scripts/adb-doom-sql.sh" - >"$restore_log" <<'SQL'
begin
  for object_ in (
    select object_type,object_name from user_objects
    where object_name like 'DOOM_TEAVM_BIND_%'
       or object_name in(
         'DOOM_TEAVM_PRESENTATION_BIND','DOOM_TEAVM_PRESENTATION_BIND_ENV',
         'DOOM_TEAVM_FRAME_SINK','DOOM_MLE_RAW_FRAME_RING')
    order by case object_type
      when 'PROCEDURE' then 1 when 'FUNCTION' then 2
      when 'MLE MODULE' then 3 when 'MLE ENVIRONMENT' then 4 else 5 end
  ) loop
    begin
      execute immediate 'drop '||
        case object_.object_type
          when 'MLE MODULE' then 'mle module '
          when 'MLE ENVIRONMENT' then 'mle env '
          else lower(object_.object_type)||' '
        end||object_.object_name||
        case when object_.object_type='TABLE' then ' purge' else '' end;
    exception when others then
      if sqlcode not in(-4043,-4080,-4103,-4104,-4105,-942) then raise;end if;
    end;
  end loop;
end;
/
SQL
    then safe=0; fi
    if ! "$project/load-mle-module.sh" --production --emit-sql |
        "$root/scripts/adb-doom-sql.sh" - >>"$restore_log"; then
      safe=0
    fi
    if ! "$root/scripts/adb-doom-sql.sh" - >>"$restore_log" <<'SQL'
alter package doom_mle_match_runtime compile body;
set serveroutput on size unlimited heading off feedback off pagesize 0
declare l_source blob;l_sha varchar2(64);l_status varchar2(7);
begin
  select source_blob into l_source from doom_teavm_sim_source;
  l_sha:=lower(rawtohex(dbms_crypto.hash(
    l_source,dbms_crypto.hash_sh256)));
  select status into l_status from user_objects
    where object_name='DOOM_MLE_MATCH_RUNTIME' and object_type='PACKAGE BODY';
  if l_sha<>'5ec18cbe4cff7192d384e81d1010e0133d357d44ff17fa65821e1489c4fd1ee3'
      or l_status<>'VALID' then
    raise_application_error(-20796,'raw-frame rollback verification failed');
  end if;
  dbms_output.put_line('PMLE_OCI_RAW_FRAME_ROLLBACK|PASS|module_sha256='||
    l_sha||'|runtime_status='||l_status);
end;
/
SQL
    then safe=0; fi
  fi
  if [[ "$stream_staged" == 1 ]]; then
    if ! "$root/scripts/adb-doom-sql.sh" - >>"$restore_log" <<'SQL'
begin execute immediate 'drop table doom_mle_perf_vector purge';
exception when others then if sqlcode<>-942 then raise;end if;end;
/
SQL
    then safe=0; fi
  fi
  if [[ "$pool_parked" == 1 && "$safe" == 1 ]]; then
    "$root/scripts/adb-doom-sql.sh" - >>"$restore_log" <<'SQL' || safe=0
begin doom_match_worker.start_warm_pool;end;
/
SQL
  fi
  if [[ "$safe" != 1 ]]; then
    status=1
    printf 'PMLE_OCI_RAW_FRAME_CAPACITY|HELD_CLOSED|reason=restore_failed\n' >&2
  fi
  exit "$status"
}
trap restore EXIT HUP INT TERM

"$root/scripts/adb-doom-sql.sh" - >"$pool_log" <<'SQL'
set serveroutput on size unlimited heading off feedback off pagesize 0
declare l_active number;l_assigned number;l_live number;
begin
  select count(*) into l_active from doom_match
    where match_state in('LOBBY','STARTING','ACTIVE','RECOVERING');
  select count(*) into l_assigned from doom_mle_warm_slot
    where assigned_match is not null;
  if l_active<>0 or l_assigned<>0 then
    raise_application_error(-20796,'raw-frame rank requires idle capacity');
  end if;
  for slot_ in (
    select job_name,incarnation_token,worker_sid,worker_serial,
      worker_spid,worker_job_run from doom_mle_warm_slot
    where slot_status in('WARMING','READY','CLAIMED','RUNNING')
  ) loop
    doom_worker_lifecycle.stop_job(
      slot_.job_name,true,'OCI database-generated raw-frame rank',
      slot_.incarnation_token,slot_.worker_sid,slot_.worker_serial,
      slot_.worker_spid,slot_.worker_job_run);
  end loop;
  select count(*) into l_live from doom_mle_warm_slot
    where slot_status in('WARMING','READY','CLAIMED','RUNNING');
  if l_live<>0 then raise_application_error(-20796,'pool did not park');end if;
  dbms_output.put_line(
    'PMLE_OCI_RAW_FRAME_POOL|PASS|active_matches=0|assigned_slots=0|live_slots=0');
end;
/
SQL
pool_parked=1
node "$parser" "$pool_log" 'PMLE_OCI_RAW_FRAME_POOL|' \
  'PMLE_OCI_RAW_FRAME_POOL|PASS|active_matches=0|assigned_slots=0|live_slots=0'

stream_staged=1
node "$project/emit-command-stream-sql.mjs" "$fixture" |
  "$root/scripts/adb-doom-sql.sh" - | tee "$stream_log"
diagnostic_loaded=1
"$project/load-mle-module.sh" --emit-sql "--javascript=$candidate" \
  "--table-pack=$tables" |
  "$root/scripts/adb-doom-sql.sh" - | tee "$load_log"
"$project/install-presentation-bind-wrapper.sh" --emit-sql \
  "--engine-sha256=$candidate_sha" |
  "$root/scripts/adb-doom-sql.sh" - | tee "$bind_log"
{
  printf '%s\n' \
    "begin dbms_session.set_identifier('OCI_RAW_FRAME_RING_300');end;" '/'
  if [[ "$render_warm_calls" == 3000 ]]; then
    cat "$project/warm-oci-database-renderer.sql"
  fi
  cat "$project/benchmark-oci-raw-frame-ring.sql"
} | "$root/scripts/adb-doom-sql.sh" - | tee "$rank_log"
if [[ "$render_warm_calls" == 3000 ]]; then
  grep -Eq '^PMLE_OCI_RENDERER_WARM\\|DIAGNOSTIC_NOT_GATE\\|calls=3000\\|window=100\\|.*\\|verdict=MEASURE_ONLY_EXACT_STREAM_FOLLOWS$' \
    "$rank_log"
fi
grep -Eq '^PMLE_OCI_RAW_FRAME_RING\|DIAGNOSTIC_NOT_GATE\|.*\|raw_30fps=(PASS|FAIL)$' \
  "$rank_log"
if [[ "$require_30fps" == YES ]]; then
  grep -Eq '^PMLE_OCI_RAW_FRAME_RING\|DIAGNOSTIC_NOT_GATE\|.*\|raw_30fps=PASS$' \
    "$rank_log"
fi
printf 'PASS PMLE-OCI-RAW-FRAME-RING candidate_sha256=%s\n' "$candidate_sha"
