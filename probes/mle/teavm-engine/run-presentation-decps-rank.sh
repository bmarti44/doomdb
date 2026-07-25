#!/usr/bin/env bash
set -Eeuo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
project="$root/probes/mle/teavm-engine"
evidence="$root/artifacts/performance/pmle-presentation-decps"
artifact="$project/target/javascript/doom-mle-presentation-engine-headless.js"
iwad="$project/target/iwad-smoke/freedoom1.wad"
tables="$root/client/dist/play/canonical-runtime-v2-058cd0df9444.bin"
pinned_presentation="$root/client/dist/play/doom-mle-presentation-e55d5f1138fa.js"
pinned_presentation_sha="e55d5f1138fa94d4fc7efd0acf27cbc89cb8a894e3d6828d84837a364b4426dc"
decps_patch="$project/0006-teavm-authority-no-blocking-wait.patch"
expected_decps_authority_sha="5ec18cbe4cff7192d384e81d1010e0133d357d44ff17fa65821e1489c4fd1ee3"
expected_decps_authority_bytes=1081335
extractor="$project/extract-presentation-frame-chain.mjs"
build_sha_extractor="$project/extract-build-sha.mjs"
comparator="$project/compare-presentation-frame-rank.mjs"
transport_comparator="$project/compare-presentation-transport-rank.mjs"
bind_capability_extractor="$project/extract-presentation-bind-capability.mjs"
bind_installer="$project/install-presentation-bind-wrapper.sh"
bind_source="$project/presentation-bind-wrapper.mjs"
bind_benchmark="$project/benchmark-presentation-bind-mle.sql"
alert_state="$(mktemp "${TMPDIR:-/tmp}/doomdb-presentation-decps-alert.XXXXXX")"
build_log="$(mktemp "${TMPDIR:-/tmp}/doomdb-presentation-decps-build.XXXXXX")"
baseline_build_log="$(mktemp "${TMPDIR:-/tmp}/doomdb-presentation-baseline-build.XXXXXX")"
pool_parked=0
candidate_loaded=0
alert_started=0

restore_environment() {
  local status=$?
  local safe_to_start_pool=1
  trap - EXIT
  if [[ "$candidate_loaded" == 1 ]]; then
    if ! "$project/load-mle-module.sh" --production >/dev/null; then
      status=1
      safe_to_start_pool=0
    fi
  fi
  if [[ "$alert_started" == 1 ]]; then
    if ! "$root/scripts/oracle-alert-window.sh" end \
        "$alert_state" PRESENTATION_DECPS_RANK; then
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
      'PMLE_PRESENTATION_DECPS_CAPACITY|HELD_CLOSED|reason=production_restore_or_alert_unproven' >&2
  fi
  rm -f "$alert_state" "$build_log" "$baseline_build_log"
  exit "$status"
}
trap restore_environment EXIT

node "$extractor" --self-test
node "$build_sha_extractor" --self-test
node "$comparator" --self-test
node "$transport_comparator" --self-test
node "$bind_capability_extractor" --self-test
test -s "$bind_source"
bind_source_bytes="$(wc -c <"$bind_source" | tr -d '[:space:]')"
bind_source_sha="$(shasum -a 256 "$bind_source" | awk '{print $1}')"
bind_install_pattern='^PASS PMLE-PRESENTATION-BIND-INSTALL source_bytes=[0-9]+ source_sha256=[0-9a-f]{64} engine_sha256=[0-9a-f]{64}$'
printf 'PASS PMLE-PRESENTATION-BIND-INSTALL source_bytes=1234 source_sha256=%064d engine_sha256=%064d\n' 0 0 |
  grep -Eq "$bind_install_pattern"
if printf 'PASS PMLE-PRESENTATION-BIND-INSTALL source_bytes=1234 source_sha256=abc\n' |
    grep -Eq "$bind_install_pattern"; then
  printf '%s\n' 'presentation bind marker extractor accepted malformed SHA' >&2
  exit 1
