#!/usr/bin/env bash
set -Eeuo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
project="$root/probes/mle/teavm-engine"
evidence="$root/artifacts/performance/pmle-free-live-frames"
fixture="$root/tests/fixtures/mle-live-deathmatch-2026-07-23.json"
artifact="$project/target/javascript/doom-mle-presentation-engine-headless.js"
iwad="$project/target/iwad-smoke/freedoom1.wad"
tables="$project/target/canonical-runtime-v2.bin"
tag="${PMLE_LIVE_COMMAND_TAG:-live-command-raster-v1-2026-07-27}"
mode="${PMLE_LIVE_COMMAND_MODE:-RANK}"
build_log="$evidence/oci-$tag-build.log"
node_log="$evidence/oci-$tag-node.log"
park_log="$evidence/oci-$tag-pool.log"
stream_log="$evidence/oci-$tag-stream.log"
load_log="$evidence/oci-$tag-load.log"
rank_log="$evidence/oci-$tag-rank.log"
verdict_log="$evidence/oci-$tag-verdict.log"
cleanup_log="$evidence/oci-$tag-cleanup.log"

[[ "${PMLE_LIVE_COMMAND_EXECUTE:-NO}" == YES ]] || exit 2
[[ "$mode" == RANK || "$mode" == BISECTION ]] || exit 2
for name in ADB_CONNECTION_STRING ADB_USERNAME ADB_PASSWORD ADB_WALLET_DIR \
  SQL_CLIENT; do
  [[ -n "${!name:-}" ]] || {
    printf 'live command raster cloud authority is absent: %s\n' "$name" >&2
    exit 2
  }
done
[[ "$ADB_USERNAME" == DOOM ]] || exit 2
for input in "$fixture" "$iwad" "$tables"; do
  [[ -s "$input" && ! -L "$input" ]] || {
    printf 'live command raster input is unavailable: %s\n' "$input" >&2
    exit 2
  }
done
for output in "$build_log" "$node_log" "$park_log" "$stream_log" \
  "$load_log" "$rank_log" "$verdict_log" "$cleanup_log"; do
  [[ ! -e "$output" ]] || {
    printf 'live command raster evidence exists: %s\n' "$output" >&2
    exit 1
  }
done
competing="$(ps ax -o command= | awk '
  /[r]un-wan-matrix|[r]un-oci-dvr|[r]un-oci-free-live|[r]un-oci-full-command/ {print}
')"
[[ -z "$competing" ]] || {
  printf 'live command raster refuses competing OCI work:\n%s\n' \
    "$competing" >&2
  exit 1
}

PMLE_PRESENTATION_CANDIDATE_BUILD=YES \
PMLE_PRESENTATION_CANDIDATE_REASON=full-command-census \
  "$project/build-presentation.sh" | tee "$build_log"
grep -Fq 'classification=UNPROMOTED_CANDIDATE candidate_reason=full-command-census' \
  "$build_log"
artifact_bytes="$(wc -c <"$artifact" | tr -d '[:space:]')"
artifact_sha="$(shasum -a 256 "$artifact" | awk '{print $1}')"
mocha_sha="$(shasum -a 256 \
  "$project/target/mochadoom-mle-presentation.jar" | awk '{print $1}')"
input_sha="$(shasum -a 256 \
  "$project/target/mochadoom-mle-engine-slice-1.0.0.jar" | awk '{print $1}')"

PMLE_PRESENTATION_LIVE_CAPTURE=YES \
  node "$project/run-presentation-node.mjs" \
    "$iwad" "$tables" "$artifact" | tee "$node_log"
grep -Fq \
  'PMLE_PRESENTATION_LIVE_CAPTURE|PASS|frames=192|full_frame_exact=192|' \
  "$node_log"

