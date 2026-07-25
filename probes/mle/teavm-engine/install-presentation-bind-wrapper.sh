#!/usr/bin/env bash
set -Eeuo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
project="$root/probes/mle/teavm-engine"
source_file="$project/presentation-bind-wrapper.mjs"
base64_fold_width=2000
emit_only=0
expected_engine_sha256=

for option in "$@"; do
  case "$option" in
    --emit-sql) emit_only=1 ;;
    --engine-sha256=*) expected_engine_sha256="${option#--engine-sha256=}" ;;
    *) printf 'unsupported option: %s\n' "$option" >&2;exit 2 ;;
  esac
done

test -s "$source_file"
[[ "$expected_engine_sha256" =~ ^[0-9a-f]{64}$ ]] || {
  printf '%s\n' \
    'presentation bind loader requires --engine-sha256=<64 lowercase hex>' >&2
  exit 2
}
source_bytes="$(wc -c <"$source_file" | tr -d '[:space:]')"
source_sha256="$(shasum -a 256 "$source_file" | awk '{print $1}')"

emit_sql() {
  printf '%s\n' \
    'whenever oserror exit failure rollback' \
    'whenever sqlerror exit sql.sqlcode rollback' \
    'set define off echo off verify off feedback off heading off pages 0 lines 32767 trimspool on serveroutput on size unlimited' \
    "begin execute immediate 'drop procedure doom_teavm_bind_release'; exception when others then if sqlcode<>-4043 then raise;end if;end;" \
    '/' \
    "begin execute immediate 'drop function doom_teavm_bind_probe_direct'; exception when others then if sqlcode<>-4043 then raise;end if;end;" \
    '/' \
    "begin execute immediate 'drop function doom_teavm_bind_direct_mode'; exception when others then if sqlcode<>-4043 then raise;end if;end;" \
    '/' \
    "begin execute immediate 'drop function doom_teavm_bind_persist_locator'; exception when others then if sqlcode<>-4043 then raise;end if;end;" \
    '/' \
    "begin execute immediate 'drop function doom_teavm_bind_persist_direct'; exception when others then if sqlcode<>-4043 then raise;end if;end;" \
    '/' \
    "begin execute immediate 'drop function doom_teavm_bind_persist'; exception when others then if sqlcode<>-4043 then raise;end if;end;" \
    '/' \
    "begin execute immediate 'drop function doom_teavm_bind_frame_chunk'; exception when others then if sqlcode<>-4043 then raise;end if;end;" \
    '/' \
    "begin execute immediate 'drop function doom_teavm_bind_frame_length'; exception when others then if sqlcode<>-4043 then raise;end if;end;" \
    '/' \
    "begin execute immediate 'drop function doom_teavm_bind_authority_step'; exception when others then if sqlcode<>-4043 then raise;end if;end;" \
    '/' \
    "begin execute immediate 'drop function doom_teavm_bind_multi_init_game'; exception when others then if sqlcode<>-4043 then raise;end if;end;" \
    '/' \
    "begin execute immediate 'drop function doom_teavm_bind_table_load'; exception when others then if sqlcode<>-4043 then raise;end if;end;" \
    '/' \
    "begin execute immediate 'drop function doom_teavm_bind_table_allocate'; exception when others then if sqlcode<>-4043 then raise;end if;end;" \
    '/' \
    "begin execute immediate 'drop function doom_teavm_bind_load'; exception when others then if sqlcode<>-4043 then raise;end if;end;" \
    '/' \
    "begin execute immediate 'drop function doom_teavm_bind_allocate'; exception when others then if sqlcode<>-4043 then raise;end if;end;" \
    '/' \
    "begin execute immediate 'drop mle module doom_teavm_presentation_bind'; exception when others then if sqlcode not in(-4080,-4103) then raise;end if;end;" \
    '/' \
    "begin execute immediate 'drop mle env doom_teavm_presentation_bind_env'; exception when others then if sqlcode not in(-4080,-4103,-4104,-4105) then raise;end if;end;" \
    '/' \
    "begin execute immediate 'drop table doom_teavm_frame_sink purge'; exception when others then if sqlcode<>-942 then raise;end if;end;" \
    '/' \
    "begin execute immediate 'drop table doom_teavm_bind_source purge'; exception when others then if sqlcode<>-942 then raise;end if;end;" \
    '/' \
    'create table doom_teavm_bind_source(source_blob blob not null);' \
    'insert into doom_teavm_bind_source values(empty_blob());' \
    'declare' \
    '  l_blob blob;' \
    '  l_raw raw(32767);' \
    'begin' \
    '  select source_blob into l_blob from doom_teavm_bind_source for update;'

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
    '  l_source blob; l_engine blob;' \
    '  l_sha varchar2(64); l_engine_sha varchar2(64);' \
    'begin' \
    '  select source_blob into l_source from doom_teavm_bind_source;' \
    '  l_sha:=lower(rawtohex(dbms_crypto.hash(l_source,dbms_crypto.hash_sh256)));' \
    "  if dbms_lob.getlength(l_source)<>$source_bytes or l_sha<>'$source_sha256' then" \
    "    raise_application_error(-20796,'presentation bind staging mismatch expected=$source_bytes/$source_sha256 actual='||dbms_lob.getlength(l_source)||'/'||l_sha);" \
    '  end if;' \
    '  select source_blob into l_engine from doom_teavm_sim_source;' \
    '  l_engine_sha:=lower(rawtohex(dbms_crypto.hash(l_engine,dbms_crypto.hash_sh256)));' \
    "  if l_engine_sha<>'$expected_engine_sha256' then" \
    "    raise_application_error(-20796,'presentation bind engine mismatch expected=$expected_engine_sha256 actual='||l_engine_sha);" \
    '  end if;' \
    "  dbms_output.put_line('PMLE_PRESENTATION_BIND_STAGING|PASS|source_bytes=$source_bytes|source_sha256=$source_sha256|engine_sha256=$expected_engine_sha256');" \
    'end;' \
    '/' \
    'create table doom_teavm_frame_sink(' \
    '  sink_id number generated always as identity primary key,' \
    '  frame_id number not null,' \
    '  payload blob not null' \
    ');' \
    'insert into doom_teavm_frame_sink(frame_id,payload)' \
    'values(-1,empty_blob());' \
    "create mle env doom_teavm_presentation_bind_env imports('doom_teavm_engine' module doom_teavm_simulation);" \
    "create mle module doom_teavm_presentation_bind language javascript using blob (select source_blob from doom_teavm_bind_source);" \
    '/' \
    "create function doom_teavm_bind_allocate(p_length number) return number as mle module doom_teavm_presentation_bind env doom_teavm_presentation_bind_env signature 'allocateIwad(number)';" \
    '/' \
    "create function doom_teavm_bind_load(p_offset number,p_chunk raw) return number as mle module doom_teavm_presentation_bind env doom_teavm_presentation_bind_env signature 'loadIwadChunk(number, Uint8Array)';" \
    '/' \
    "create function doom_teavm_bind_table_allocate(p_length number) return number as mle module doom_teavm_presentation_bind env doom_teavm_presentation_bind_env signature 'allocateTablePack(number)';" \
    '/' \
    "create function doom_teavm_bind_table_load(p_offset number,p_chunk raw) return number as mle module doom_teavm_presentation_bind env doom_teavm_presentation_bind_env signature 'loadTablePackChunk(number, Uint8Array)';" \
    '/' \
    "create function doom_teavm_bind_multi_init_game(p_active_players number,p_deathmatch number,p_skill number,p_episode number,p_map number) return varchar2 as mle module doom_teavm_presentation_bind env doom_teavm_presentation_bind_env signature 'initializeMultiplayerGame(number, number, number, number, number)';" \
    '/' \
    "create function doom_teavm_bind_authority_step(p_active_players number,p_membership_mask number,p_commands raw) return number as mle module doom_teavm_presentation_bind env doom_teavm_presentation_bind_env signature 'stepMultiplayerAuthoritative(number, number, Uint8Array)';" \
    '/' \
    "create function doom_teavm_bind_frame_length(p_player_slot number) return number as mle module doom_teavm_presentation_bind env doom_teavm_presentation_bind_env signature 'renderPlayerFrameLength(number)';" \
    '/' \
    "create function doom_teavm_bind_frame_chunk(p_offset number,p_length number) return raw as mle module doom_teavm_presentation_bind env doom_teavm_presentation_bind_env signature 'renderPlayerFrameChunk(number, number)';" \
    '/' \
    "create function doom_teavm_bind_probe_direct return number as mle module doom_teavm_presentation_bind env doom_teavm_presentation_bind_env signature 'probeDirectBlobBind()';" \
    '/' \
    "create function doom_teavm_bind_direct_mode return varchar2 as mle module doom_teavm_presentation_bind env doom_teavm_presentation_bind_env signature 'directBlobBindCapability()';" \
    '/' \
    "create function doom_teavm_bind_persist_direct(p_player_slot number,p_frame_id number) return number as mle module doom_teavm_presentation_bind env doom_teavm_presentation_bind_env signature 'renderPlayerFramePersistDirect(number, number)';" \
    '/' \
    "create function doom_teavm_bind_persist_locator(p_player_slot number,p_frame_id number) return number as mle module doom_teavm_presentation_bind env doom_teavm_presentation_bind_env signature 'renderPlayerFramePersistLocator(number, number)';" \
    '/' \
    "create procedure doom_teavm_bind_release as mle module doom_teavm_presentation_bind env doom_teavm_presentation_bind_env signature 'release()';" \
    '/' \
    'declare' \
    "  l_imports pls_integer; l_direct_supported varchar2(3):='YES';" \
    "  l_direct_mode varchar2(32):='UNSUPPORTED';" \
    'begin' \
    '  select count(*) into l_imports from user_mle_env_imports' \
    "   where env_name='DOOM_TEAVM_PRESENTATION_BIND_ENV'" \
    "     and import_name='doom_teavm_engine'" \
    "     and module_name='DOOM_TEAVM_SIMULATION';" \
    '  if l_imports<>1 then' \
    "    raise_application_error(-20796,'presentation bind import mapping missing');" \
    '  end if;' \
    '  begin' \
    '    l_direct_mode:=doom_teavm_bind_direct_mode;' \
    "    if l_direct_mode not in('explicit_db_type_blob','implicit_target_blob') then" \
    "      raise_application_error(-20796,'invalid direct BLOB mode: '||l_direct_mode);" \
    '    end if;' \
    '    if doom_teavm_bind_probe_direct<>64000 then' \
    "      raise_application_error(-20796,'direct BLOB probe returned false');" \
    '    end if;' \
    '  exception when others then' \
    "    l_direct_supported:='NO';" \
    "    l_direct_mode:='UNSUPPORTED';" \
    "    dbms_output.put_line('PMLE_PRESENTATION_DIRECT_BIND|UNSUPPORTED|sqlcode='||sqlcode);" \
    '  end;' \
    "  dbms_output.put_line('PMLE_PRESENTATION_BIND_INSTALL|PASS|transports=direct_uint8array_blob_insert,persistent_returning_oracle_blob|direct_supported='||l_direct_supported||'|direct_mode='||l_direct_mode||'|frame_bytes=64000|imports='||l_imports||'|source_bytes=$source_bytes|source_sha256=$source_sha256|engine_sha256=$expected_engine_sha256');" \
    'end;' \
    '/' \
    'commit;'
}