fi
competing_gate="$(ps ax -o command= | awk '
  /[r]un-ledger-differential|[r]un-decps-ledger|[b]uild-ledger-differential|[r]un-worker-soak|[r]un-live-command-matrix-mle|[r]un-decps-rank-mle/ {print}
')"
[[ -z "$competing_gate" ]] || {
  printf 'presentation de-CPS build refuses a competing evidence gate:\n%s\n' \
    "$competing_gate" >&2
  exit 1
}
mkdir -p "$evidence"
authority_isolation_log="$evidence/authority-isolation-${expected_decps_authority_sha:0:12}.log"
[[ ! -e "$authority_isolation_log" ]] || {
  printf 'presentation authority-isolation evidence exists: %s\n' \
    "$authority_isolation_log" >&2
  exit 1
}
PMLE_AUTHORITY_CANDIDATE_BUILD=YES \
PMLE_AUTHORITY_CANDIDATE_REASON=presentation-authority-isolation \
DOOMDB_TEAVM_AUTHORITY_EXTRA_PATCH="$decps_patch" \
  "$project/build-simulation.sh" | tee "$authority_isolation_log"
authority_after_presentation_source="$project/target/javascript/doom-mle-simulation-engine-headless.js"
[[ "$(wc -c <"$authority_after_presentation_source" | tr -d '[:space:]')" \
      == "$expected_decps_authority_bytes" &&
    "$(shasum -a 256 "$authority_after_presentation_source" | awk '{print $1}')" \
      == "$expected_decps_authority_sha" ]] || {
  printf '%s\n' \
    'presentation-only adapter changes altered the de-CPS authority artifact' >&2
  exit 1
}
printf 'PMLE_PRESENTATION_AUTHORITY_ISOLATION|PASS|bytes=%s|sha256=%s\n' \
  "$expected_decps_authority_bytes" "$expected_decps_authority_sha" |
  tee -a "$authority_isolation_log"
authority_input_sha="$(
  node "$build_sha_extractor" "$authority_isolation_log" \
    'PASS PMLE-TEAVM-SIMULATION-BUILD' input_bytecode_sha256
)"
PMLE_PRESENTATION_CANDIDATE_BUILD=YES \
PMLE_PRESENTATION_CANDIDATE_REASON=decps-frame-chunk \
DOOMDB_TEAVM_PRESENTATION_EXTRA_PATCH="$decps_patch" \
  "$project/build-presentation.sh" | tee "$build_log"
candidate_input_sha="$(
  node "$build_sha_extractor" "$build_log" \
    'PASS PMLE-TEAVM-PRESENTATION-BUILD' input_bytecode_sha256
)"
[[ "$candidate_input_sha" == "$authority_input_sha" ]] || {
  printf 'presentation/authority input bytecode mismatch: %s/%s\n' \
    "$candidate_input_sha" "$authority_input_sha" >&2
  exit 1
}