pool_parked=0
restoration_required=0
stream_staged=0
restore_environment() {
  local status=$? safe=1
  trap - EXIT HUP INT TERM
  if [[ "$restoration_required" == 1 ]]; then
    if "$root/scripts/adb-doom-sql.sh" - >"$cleanup_log" <<'SQL' &&
begin execute immediate 'drop function doom_teavm_live_row_chunk';
exception when others then if sqlcode<>-4043 then raise;end if;end;
/
begin execute immediate 'drop function doom_teavm_live_prepare_row';
exception when others then if sqlcode<>-4043 then raise;end if;end;
/
begin execute immediate 'drop function doom_teavm_live_capture_count';
exception when others then if sqlcode<>-4043 then raise;end if;end;
/
begin execute immediate 'drop function doom_teavm_live_asset_resets';
exception when others then if sqlcode<>-4043 then raise;end if;end;
/
begin execute immediate 'drop function doom_teavm_live_capture_chunk';
exception when others then if sqlcode<>-4043 then raise;end if;end;
/
begin execute immediate 'drop function doom_teavm_live_capture_length';
exception when others then if sqlcode<>-4043 then raise;end if;end;
/
begin execute immediate 'drop function doom_teavm_live_count_only';
exception when others then if sqlcode<>-4043 then raise;end if;end;
/
begin execute immediate 'drop function doom_teavm_live_raster_only';
exception when others then if sqlcode<>-4043 then raise;end if;end;
/
begin execute immediate 'drop function doom_teavm_live_capture_commands';
exception when others then if sqlcode<>-4043 then raise;end if;end;
/
SQL
      "$project/load-mle-module.sh" --production --emit-sql |
        "$root/scripts/adb-doom-sql.sh" - >>"$cleanup_log" &&
      "$root/scripts/adb-doom-sql.sh" - >>"$cleanup_log" <<'SQL'
alter package doom_mle_match_runtime compile body;
set heading off feedback off pagesize 0 linesize 32767
select 'PMLE_LIVE_COMMAND_ROLLBACK|PASS|status='||status
from user_objects
where object_name='DOOM_MLE_MATCH_RUNTIME'
  and object_type='PACKAGE BODY' and status='VALID';
SQL
    then
      :
    else
      safe=0
    fi
  else
    : >"$cleanup_log"
  fi
  if [[ "$stream_staged" == 1 ]]; then
    if ! "$root/scripts/adb-doom-sql.sh" - >>"$cleanup_log" <<'SQL'
begin
  execute immediate 'drop table doom_mle_perf_vector purge';
exception when others then
  if sqlcode<>-942 then raise;end if;
end;
/
SQL
    then safe=0;fi
  fi
  if [[ "$pool_parked" == 1 && "$safe" == 1 ]]; then
    "$root/scripts/adb-doom-sql.sh" - >>"$cleanup_log" <<'SQL' || safe=0
begin doom_match_worker.start_warm_pool;end;
/
SQL
  fi
  if [[ "$safe" == 1 ]]; then
    "$root/scripts/adb-doom-sql.sh" - >>"$cleanup_log" <<'SQL' || safe=0
set serveroutput on size unlimited heading off feedback off pagesize 0
declare l_source varchar2(64);l_diag number;l_stream number;
begin
  select lower(rawtohex(dbms_crypto.hash(
    source_blob,dbms_crypto.hash_sh256))) into l_source
    from doom_teavm_sim_source;
  select count(*) into l_diag from user_objects
    where object_name like 'DOOM_TEAVM_LIVE_%';
  select count(*) into l_stream from user_tables
    where table_name='DOOM_MLE_PERF_VECTOR';
  if l_source<>'5ec18cbe4cff7192d384e81d1010e0133d357d44ff17fa65821e1489c4fd1ee3'
      or l_diag<>0 or l_stream<>0 then
    raise_application_error(-20796,'live command raster postflight');
  end if;
  dbms_output.put_line(
    'PMLE_LIVE_COMMAND_POSTFLIGHT|PASS|production_sha256='||l_source||
    '|diagnostic_objects=0|stream_table=0');
end;
/
SQL
  fi
  [[ "$safe" == 1 ]] || {
    status=1
    printf '%s\n' \
      'PMLE_LIVE_COMMAND_CAPACITY|HELD_CLOSED|reason=rollback_unproven' >&2
  }
  exit "$status"
}
trap restore_environment EXIT HUP INT TERM

"$root/scripts/adb-doom-sql.sh" - >"$park_log" <<'SQL'
set serveroutput on size unlimited heading off feedback off pagesize 0
declare l_active number;l_assigned number;l_live number;
begin
  select count(*) into l_active from doom_match
    where match_state in('LOBBY','STARTING','ACTIVE','RECOVERING');
  select count(*) into l_assigned from doom_mle_warm_slot
    where assigned_match is not null;
  if l_active<>0 or l_assigned<>0 then
    raise_application_error(-20796,'live raster requires idle capacity');
  end if;
  for slot_ in (
    select job_name,incarnation_token,worker_sid,worker_serial,
      worker_spid,worker_job_run
    from doom_mle_warm_slot
    where slot_status in('WARMING','READY','CLAIMED','RUNNING')
  ) loop
    doom_worker_lifecycle.stop_job(
      slot_.job_name,true,'OCI live command raster diagnostic',
      slot_.incarnation_token,slot_.worker_sid,slot_.worker_serial,
      slot_.worker_spid,slot_.worker_job_run);
  end loop;
  select count(*) into l_live from doom_mle_warm_slot
    where slot_status in('WARMING','READY','CLAIMED','RUNNING');
  if l_live<>0 then raise_application_error(-20796,'pool did not park');end if;
  dbms_output.put_line(
    'PMLE_LIVE_COMMAND_POOL|PASS|active_matches=0|assigned_slots=0|live_slots=0');
