#!/usr/bin/env bash
set -Eeuo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
project="$root/probes/mle/teavm-engine"
source_file="$project/dvr-bind-wrapper.mjs"
base64_fold_width=2000
emit_only=0
expected_engine_sha256=
expected_codec_sha256=

for option in "$@"; do
  case "$option" in
    --emit-sql) emit_only=1 ;;
    --engine-sha256=*) expected_engine_sha256="${option#--engine-sha256=}" ;;
    --codec-sha256=*) expected_codec_sha256="${option#--codec-sha256=}" ;;
    *) printf 'unsupported option: %s\n' "$option" >&2; exit 2 ;;
  esac
done

test -s "$source_file"
[[ "$expected_engine_sha256" =~ ^[0-9a-f]{64}$ ]] || {
  printf 'DVR bind loader requires --engine-sha256=<64 lowercase hex>\n' >&2
  exit 2
}
[[ "$expected_codec_sha256" =~ ^[0-9a-f]{64}$ ]] || {
  printf 'DVR bind loader requires --codec-sha256=<64 lowercase hex>\n' >&2
  exit 2
}
source_bytes="$(wc -c <"$source_file" | tr -d '[:space:]')"
source_sha256="$(shasum -a 256 "$source_file" | awk '{print $1}')"

emit_drop() {
  local kind="$1" name="$2" accepted="$3"
  printf "begin execute immediate 'drop %s %s'; exception when others then if sqlcode not in(%s) then raise;end if;end;\n/\n" \
    "$kind" "$name" "$accepted"
}