test -s "$artifact"
test -s "$iwad"
[[ "$(shasum -a 256 "$pinned_presentation" | awk '{print $1}')" == "$pinned_presentation_sha" ]] || {
  printf 'pinned presentation artifact SHA mismatch\n' >&2
  exit 1
}
candidate_sha="$(shasum -a 256 "$artifact" | awk '{print $1}')"
candidate_bytes="$(wc -c <"$artifact" | tr -d '[:space:]')"
candidate="$evidence/presentation-candidate-${candidate_sha:0:12}.js"
candidate_build_evidence="$evidence/build-${candidate_sha:0:12}.log"
pinned_node_log="$evidence/node-pinned-${pinned_presentation_sha:0:12}-${candidate_sha:0:12}.log"
candidate_node_log="$evidence/node-decps-${candidate_sha:0:12}.log"
candidate_load_log="$evidence/load-decps-${candidate_sha:0:12}.log"
candidate_mle_log="$evidence/mle-decps-${candidate_sha:0:12}.log"
candidate_bind_install_log="$evidence/bind-install-${candidate_sha:0:12}.log"
candidate_bind_mle_log="$evidence/mle-bind-${candidate_sha:0:12}.log"
transport_ab_log="$evidence/transport-ab-${candidate_sha:0:12}.log"
temporary_lob_grant_log="$evidence/temporary-lob-grant-${candidate_sha:0:12}.log"
[[ ! -e "$candidate" && ! -e "$candidate_build_evidence" &&
    ! -e "$pinned_node_log" &&
    ! -e "$candidate_node_log" &&
    ! -e "$candidate_load_log" && ! -e "$candidate_mle_log" &&
    ! -e "$candidate_bind_install_log" && ! -e "$candidate_bind_mle_log" &&
    ! -e "$transport_ab_log" && ! -e "$temporary_lob_grant_log" ]] || {
  printf 'presentation de-CPS evidence already exists for %s\n' "$candidate_sha" >&2
  exit 1
}
cp "$artifact" "$candidate"
[[ "$(shasum -a 256 "$candidate" | awk '{print $1}')" == "$candidate_sha" ]] ||
  { printf 'copied presentation candidate SHA mismatch\n' >&2; exit 1; }
cp "$build_log" "$candidate_build_evidence"

PMLE_PRESENTATION_CANDIDATE_BUILD=YES \
PMLE_PRESENTATION_CANDIDATE_REASON=frame-chunk-baseline \
  "$project/build-presentation.sh" | tee "$baseline_build_log"
baseline_input_sha="$(
  node "$build_sha_extractor" "$baseline_build_log" \
    'PASS PMLE-TEAVM-PRESENTATION-BUILD' input_bytecode_sha256
)"
[[ "$baseline_input_sha" == "$authority_input_sha" ]] || {
  printf 'presentation baseline/authority input bytecode mismatch: %s/%s\n' \
    "$baseline_input_sha" "$authority_input_sha" >&2
  exit 1
}
test -s "$artifact"
expected_baseline_mocha_sha="$(node -e \
  "const fs=require('fs');const v=JSON.parse(fs.readFileSync('$root/versions.lock'));process.stdout.write(v.teaVM.presentation.mochaBytecodeSha256)")"
actual_baseline_mocha_sha="$(shasum -a 256 \
  "$project/target/mochadoom-mle-presentation.jar" | awk '{print $1}')"
[[ "$actual_baseline_mocha_sha" == "$expected_baseline_mocha_sha" ]] || {
  printf 'presentation source-only baseline Mocha drift: %s expected %s\n' \
    "$actual_baseline_mocha_sha" "$expected_baseline_mocha_sha" >&2
  exit 1
}
baseline_sha="$(shasum -a 256 "$artifact" | awk '{print $1}')"
baseline_bytes="$(wc -c <"$artifact" | tr -d '[:space:]')"
baseline="$evidence/presentation-baseline-${baseline_sha:0:12}.js"
baseline_build_evidence="$evidence/build-${baseline_sha:0:12}.log"
baseline_node_log="$evidence/node-baseline-${baseline_sha:0:12}.log"
baseline_load_log="$evidence/load-baseline-${baseline_sha:0:12}.log"
baseline_mle_log="$evidence/mle-baseline-${baseline_sha:0:12}.log"
baseline_bind_install_log="$evidence/bind-install-baseline-${baseline_sha:0:12}.log"
ab_log="$evidence/ab-${baseline_sha:0:12}-${candidate_sha:0:12}.log"
[[ ! -e "$baseline" && ! -e "$baseline_build_evidence" &&
    ! -e "$baseline_node_log" &&
    ! -e "$baseline_load_log" && ! -e "$baseline_mle_log" &&
    ! -e "$baseline_bind_install_log" &&
    ! -e "$ab_log" ]] || {
  printf 'presentation baseline evidence already exists for %s\n' "$baseline_sha" >&2
  exit 1
}
cp "$artifact" "$baseline"
[[ "$(shasum -a 256 "$baseline" | awk '{print $1}')" == "$baseline_sha" ]] ||
  { printf 'copied presentation baseline SHA mismatch\n' >&2; exit 1; }