end;
/
SQL
pool_parked=1
grep -Fq 'PMLE_LIVE_COMMAND_POOL|PASS|' "$park_log"

stream_staged=1
node "$project/emit-command-stream-sql.mjs" "$fixture" |
  "$root/scripts/adb-doom-sql.sh" - | tee "$stream_log"
grep -Fq \
  'PMLE_OCI_COMMAND_STREAM|PASS|stream=live-dm-2026-07-23|tics=5250|' \
  "$stream_log"

restoration_required=1
{
  "$project/load-mle-module.sh" --emit-sql \
    "--javascript=$artifact" "--table-pack=$tables"
  cat <<'SQL'
create function doom_teavm_live_capture_length(p_player number)
return number as mle module doom_teavm_simulation env doom_teavm_sim_env
signature 'renderCapturedPlayerFrameLength(number)';
/
create function doom_teavm_live_capture_chunk(p_offset number,p_length number)
return raw as mle module doom_teavm_simulation env doom_teavm_sim_env
signature 'capturedPlayerFrameChunk(number, number)';
/
create function doom_teavm_live_capture_count return number
as mle module doom_teavm_simulation env doom_teavm_sim_env
signature 'capturedFrameCommandCount()';
/
create function doom_teavm_live_asset_resets return number
as mle module doom_teavm_simulation env doom_teavm_sim_env
signature 'capturedFrameAssetResetCount()';
/
create function doom_teavm_live_prepare_row return number
as mle module doom_teavm_simulation env doom_teavm_sim_env
signature 'prepareCapturedPlayerFrameRowMajor()';
/
create function doom_teavm_live_row_chunk(p_offset number,p_length number)
return raw as mle module doom_teavm_simulation env doom_teavm_sim_env
signature 'capturedPlayerFrameRowMajorChunk(number, number)';
/
create function doom_teavm_live_capture_commands(p_player number)
return number as mle module doom_teavm_simulation env doom_teavm_sim_env
signature 'capturePlayerFrameCommands(number)';
/
create function doom_teavm_live_raster_only return number
as mle module doom_teavm_simulation env doom_teavm_sim_env
signature 'rasterCapturedPlayerFrameLength()';
/
create function doom_teavm_live_count_only(p_player number)
return number as mle module doom_teavm_simulation env doom_teavm_sim_env
signature 'renderPlayerFrameCountOnly(number)';
/
SQL
} | "$root/scripts/adb-doom-sql.sh" - | tee "$load_log"
grep -Fq \
  "PMLE_TEAVM_STAGING_GATE|PASS|source_bytes=$artifact_bytes|source_sha256=$artifact_sha|" \
  "$load_log"

if [[ "$mode" == BISECTION ]]; then
  "$root/scripts/adb-doom-sql.sh" \
    "$project/benchmark-oci-live-command-bisection.sql" | tee "$rank_log"
  [[ "$(grep -c '^PMLE_LIVE_BISECTION_EQUIVALENCE|PASS|' "$rank_log")" == 3 ]]
  [[ "$(grep -c '^PMLE_LIVE_COMMAND_BISECTION|DIAGNOSTIC_NOT_GATE|' \
      "$rank_log")" == 1 ]]
  node - "$rank_log" "$artifact_sha" "$artifact_bytes" "$mocha_sha" \
    "$input_sha" <<'NODE' | tee "$verdict_log"
import fs from 'node:fs';
const [logPath, artifactSha, artifactBytes, mochaSha, inputSha] =
  process.argv.slice(2);
const line = fs.readFileSync(logPath, 'utf8').split(/\r?\n/).find((value) =>
  value.startsWith('PMLE_LIVE_COMMAND_BISECTION|DIAGNOSTIC_NOT_GATE|'));