if [[ "$emit_only" == 1 ]]; then
  emit_sql
  exit 0
fi

output="$(mktemp "${TMPDIR:-/tmp}/doomdb-presentation-bind-load.XXXXXX")"
trap 'rm -f "$output"' EXIT HUP INT TERM
emit_sql | "$root/scripts/db_sql.sh" - >"$output"
cat "$output"
grep -q "^PMLE_PRESENTATION_BIND_STAGING|PASS|source_bytes=$source_bytes|source_sha256=$source_sha256|engine_sha256=$expected_engine_sha256$" \
  "$output"
grep -Eq "^PMLE_PRESENTATION_BIND_INSTALL\\|PASS\\|transports=direct_uint8array_blob_insert,persistent_returning_oracle_blob\\|direct_supported=(YES|NO)\\|direct_mode=(explicit_db_type_blob|implicit_target_blob|UNSUPPORTED)\\|frame_bytes=64000\\|imports=1\\|source_bytes=$source_bytes\\|source_sha256=$source_sha256\\|engine_sha256=$expected_engine_sha256$" \
  "$output"
printf 'PASS PMLE-PRESENTATION-BIND-INSTALL source_bytes=%s source_sha256=%s engine_sha256=%s\n' \
  "$source_bytes" "$source_sha256" "$expected_engine_sha256"