cp "$baseline_build_log" "$baseline_build_evidence"

node "$project/rank-presentation-frame-node.mjs" \
  "$iwad" "$tables" "$pinned_presentation" | tee "$pinned_node_log"
pinned_node_chain="$(
  node "$extractor" "$pinned_node_log" PMLE_PRESENTATION_FRAME_ORACLE
)"
node "$project/rank-presentation-frame-node.mjs" \
  "$iwad" "$tables" "$baseline" | tee "$baseline_node_log"
baseline_node_chain="$(
  node "$extractor" "$baseline_node_log" PMLE_PRESENTATION_FRAME_ORACLE
)"
node "$project/rank-presentation-frame-node.mjs" \
  "$iwad" "$tables" "$candidate" | tee "$candidate_node_log"
candidate_node_chain="$(
  node "$extractor" "$candidate_node_log" PMLE_PRESENTATION_FRAME_ORACLE
)"
[[ "$baseline_node_chain" == "$candidate_node_chain" ]] || {
  printf 'presentation baseline/de-CPS Node frame-chain mismatch: baseline=%s candidate=%s\n' \
    "$baseline_node_chain" "$candidate_node_chain" >&2
  exit 1
}
[[ "$pinned_node_chain" == "$candidate_node_chain" ]] || {
  printf 'pinned/baseline/de-CPS Node frame-chain mismatch: pinned=%s baseline=%s candidate=%s\n' \
    "$pinned_node_chain" "$baseline_node_chain" "$candidate_node_chain" >&2
  exit 1
}

busy_host="$(ps ax -o command= | awk '
  /[d]ocker (build|compose .* build)|[b]uild-simulation[.]sh|[m]vn .*package|[j]avac|[v]erify-local-e2e/ {print}
')"
[[ -z "$busy_host" ]] || {
  printf 'presentation de-CPS rank requires a quiet host:\n%s\n' \
    "$busy_host" >&2
  exit 1
}
active_output="$("$root/scripts/db_sql.sh" - <<'SQL'
set heading off feedback off pagesize 0
select 'ACTIVE_MATCHES='||count(*) from doom_match
where match_state in('LOBBY','ACTIVE')
  and expires_at>(localtimestamp at time zone 'UTC');
SQL
)"
active="$(awk -F= '/^ACTIVE_MATCHES=/{print $2}' <<<"$active_output")"
[[ "$active" == 0 ]] ||
  { printf 'presentation rank refuses %s active match(es)\n' "$active" >&2; exit 1; }

docker compose -f "$root/compose.yaml" exec -T db \
  sqlplus -s / as sysdba <<'SQL' | tee "$temporary_lob_grant_log"
whenever sqlerror exit sql.sqlcode rollback
set heading off feedback off pagesize 0
alter session set container=FREEPDB1;
grant select on sys.v_$temporary_lobs to DOOM;
select 'PMLE_PRESENTATION_TEMP_LOB_GRANT|PASS|grantee=DOOM|view=V_$TEMPORARY_LOBS'
from dual
where (select count(*) from dba_tab_privs
       where grantee='DOOM' and owner='SYS'
         and table_name='V_$TEMPORARY_LOBS' and privilege='SELECT')=1;
exit success commit
SQL
grep -Fqx \
  "PMLE_PRESENTATION_TEMP_LOB_GRANT|PASS|grantee=DOOM|view=V_\$TEMPORARY_LOBS" \
  "$temporary_lob_grant_log"

"$root/scripts/oracle-alert-window.sh" begin \
  "$alert_state" PRESENTATION_DECPS_RANK
alert_started=1
pool_parked=1
"$root/scripts/db_sql.sh" - >/dev/null <<'SQL'
declare
  l_live number;
