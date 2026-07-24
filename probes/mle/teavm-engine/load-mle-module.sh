#!/usr/bin/env bash
set -Eeuo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
project="$root/probes/mle/teavm-engine"
javascript="$project/target/javascript/doom-mle-simulation-engine-headless.js"
table_pack="$project/target/canonical-runtime-v2.bin"
expected_source_bytes=1171896
expected_source_sha256="e485b9418e5845b78e9e1593918d8bbb6f3c441c41a43cb8f3faf046e595148b"
expected_table_pack_sha256="058cd0df9444131b356762a096fd422d5131ac3aea91163aee056e8ad4965b44"
base64_fold_width=2000
build=1
emit_only=0
production=0
custom_source=0

for option in "$@"; do
  case "$option" in
    --no-build) build=0 ;;
    --emit-sql) emit_only=1 ;;
    --javascript=*) javascript="${option#--javascript=}";build=0;custom_source=1 ;;
    --table-pack=*) table_pack="${option#--table-pack=}";build=0;custom_source=1 ;;
    --production) production=1;build=0
      javascript="$root/client/dist/play/doom-mle-authority-e485b9418e58.js"
      table_pack="$root/client/dist/play/canonical-runtime-v2-058cd0df9444.bin"
      ;;
    *) printf 'unsupported option: %s\n' "$option" >&2;exit 2 ;;
  esac
done

if [[ "$production" == 1 && "$custom_source" == 1 ]]; then
  printf '%s\n' 'production load cannot override content-addressed artifacts' >&2
  exit 2
fi

if [[ "$build" == 1 ]]; then
  "$project/probe-simulation-engine.sh" simulation-engine-headless
fi
test -s "$javascript"
test -s "$table_pack"
bytes="$(wc -c <"$javascript" | tr -d '[:space:]')"
sha256="$(shasum -a 256 "$javascript" | awk '{print $1}')"
table_pack_bytes="$(wc -c <"$table_pack" | tr -d '[:space:]')"
table_pack_sha256="$(shasum -a 256 "$table_pack" | awk '{print $1}')"
has_warm_restore=0
if rg -F 'restoreCheckpointWarm' "$javascript" >/dev/null; then
  has_warm_restore=1
fi
if [[ "$production" == 1 &&
      ("$bytes" != "$expected_source_bytes" ||
       "$sha256" != "$expected_source_sha256") ]]; then
  printf 'pinned production MLE source drift: bytes=%s sha256=%s\n' \
    "$bytes" "$sha256" >&2
  exit 1
fi
[[ "$table_pack_bytes" == 180272 && "$table_pack_sha256" == "$expected_table_pack_sha256" ]] || {
  printf 'canonical table pack drift: bytes=%s sha256=%s\n' \
    "$table_pack_bytes" "$table_pack_sha256" >&2
  exit 1
}