if (!line) throw new Error('bisection marker is absent');
const row = Object.fromEntries(line.split('|').slice(2)
  .map((field) => field.split('=', 2)));
for (const key of ['count_only_p95_ms', 'capture_p95_ms', 'raster_p95_ms']) {
  row[key] = Number(row[key]);
  if (!Number.isFinite(row[key]) || row[key] <= 0) {
    throw new Error(`invalid ${key}`);
  }
}
const asset = Math.max(0, row.capture_p95_ms - row.count_only_p95_ms);
const stages = [
  ['GEOMETRY_HUD', row.count_only_p95_ms],
  ['ASSET_COMMAND_PREP', asset],
  ['COMPACT_RASTER', row.raster_p95_ms],
].sort((a, b) => b[1] - a[1]);
console.log(`PMLE_LIVE_BISECTION_VERDICT|NEXT_STAGE=${stages[0][0]}`
  + `|count_only_p95_ms=${row.count_only_p95_ms.toFixed(3)}`
  + `|asset_command_exclusive_p95_ms=${asset.toFixed(3)}`
  + `|raster_p95_ms=${row.raster_p95_ms.toFixed(3)}`
  + `|artifact_bytes=${artifactBytes}|artifact_sha256=${artifactSha}`
  + `|mocha_sha256=${mochaSha}|input_sha256=${inputSha}`
  + '|full_frame_exact_oci=3|classification=DIAGNOSTIC_NOT_GATE');
NODE
else
  "$root/scripts/adb-doom-sql.sh" \
    "$project/benchmark-oci-live-command-raster.sql" | tee "$rank_log"
  [[ "$(grep -c '^PMLE_LIVE_COMMAND_EQUIVALENCE|PASS|' "$rank_log")" == 6 ]]
  [[ "$(grep -c '^PMLE_LIVE_COMMAND_RANK|DIAGNOSTIC_NOT_GATE|' "$rank_log")" == 2 ]]

  node - "$rank_log" "$artifact_sha" "$artifact_bytes" "$mocha_sha" \
    "$input_sha" <<'NODE' | tee "$verdict_log"
import fs from 'node:fs';
const [logPath, artifactSha, artifactBytes, mochaSha, inputSha] =
  process.argv.slice(2);
const rows = fs.readFileSync(logPath, 'utf8').split(/\r?\n/)
  .filter((line) => line.startsWith(
    'PMLE_LIVE_COMMAND_RANK|DIAGNOSTIC_NOT_GATE|'));
if (rows.length !== 2) throw new Error(`expected two rank rows, got ${rows.length}`);
const parsed = rows.map((line) => Object.fromEntries(line.split('|').slice(2)
  .map((field) => field.split('=', 2))));
for (const row of parsed) {
  for (const key of ['step_p95_ms', 'render_p95_ms', 'egress_p95_ms',
    'pipeline_p95_ms', 'throughput_fps']) {
    row[key] = Number(row[key]);
    if (!Number.isFinite(row[key]) || row[key] <= 0) {
      throw new Error(`invalid ${key}`);
    }
  }
  row.internalP95 = row.step_p95_ms + row.render_p95_ms;
}
const complete = parsed.every((row) =>
  row.pipeline_p95_ms <= 33.333 && row.throughput_fps >= 35);
const internal = parsed.every((row) => row.internalP95 <= 25);
let verdict = 'BISECT_LIVE_COMMAND_PIPELINE';
if (complete) verdict = 'PROMOTE_ORDS_BROWSER_INTEGRATION';
else if (internal) verdict = 'OPTIMIZE_ONE_CROSSING_TRANSPORT';
const detail = parsed.map((row) =>
  `${row.window.toLowerCase()}_pipeline_p95_ms=${row.pipeline_p95_ms.toFixed(3)}`
  + `|${row.window.toLowerCase()}_fps=${row.throughput_fps.toFixed(3)}`
  + `|${row.window.toLowerCase()}_internal_p95_ms=${row.internalP95.toFixed(3)}`)
  .join('|');
console.log(`PMLE_LIVE_COMMAND_VERDICT|${verdict}|${detail}`
  + `|artifact_bytes=${artifactBytes}|artifact_sha256=${artifactSha}`
  + `|mocha_sha256=${mochaSha}|input_sha256=${inputSha}`
  + '|full_frame_exact_node=192|full_frame_exact_oci=6'
  + '|client=PIXEL_COPY_ONLY|classification=DIAGNOSTIC_NOT_GATE');
NODE
fi