begin
  for slot_ in (
    select job_name,incarnation_token,worker_sid,worker_serial,
      worker_spid,worker_job_run
    from doom_mle_warm_slot
    where slot_status in('WARMING','READY','CLAIMED','RUNNING')
      and assigned_match is null
  ) loop
    doom_worker_lifecycle.stop_job(
      slot_.job_name,true,'presentation de-CPS direct-MLE rank',
      slot_.incarnation_token,slot_.worker_sid,slot_.worker_serial,
      slot_.worker_spid,slot_.worker_job_run);
  end loop;
  select count(*) into l_live from doom_mle_warm_slot
    where slot_status in('WARMING','READY','CLAIMED','RUNNING');
  if l_live<>0 then
    raise_application_error(-20796,'retained warm pool did not park');
  end if;
end;
/
SQL

candidate_loaded=1
"$project/load-mle-module.sh" \
  "--javascript=$baseline" "--table-pack=$tables" | tee "$baseline_load_log"
grep -q "^PMLE_TEAVM_STAGING_GATE|PASS|source_bytes=$baseline_bytes|source_sha256=$baseline_sha|table_bytes=180272|table_sha256=058cd0df9444131b356762a096fd422d5131ac3aea91163aee056e8ad4965b44$" \
  "$baseline_load_log"
"$bind_installer" "--engine-sha256=$baseline_sha" |
  tee "$baseline_bind_install_log"
grep -Fqx "PASS PMLE-PRESENTATION-BIND-INSTALL source_bytes=$bind_source_bytes source_sha256=$bind_source_sha engine_sha256=$baseline_sha" \
  "$baseline_bind_install_log"
{
  printf 'PMLE_HOST_QUIESCENCE|PASS|docker_builds=0|compiles=0|verifiers=0\n'
  printf 'PMLE_PRESENTATION_BASELINE_ARTIFACT|sha256=%s|bytes=%s|classification=UNPROMOTED_CANDIDATE\n' \
    "$baseline_sha" "$baseline_bytes"
  "$root/scripts/db_sql.sh" "$project/environment-metadata.sql"
  timeout --signal=TERM 1800 "$root/scripts/db_sql.sh" \
    "$project/benchmark-presentation-frame-mle.sql"
} | tee "$baseline_mle_log"

"$project/load-mle-module.sh" \
  "--javascript=$candidate" "--table-pack=$tables" | tee "$candidate_load_log"
grep -q "^PMLE_TEAVM_STAGING_GATE|PASS|source_bytes=$candidate_bytes|source_sha256=$candidate_sha|table_bytes=180272|table_sha256=058cd0df9444131b356762a096fd422d5131ac3aea91163aee056e8ad4965b44$" \
  "$candidate_load_log"
"$bind_installer" "--engine-sha256=$candidate_sha" |
  tee "$candidate_bind_install_log"
grep -Eq "$bind_install_pattern" \
  "$candidate_bind_install_log"
grep -Fqx "PASS PMLE-PRESENTATION-BIND-INSTALL source_bytes=$bind_source_bytes source_sha256=$bind_source_sha engine_sha256=$candidate_sha" \
  "$candidate_bind_install_log"
bind_transport="$(node "$bind_capability_extractor" \
  "$candidate_bind_install_log")"
bind_direct_mode="$(node "$bind_capability_extractor" --mode \
  "$candidate_bind_install_log")"
{
  printf 'PMLE_HOST_QUIESCENCE|PASS|docker_builds=0|compiles=0|verifiers=0\n'
  printf 'PMLE_PRESENTATION_DECPS_ARTIFACT|sha256=%s|bytes=%s|classification=UNPROMOTED_CANDIDATE\n' \
    "$candidate_sha" "$candidate_bytes"
  "$root/scripts/db_sql.sh" "$project/environment-metadata.sql"
  timeout --signal=TERM 1800 "$root/scripts/db_sql.sh" \
    "$project/benchmark-presentation-frame-mle.sql"
} | tee "$candidate_mle_log"