emit_sql() {
  printf '%s\n' \
    'whenever oserror exit failure rollback' \
    'whenever sqlerror exit sql.sqlcode rollback' \
    'set define off' \
    'set echo off' \
    'set verify off' \
    'set feedback off' \
    'set heading off' \
    'set pagesize 0' \
    'set linesize 32767' \
    'set trimspool on' \
    'set serveroutput on size unlimited'

  emit_drop procedure doom_dvr_bind_release -4043
  for name in \
      doom_dvr_bind_persist_batch doom_dvr_bind_persist_raw \
      doom_dvr_bind_batch_count doom_dvr_bind_append \
      doom_dvr_bind_reset_batch doom_dvr_bind_compressed_length \
      doom_dvr_bind_compressed_chunk doom_dvr_bind_frame_chunk \
      doom_dvr_bind_roundtrip doom_dvr_bind_compress doom_dvr_bind_render \
      doom_dvr_bind_step doom_dvr_bind_init \
      doom_dvr_bind_table_load doom_dvr_bind_table_allocate \
      doom_dvr_bind_load doom_dvr_bind_allocate; do
    emit_drop function "$name" -4043
  done
  emit_drop "mle module" doom_mle_dvr_bind "-4080,-4103"
  emit_drop "mle env" doom_mle_dvr_bind_env "-4080,-4103,-4104,-4105"
  emit_drop table doom_dvr_frame_sink -942
  emit_drop table doom_mle_dvr_bind_source -942

  printf '%s\n' \
    'create table doom_mle_dvr_bind_source(source_blob blob not null);' \
    'insert into doom_mle_dvr_bind_source values(empty_blob());' \
    'declare' \
    '  l_blob blob;' \
    '  l_raw raw(32767);' \
    'begin' \
    '  select source_blob into l_blob from doom_mle_dvr_bind_source for update;'

  base64 <"$source_file" | tr -d '\r\n' | fold -w "$base64_fold_width" |
    while IFS= read -r piece || [[ -n "$piece" ]]; do
      printf "  l_raw:=utl_encode.base64_decode(utl_raw.cast_to_raw('%s'));\n" \
        "$piece"
      printf '%s\n' \
        '  dbms_lob.writeappend(l_blob,utl_raw.length(l_raw),l_raw);'
    done

  printf '%s\n' \
    'end;' \
    '/' \
    'declare' \
    '  l_source blob; l_engine blob; l_codec blob;' \
    '  l_sha varchar2(64); l_engine_sha varchar2(64); l_codec_sha varchar2(64);' \
    'begin' \
    '  select source_blob into l_source from doom_mle_dvr_bind_source;' \
    '  l_sha:=lower(rawtohex(dbms_crypto.hash(l_source,dbms_crypto.hash_sh256)));' \
    "  if dbms_lob.getlength(l_source)<>$source_bytes or l_sha<>'$source_sha256' then" \
    "    raise_application_error(-20796,'DVR bind staging mismatch expected=$source_bytes/$source_sha256 actual='||dbms_lob.getlength(l_source)||'/'||l_sha);" \
    '  end if;' \
    '  select source_blob into l_engine from doom_teavm_sim_source;' \
    '  l_engine_sha:=lower(rawtohex(dbms_crypto.hash(l_engine,dbms_crypto.hash_sh256)));' \
    "  if l_engine_sha<>'$expected_engine_sha256' then" \
    "    raise_application_error(-20796,'DVR engine mismatch expected=$expected_engine_sha256 actual='||l_engine_sha);" \
    '  end if;' \
    '  select source_blob into l_codec from doom_mle_dvr_codec_source;' \
    '  l_codec_sha:=lower(rawtohex(dbms_crypto.hash(l_codec,dbms_crypto.hash_sh256)));' \
    "  if l_codec_sha<>'$expected_codec_sha256' then" \
    "    raise_application_error(-20796,'DVR codec mismatch expected=$expected_codec_sha256 actual='||l_codec_sha);" \
    '  end if;' \
    "  dbms_output.put_line('PMLE_DVR_BIND_STAGING|PASS|source_bytes=$source_bytes|source_sha256=$source_sha256|engine_sha256=$expected_engine_sha256|codec_sha256=$expected_codec_sha256');" \
    'end;' \
    '/' \
    'create table doom_dvr_frame_sink(' \
    '  sink_id number primary key,' \
    '  batch_id number not null,' \
    '  frame_count number not null,' \
    '  first_frame_id number not null,' \
    '  last_frame_id number not null,' \
    '  codec_id varchar2(32) not null,' \
    '  payload blob not null' \
    ');' \
    "insert into doom_dvr_frame_sink values(1,-1,0,-1,-1,'RAW_INDEXED_V1',empty_blob());" \
    "insert into doom_dvr_frame_sink values(2,-1,0,-1,-1,'DOOM_DFR1_RLE',empty_blob());" \
    "create mle env doom_mle_dvr_bind_env imports('doom_teavm_engine' module doom_teavm_simulation, 'doom_dvr_codec' module doom_mle_dvr_codec);" \
    "create mle module doom_mle_dvr_bind language javascript using blob (select source_blob from doom_mle_dvr_bind_source);" \
    '/' \
    "create function doom_dvr_bind_allocate(p_length number) return number as mle module doom_mle_dvr_bind env doom_mle_dvr_bind_env signature 'allocateIwad(number)';" \
    '/' \
    "create function doom_dvr_bind_load(p_offset number,p_chunk raw) return number as mle module doom_mle_dvr_bind env doom_mle_dvr_bind_env signature 'loadIwadChunk(number, Uint8Array)';" \
    '/' \
    "create function doom_dvr_bind_table_allocate(p_length number) return number as mle module doom_mle_dvr_bind env doom_mle_dvr_bind_env signature 'allocateTablePack(number)';" \
    '/' \
    "create function doom_dvr_bind_table_load(p_offset number,p_chunk raw) return number as mle module doom_mle_dvr_bind env doom_mle_dvr_bind_env signature 'loadTablePackChunk(number, Uint8Array)';" \
    '/' \
    "create function doom_dvr_bind_init(p_active_players number,p_deathmatch number,p_skill number,p_episode number,p_map number) return varchar2 as mle module doom_mle_dvr_bind env doom_mle_dvr_bind_env signature 'initializeMultiplayerGame(number, number, number, number, number)';" \
    '/' \
    "create function doom_dvr_bind_step(p_active_players number,p_membership_mask number,p_commands raw) return number as mle module doom_mle_dvr_bind env doom_mle_dvr_bind_env signature 'stepMultiplayerAuthoritative(number, number, Uint8Array)';" \
    '/' \
    "create function doom_dvr_bind_render(p_player_slot number) return number as mle module doom_mle_dvr_bind env doom_mle_dvr_bind_env signature 'renderRetain(number)';" \
    '/' \
    "create function doom_dvr_bind_compress return number as mle module doom_mle_dvr_bind env doom_mle_dvr_bind_env signature 'compressRetained()';" \
    '/' \
    "create function doom_dvr_bind_roundtrip return number as mle module doom_mle_dvr_bind env doom_mle_dvr_bind_env signature 'roundTripRetained()';" \
    '/' \
    "create function doom_dvr_bind_frame_chunk(p_offset number,p_length number) return raw as mle module doom_mle_dvr_bind env doom_mle_dvr_bind_env signature 'retainedFrameChunk(number, number)';" \
    '/' \
    "create function doom_dvr_bind_compressed_chunk(p_offset number,p_length number) return raw as mle module doom_mle_dvr_bind env doom_mle_dvr_bind_env signature 'retainedCompressedChunk(number, number)';" \
    '/' \
    "create function doom_dvr_bind_compressed_length return number as mle module doom_mle_dvr_bind env doom_mle_dvr_bind_env signature 'retainedCompressedLength()';" \
    '/' \
    "create function doom_dvr_bind_reset_batch return number as mle module doom_mle_dvr_bind env doom_mle_dvr_bind_env signature 'resetBatch()';" \
    '/' \
    "create function doom_dvr_bind_append(p_player_slot number,p_frame_id number) return number as mle module doom_mle_dvr_bind env doom_mle_dvr_bind_env signature 'renderCompressAppend(number, number)';" \
    '/' \
    "create function doom_dvr_bind_batch_count return number as mle module doom_mle_dvr_bind env doom_mle_dvr_bind_env signature 'batchCount()';" \
    '/' \
    "create function doom_dvr_bind_persist_raw(p_frame_id number) return number as mle module doom_mle_dvr_bind env doom_mle_dvr_bind_env signature 'persistRetainedRaw(number)';" \
    '/' \
    "create function doom_dvr_bind_persist_batch(p_batch_id number) return number as mle module doom_mle_dvr_bind env doom_mle_dvr_bind_env signature 'persistCompressedBatch(number)';" \
    '/' \
    "create procedure doom_dvr_bind_release as mle module doom_mle_dvr_bind env doom_mle_dvr_bind_env signature 'release()';" \
    '/' \
    'declare' \
    '  l_imports pls_integer;' \
    'begin' \
    '  select count(*) into l_imports from user_mle_env_imports' \
    "   where env_name='DOOM_MLE_DVR_BIND_ENV'" \
    "     and ((import_name='doom_teavm_engine' and module_name='DOOM_TEAVM_SIMULATION')" \
    "       or (import_name='doom_dvr_codec' and module_name='DOOM_MLE_DVR_CODEC'));" \
    '  if l_imports<>2 then' \
    "    raise_application_error(-20796,'DVR bind import mapping missing');" \
    '  end if;' \
    "  dbms_output.put_line('PMLE_DVR_BIND_INSTALL|PASS|codec=DOOM_DFR1_RLE|version=1|transport=persistent_returning_oracle_blob|temp_lobs=ZERO_BY_CONSTRUCTION|imports='||l_imports||'|source_bytes=$source_bytes|source_sha256=$source_sha256|engine_sha256=$expected_engine_sha256|codec_sha256=$expected_codec_sha256');" \
    'end;' \
    '/' \
    'commit;'
}

if [[ "$emit_only" == 1 ]]; then
  emit_sql
  exit 0
fi

output="$(mktemp "${TMPDIR:-/tmp}/doomdb-dvr-bind-load.XXXXXX")"
trap 'rm -f "$output"' EXIT HUP INT TERM
emit_sql | "$root/scripts/db_sql.sh" - >"$output"
cat "$output"
grep -Fxq \
  "PMLE_DVR_BIND_STAGING|PASS|source_bytes=$source_bytes|source_sha256=$source_sha256|engine_sha256=$expected_engine_sha256|codec_sha256=$expected_codec_sha256" \
  "$output"
grep -Fxq \
  "PMLE_DVR_BIND_INSTALL|PASS|codec=DOOM_DFR1_RLE|version=1|transport=persistent_returning_oracle_blob|temp_lobs=ZERO_BY_CONSTRUCTION|imports=2|source_bytes=$source_bytes|source_sha256=$source_sha256|engine_sha256=$expected_engine_sha256|codec_sha256=$expected_codec_sha256" \
  "$output"
printf 'PASS PMLE-DVR-BIND-INSTALL source_bytes=%s source_sha256=%s\n' \
  "$source_bytes" "$source_sha256"