emit_sql() {
  printf '%s\n' \
    'whenever oserror exit failure rollback' \
    'whenever sqlerror exit sql.sqlcode rollback' \
    'set define off echo off verify off feedback off heading off pages 0 lines 32767 trimspool on serveroutput on size unlimited' \
    "begin execute immediate 'drop procedure doom_teavm_sim_release'; exception when others then if sqlcode <> -4043 then raise; end if; end;" \
    '/' \
    "begin execute immediate 'drop function doom_teavm_sim_memory'; exception when others then if sqlcode <> -4043 then raise; end if; end;" \
    '/' \
    "begin execute immediate 'drop function doom_teavm_sim_state'; exception when others then if sqlcode <> -4043 then raise; end if; end;" \
    '/' \
    "begin execute immediate 'drop function doom_teavm_sim_canonical_state'; exception when others then if sqlcode <> -4043 then raise; end if; end;" \
    '/' \
    "begin execute immediate 'drop function doom_teavm_sim_canonical_chunk'; exception when others then if sqlcode <> -4043 then raise; end if; end;" \
    '/' \
    "begin execute immediate 'drop function doom_teavm_sim_canonical_length'; exception when others then if sqlcode <> -4043 then raise; end if; end;" \
    '/' \
    "begin execute immediate 'drop function doom_teavm_sim_checkpoint_chunk'; exception when others then if sqlcode <> -4043 then raise; end if; end;" \
    '/' \
    "begin execute immediate 'drop function doom_teavm_sim_checkpoint_length'; exception when others then if sqlcode <> -4043 then raise; end if; end;" \
    '/' \
    "begin execute immediate 'drop function doom_teavm_sim_restore'; exception when others then if sqlcode <> -4043 then raise; end if; end;" \
    '/' \
    "begin execute immediate 'drop function doom_teavm_sim_restore_warm'; exception when others then if sqlcode <> -4043 then raise; end if; end;" \
    '/' \
    "begin execute immediate 'drop function doom_teavm_sim_restore_load'; exception when others then if sqlcode <> -4043 then raise; end if; end;" \
    '/' \
    "begin execute immediate 'drop function doom_teavm_sim_restore_allocate'; exception when others then if sqlcode <> -4043 then raise; end if; end;" \
    '/' \
    "begin execute immediate 'drop function doom_teavm_sim_step'; exception when others then if sqlcode <> -4043 then raise; end if; end;" \
    '/' \
    "begin execute immediate 'drop function doom_teavm_sim_step_bare'; exception when others then if sqlcode <> -4043 then raise; end if; end;" \
    '/' \
    "begin execute immediate 'drop function doom_teavm_sim_step_command'; exception when others then if sqlcode <> -4043 then raise; end if; end;" \
    '/' \
    "begin execute immediate 'drop function doom_teavm_sim_initialize'; exception when others then if sqlcode <> -4043 then raise; end if; end;" \
    '/' \
    "begin execute immediate 'drop function doom_teavm_sim_multi_step'; exception when others then if sqlcode <> -4043 then raise; end if; end;" \
    '/' \
    "begin execute immediate 'drop function doom_teavm_sim_authority_step'; exception when others then if sqlcode <> -4043 then raise; end if; end;" \
    '/' \
    "begin execute immediate 'drop function doom_teavm_sim_multi_init'; exception when others then if sqlcode <> -4043 then raise; end if; end;" \
    '/' \
    "begin execute immediate 'drop function doom_teavm_sim_multi_init_skill'; exception when others then if sqlcode <> -4043 then raise; end if; end;" \
    '/' \
    "begin execute immediate 'drop function doom_teavm_sim_multi_init_game'; exception when others then if sqlcode <> -4043 then raise; end if; end;" \
    '/' \
    "begin execute immediate 'drop function doom_teavm_sim_load'; exception when others then if sqlcode <> -4043 then raise; end if; end;" \
    '/' \
    "begin execute immediate 'drop function doom_teavm_sim_allocate'; exception when others then if sqlcode <> -4043 then raise; end if; end;" \
    '/' \
    "begin execute immediate 'drop function doom_teavm_sim_table_load'; exception when others then if sqlcode <> -4043 then raise; end if; end;" \
    '/' \
    "begin execute immediate 'drop function doom_teavm_sim_table_allocate'; exception when others then if sqlcode <> -4043 then raise; end if; end;" \
    '/' \
    "begin execute immediate 'drop mle module doom_teavm_simulation'; exception when others then if sqlcode not in (-4080,-4103) then raise; end if; end;" \
    '/' \
    "begin execute immediate 'drop mle env doom_teavm_sim_env'; exception when others then if sqlcode not in (-4080,-4103,-4104,-4105) then raise; end if; end;" \
    '/' \
    "begin execute immediate 'drop table doom_teavm_sim_source purge'; exception when others then if sqlcode <> -942 then raise; end if; end;" \
    '/' \
    'create table doom_teavm_sim_source (source_blob blob not null,table_pack_blob blob not null);' \
    'insert into doom_teavm_sim_source values (empty_blob(),empty_blob());' \
    'declare' \
    '  l_blob blob;' \
    '  l_raw raw(32767);' \
    'begin' \
    '  select source_blob into l_blob from doom_teavm_sim_source for update;'

  base64 <"$javascript" | tr -d '\r\n' | fold -w "$base64_fold_width" |
    while IFS= read -r piece || [[ -n "$piece" ]]; do
      printf "  l_raw := utl_encode.base64_decode(utl_raw.cast_to_raw('%s'));\n" "$piece"
      printf '%s\n' '  dbms_lob.writeappend(l_blob, utl_raw.length(l_raw), l_raw);'
    done

  printf '%s\n' \
    'end;' \
    '/' \
    'declare' \
    '  l_blob blob;' \
    '  l_raw raw(32767);' \
    'begin' \
    '  select table_pack_blob into l_blob from doom_teavm_sim_source for update;'

  base64 <"$table_pack" | tr -d '\r\n' | fold -w "$base64_fold_width" |
    while IFS= read -r piece || [[ -n "$piece" ]]; do
      printf "  l_raw := utl_encode.base64_decode(utl_raw.cast_to_raw('%s'));\n" "$piece"
      printf '%s\n' '  dbms_lob.writeappend(l_blob, utl_raw.length(l_raw), l_raw);'
    done

  printf '%s\n' \
    'end;' \
    '/' \
    'declare' \
    '  l_source blob; l_tables blob;' \
    '  l_source_sha varchar2(64); l_tables_sha varchar2(64);' \
    'begin' \
    '  select source_blob,table_pack_blob into l_source,l_tables from doom_teavm_sim_source;' \
    '  l_source_sha:=lower(rawtohex(dbms_crypto.hash(l_source,dbms_crypto.hash_sh256)));' \
    '  l_tables_sha:=lower(rawtohex(dbms_crypto.hash(l_tables,dbms_crypto.hash_sh256)));' \
    "  if dbms_lob.getlength(l_source)<>$bytes or l_source_sha<>'$sha256' then" \
    "    raise_application_error(-20796,'MLE source staging mismatch expected=$bytes/$sha256 actual='||dbms_lob.getlength(l_source)||'/'||l_source_sha);" \
    '  end if;' \
    "  if dbms_lob.getlength(l_tables)<>$table_pack_bytes or l_tables_sha<>'$table_pack_sha256' then" \
    "    raise_application_error(-20796,'MLE table staging mismatch expected=$table_pack_bytes/$table_pack_sha256 actual='||dbms_lob.getlength(l_tables)||'/'||l_tables_sha);" \
    '  end if;' \
    "  dbms_output.put_line('PMLE_TEAVM_STAGING_GATE|PASS|source_bytes=$bytes|source_sha256=$sha256|table_bytes=$table_pack_bytes|table_sha256=$table_pack_sha256');" \
    'end;' \
    '/' \
    'create mle env doom_teavm_sim_env pure;' \
    "create mle module doom_teavm_simulation language javascript using blob (select source_blob from doom_teavm_sim_source);" \
    '/' \
    "create function doom_teavm_sim_allocate(p_length number) return number as mle module doom_teavm_simulation env doom_teavm_sim_env signature 'allocateIwad(number)';" \
    '/' \
    "create function doom_teavm_sim_load(p_offset number,p_chunk raw) return number as mle module doom_teavm_simulation env doom_teavm_sim_env signature 'loadIwadChunk(number, Uint8Array)';" \
    '/' \
    "create function doom_teavm_sim_table_allocate(p_length number) return number as mle module doom_teavm_simulation env doom_teavm_sim_env signature 'allocateTablePack(number)';" \
    '/' \
    "create function doom_teavm_sim_table_load(p_offset number,p_chunk raw) return number as mle module doom_teavm_simulation env doom_teavm_sim_env signature 'loadTablePackChunk(number, Uint8Array)';" \
    '/' \
    "create function doom_teavm_sim_initialize return varchar2 as mle module doom_teavm_simulation env doom_teavm_sim_env signature 'initialize()';" \
    '/' \
    "create function doom_teavm_sim_multi_init(p_active_players number) return varchar2 as mle module doom_teavm_simulation env doom_teavm_sim_env signature 'initializeMultiplayer(number)';" \
    '/' \
    "create function doom_teavm_sim_multi_init_skill(p_active_players number,p_skill number) return varchar2 as mle module doom_teavm_simulation env doom_teavm_sim_env signature 'initializeMultiplayerAtSkill(number, number)';" \
    '/' \
    "create function doom_teavm_sim_multi_init_game(p_active_players number,p_deathmatch number,p_skill number,p_episode number,p_map number) return varchar2 as mle module doom_teavm_simulation env doom_teavm_sim_env signature 'initializeMultiplayerGame(number, number, number, number, number)';" \
    '/' \
    "create function doom_teavm_sim_multi_step(p_active_players number,p_commands raw) return number as mle module doom_teavm_simulation env doom_teavm_sim_env signature 'stepMultiplayerBare(number, Uint8Array)';" \
    '/' \
    "create function doom_teavm_sim_authority_step(p_active_players number,p_membership_mask number,p_commands raw) return number as mle module doom_teavm_simulation env doom_teavm_sim_env signature 'stepMultiplayerAuthoritative(number, number, Uint8Array)';" \
    '/' \
    "create function doom_teavm_sim_step(p_forward number,p_side number,p_turn number,p_buttons number) return varchar2 as mle module doom_teavm_simulation env doom_teavm_sim_env signature 'step(number, number, number, number)';" \
    '/' \
    "create function doom_teavm_sim_step_bare(p_forward number,p_side number,p_turn number,p_buttons number) return number as mle module doom_teavm_simulation env doom_teavm_sim_env signature 'stepBare(number, number, number, number)';" \
    '/' \
    "create function doom_teavm_sim_step_command(p_forward number,p_side number,p_turn number,p_consistency number,p_buttons number) return number as mle module doom_teavm_simulation env doom_teavm_sim_env signature 'stepCommandBare(number, number, number, number, number)';" \
    '/' \
    "create function doom_teavm_sim_state return varchar2 as mle module doom_teavm_simulation env doom_teavm_sim_env signature 'currentState()';" \
    '/' \
    "create function doom_teavm_sim_canonical_state return varchar2 as mle module doom_teavm_simulation env doom_teavm_sim_env signature 'canonicalState()';" \
    '/' \
    "create function doom_teavm_sim_canonical_length return number as mle module doom_teavm_simulation env doom_teavm_sim_env signature 'canonicalStateLength()';" \
    '/' \
    "create function doom_teavm_sim_canonical_chunk(p_offset number,p_length number) return raw as mle module doom_teavm_simulation env doom_teavm_sim_env signature 'canonicalStateChunk(number, number)';" \
    '/' \
    "create function doom_teavm_sim_checkpoint_length return number as mle module doom_teavm_simulation env doom_teavm_sim_env signature 'checkpointLength()';" \
    '/' \
    "create function doom_teavm_sim_checkpoint_chunk(p_offset number,p_length number) return raw as mle module doom_teavm_simulation env doom_teavm_sim_env signature 'checkpointChunk(number, number)';" \
    '/' \
    "create function doom_teavm_sim_restore_allocate(p_length number) return number as mle module doom_teavm_simulation env doom_teavm_sim_env signature 'allocateCheckpoint(number)';" \
    '/' \
    "create function doom_teavm_sim_restore_load(p_offset number,p_chunk raw) return number as mle module doom_teavm_simulation env doom_teavm_sim_env signature 'loadCheckpointChunk(number, Uint8Array)';" \
    '/' \
    "create function doom_teavm_sim_restore(p_expected_tic number) return varchar2 as mle module doom_teavm_simulation env doom_teavm_sim_env signature 'restoreCheckpoint(number)';" \
    '/'

  if [[ "$has_warm_restore" == 1 ]]; then
    printf '%s\n' \
      "create function doom_teavm_sim_restore_warm(p_expected_tic number) return varchar2 as mle module doom_teavm_simulation env doom_teavm_sim_env signature 'restoreCheckpointWarm(number)';" \
      '/'
  fi

  printf '%s\n' \
    "create function doom_teavm_sim_memory return varchar2 as mle module doom_teavm_simulation env doom_teavm_sim_env signature 'memoryDiagnostic()';" \
    '/' \
    "create procedure doom_teavm_sim_release as mle module doom_teavm_simulation env doom_teavm_sim_env signature 'release()';" \
    '/' \
    "select 'PMLE_TEAVM_SIMULATION_LOAD|bytes='||dbms_lob.getlength(source_blob)||'|table_pack_bytes='||dbms_lob.getlength(table_pack_blob) from doom_teavm_sim_source;"
}

if [[ "$emit_only" == 1 ]]; then
  emit_sql
  exit 0
fi

output="$(mktemp "${TMPDIR:-/tmp}/doomdb-teavm-simulation-load.XXXXXX")"
trap 'rm -f "$output"' EXIT HUP INT TERM
emit_sql | "$root/scripts/db_sql.sh" - >"$output"
cat "$output"
grep -q "^PMLE_TEAVM_SIMULATION_LOAD|bytes=$bytes|table_pack_bytes=$table_pack_bytes$" "$output"
printf 'PASS PMLE-TEAVM-SIMULATION-LOAD bytes=%s sha256=%s table_pack_bytes=%s table_pack_sha256=%s\n' \
  "$bytes" "$sha256" "$table_pack_bytes" "$table_pack_sha256"