baseline_mle_chain="$(
  node "$extractor" "$baseline_mle_log" PMLE_PRESENTATION_FRAME_RANK
)"
candidate_mle_chain="$(
  node "$extractor" "$candidate_mle_log" PMLE_PRESENTATION_FRAME_RANK
)"
[[ "$baseline_mle_chain" == "$baseline_node_chain" ]] || {
  printf 'presentation baseline Node/MLE frame-chain mismatch: node=%s mle=%s\n' \
    "$baseline_node_chain" "$baseline_mle_chain" >&2
  exit 1
}
[[ "$candidate_mle_chain" == "$candidate_node_chain" ]] || {
  printf 'presentation de-CPS Node/MLE frame-chain mismatch: node=%s mle=%s\n' \
    "$candidate_node_chain" "$candidate_mle_chain" >&2
  exit 1
}
[[ "$baseline_mle_chain" == "$candidate_mle_chain" ]] || {
  printf 'presentation baseline/de-CPS MLE frame-chain mismatch\n' >&2
  exit 1
}
grep -q '^PMLE_PRESENTATION_FRAME_RANK|DIAGNOSTIC_NOT_GATE|' \
  "$baseline_mle_log"
grep -q '^PMLE_PRESENTATION_FRAME_RANK|DIAGNOSTIC_NOT_GATE|' \
  "$candidate_mle_log"
node "$comparator" "$baseline_mle_log" "$candidate_mle_log" | tee "$ab_log"

if [[ "$bind_transport" == direct_uint8array_blob_insert ]]; then
  bind_transport=direct_uint8array_blob_insert
  bind_client_identifier=
  bind_gate_identifier=PMLE_FRAME_BIND_DIRECT_GATE_300
elif [[ "$bind_transport" == persistent_returning_oracle_blob ]]; then
  bind_transport=persistent_returning_oracle_blob
  bind_client_identifier=PMLE_FRAME_BIND_LOCATOR_DIAGNOSTIC
  bind_gate_identifier=PMLE_FRAME_BIND_LOCATOR_GATE_300
else
  printf '%s\n' 'presentation bind capability marker missing or ambiguous' >&2
  exit 1
fi
{
  printf 'PMLE_HOST_QUIESCENCE|PASS|docker_builds=0|compiles=0|verifiers=0\n'
  printf 'PMLE_PRESENTATION_BIND_ARTIFACT|sha256=%s|bytes=%s|classification=UNPROMOTED_CANDIDATE\n' \
    "$candidate_sha" "$candidate_bytes"
  "$root/scripts/db_sql.sh" "$project/environment-metadata.sql"
  if [[ -z "$bind_client_identifier" ]]; then
    timeout --signal=TERM 1800 "$root/scripts/db_sql.sh" "$bind_benchmark"
  else
    {
      printf '%s\n' \
        'whenever oserror exit failure rollback' \
        'whenever sqlerror exit sql.sqlcode rollback' \
        "begin dbms_session.set_identifier('$bind_client_identifier');end;" \
        '/'
      cat "$bind_benchmark"
    } | timeout --signal=TERM 1800 "$root/scripts/db_sql.sh" -
  fi
} | tee "$candidate_bind_mle_log"
candidate_bind_chain="$(
  node "$extractor" "$candidate_bind_mle_log" PMLE_PRESENTATION_BIND_RANK
)"
[[ "$candidate_bind_chain" == "$candidate_node_chain" ]] || {
  printf 'presentation session-bind Node/MLE frame-chain mismatch: node=%s mle=%s\n' \
    "$candidate_node_chain" "$candidate_bind_chain" >&2
  exit 1
}
node "$transport_comparator" "$candidate_mle_log" "$candidate_bind_mle_log" |
  tee "$transport_ab_log"

gate_status=NOT_RUN_RANK_FAILED
if grep -q '|candidate_exact_30fps=PASS|' "$ab_log"; then
  gate_pinned_node_log="$evidence/node-gate-pinned-${pinned_presentation_sha:0:12}-${candidate_sha:0:12}.log"
  gate_candidate_node_log="$evidence/node-gate-candidate-${candidate_sha:0:12}.log"
  gate_mle_log="$evidence/mle-gate-${candidate_sha:0:12}.log"
  gate_verdict_log="$evidence/gate-${candidate_sha:0:12}.log"
  for gate_file in "$gate_pinned_node_log" "$gate_candidate_node_log" \
      "$gate_mle_log" "$gate_verdict_log"; do
    [[ ! -e "$gate_file" ]] || {
      printf 'presentation 300-frame gate evidence exists: %s\n' "$gate_file" >&2
      exit 1
    }
  done
  node "$project/rank-presentation-frame-node.mjs" \
    "$iwad" "$tables" "$pinned_presentation" 300 30 |
    tee "$gate_pinned_node_log"
  gate_pinned_chain="$(
    node "$extractor" "$gate_pinned_node_log" PMLE_PRESENTATION_FRAME_ORACLE
  )"
  node "$project/rank-presentation-frame-node.mjs" \
    "$iwad" "$tables" "$candidate" 300 30 |
    tee "$gate_candidate_node_log"
  gate_candidate_chain="$(
    node "$extractor" "$gate_candidate_node_log" PMLE_PRESENTATION_FRAME_ORACLE
  )"
  [[ "$gate_pinned_chain" == "$gate_candidate_chain" ]] || {
    printf 'presentation 300-frame pinned/candidate Node chain mismatch\n' >&2
    exit 1
  }
  {
    printf 'PMLE_HOST_QUIESCENCE|PASS|docker_builds=0|compiles=0|verifiers=0\n'
    printf 'PMLE_PRESENTATION_DECPS_ARTIFACT|sha256=%s|bytes=%s|classification=UNPROMOTED_CANDIDATE\n' \
      "$candidate_sha" "$candidate_bytes"
    "$root/scripts/db_sql.sh" "$project/environment-metadata.sql"
    {
      printf '%s\n' \
        'whenever oserror exit failure rollback' \
        'whenever sqlerror exit sql.sqlcode rollback' \
        "begin dbms_session.set_identifier('PMLE_FRAME_GATE_300');end;" \
        '/'
      cat "$project/benchmark-presentation-frame-mle.sql"
    } | timeout --signal=TERM 3600 "$root/scripts/db_sql.sh" -
  } | tee "$gate_mle_log"
  gate_mle_chain="$(
    node "$extractor" "$gate_mle_log" PMLE_PRESENTATION_FRAME_RANK
  )"
  [[ "$gate_mle_chain" == "$gate_candidate_chain" ]] || {
    printf 'presentation 300-frame Node/MLE chain mismatch\n' >&2
    exit 1
  }
  node "$comparator" --gate "$gate_mle_log" | tee "$gate_verdict_log"
  gate_status=RAW_PASS
fi
if grep -q '|bind_exact_30fps=PASS|' "$transport_ab_log"; then
  bind_gate_pinned_node_log="$evidence/node-bind-gate-pinned-${pinned_presentation_sha:0:12}-${candidate_sha:0:12}.log"
  bind_gate_candidate_node_log="$evidence/node-bind-gate-candidate-${candidate_sha:0:12}.log"
  bind_gate_mle_log="$evidence/mle-bind-gate-${candidate_sha:0:12}.log"
  bind_gate_verdict_log="$evidence/bind-gate-${candidate_sha:0:12}.log"
  for gate_file in "$bind_gate_pinned_node_log" \
      "$bind_gate_candidate_node_log" "$bind_gate_mle_log" \
      "$bind_gate_verdict_log"; do
    [[ ! -e "$gate_file" ]] || {
      printf 'presentation bind 300-frame gate evidence exists: %s\n' \
        "$gate_file" >&2
      exit 1
    }
  done
  node "$project/rank-presentation-frame-node.mjs" \
    "$iwad" "$tables" "$pinned_presentation" 300 30 |
    tee "$bind_gate_pinned_node_log"
  bind_gate_pinned_chain="$(
    node "$extractor" "$bind_gate_pinned_node_log" \
      PMLE_PRESENTATION_FRAME_ORACLE
  )"
  node "$project/rank-presentation-frame-node.mjs" \
    "$iwad" "$tables" "$candidate" 300 30 |
    tee "$bind_gate_candidate_node_log"
  bind_gate_candidate_chain="$(
    node "$extractor" "$bind_gate_candidate_node_log" \
      PMLE_PRESENTATION_FRAME_ORACLE
  )"
  [[ "$bind_gate_pinned_chain" == "$bind_gate_candidate_chain" ]] || {
    printf 'presentation bind 300-frame pinned/candidate Node chain mismatch\n' >&2
    exit 1
  }
  {
    printf 'PMLE_HOST_QUIESCENCE|PASS|docker_builds=0|compiles=0|verifiers=0\n'
    printf 'PMLE_PRESENTATION_BIND_ARTIFACT|sha256=%s|bytes=%s|classification=UNPROMOTED_CANDIDATE\n' \
      "$candidate_sha" "$candidate_bytes"
    "$root/scripts/db_sql.sh" "$project/environment-metadata.sql"
    {
      printf '%s\n' \
        'whenever oserror exit failure rollback' \
        'whenever sqlerror exit sql.sqlcode rollback' \
        "begin dbms_session.set_identifier('$bind_gate_identifier');end;" \
        '/'
      cat "$bind_benchmark"
    } | timeout --signal=TERM 3600 "$root/scripts/db_sql.sh" -
  } | tee "$bind_gate_mle_log"
  bind_gate_mle_chain="$(
    node "$extractor" "$bind_gate_mle_log" PMLE_PRESENTATION_BIND_RANK
  )"
  [[ "$bind_gate_mle_chain" == "$bind_gate_candidate_chain" ]] || {
    printf 'presentation bind 300-frame Node/MLE chain mismatch\n' >&2
    exit 1
  }
  node "$transport_comparator" --gate "$bind_gate_mle_log" |
    tee "$bind_gate_verdict_log"
  if [[ "$gate_status" == RAW_PASS ]]; then
    gate_status=RAW_AND_BIND_PASS
  else
    gate_status=BIND_PASS
  fi
fi
printf 'PASS PMLE-PRESENTATION-DECPS-RANK pinned_sha256=%s baseline_sha256=%s baseline_bytes=%s candidate_sha256=%s candidate_bytes=%s shared_input_bytecode_sha256=%s bind_source_bytes=%s bind_source_sha256=%s bind_transport=%s bind_direct_mode=%s chain_sha256=%s bind_chain_sha256=%s gate_300=%s authority_isolation_evidence=%s baseline_build=%s candidate_build=%s baseline_evidence=%s candidate_evidence=%s baseline_bind_install_evidence=%s bind_install_evidence=%s bind_evidence=%s raw_ab_evidence=%s transport_ab_evidence=%s temporary_lob_grant_evidence=%s\n' \
  "$pinned_presentation_sha" "$baseline_sha" "$baseline_bytes" \
  "$candidate_sha" "$candidate_bytes" "$authority_input_sha" \
  "$bind_source_bytes" "$bind_source_sha" "$bind_transport" \
  "$bind_direct_mode" \
  "$candidate_mle_chain" "$candidate_bind_chain" "$gate_status" \
  "${authority_isolation_log#"$root"/}" \
  "${baseline_build_evidence#"$root"/}" \
  "${candidate_build_evidence#"$root"/}" \
  "${baseline_mle_log#"$root"/}" "${candidate_mle_log#"$root"/}" \
  "${baseline_bind_install_log#"$root"/}" \
  "${candidate_bind_install_log#"$root"/}" \
  "${candidate_bind_mle_log#"$root"/}" \
  "${ab_log#"$root"/}" "${transport_ab_log#"$root"/}" \
  "${temporary_lob_grant_log#"$root"/}"
