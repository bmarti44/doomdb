#!/usr/bin/env bash
set -Eeuo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
project="$root/probes/mle/teavm-engine"
artifact="$project/target/javascript/doom-mle-simulation-engine-headless.js"
[[ -s "$artifact" ]] || { printf 'build the simulation candidate first\n' >&2;exit 2; }
bytes="$(wc -c <"$artifact" | tr -d '[:space:]')"
sha256="$(shasum -a 256 "$artifact" | awk '{print $1}')"
fold_width=2000
keep="${PMLE_INIT_DIET_KEEP:-0}"
[[ "$keep" == 0 || "$keep" == 1 ]] ||
  { printf 'PMLE_INIT_DIET_KEEP must be 0 or 1\n' >&2;exit 2; }

cleanup() {
  "$root/scripts/db_sql.sh" - >/dev/null 2>&1 <<'SQL' || true
begin execute immediate 'drop procedure doom_mle_diet_release';exception when others then null;end;
/
begin execute immediate 'drop function doom_mle_diet_state';exception when others then null;end;
/
begin execute immediate 'drop function doom_mle_diet_restore';exception when others then null;end;
/
begin execute immediate 'drop function doom_mle_diet_restore_load';exception when others then null;end;
/
begin execute immediate 'drop function doom_mle_diet_restore_allocate';exception when others then null;end;
/
begin execute immediate 'drop function doom_mle_diet_checkpoint_chunk';exception when others then null;end;
/
begin execute immediate 'drop function doom_mle_diet_checkpoint_length';exception when others then null;end;
/
begin execute immediate 'drop function doom_mle_diet_canonical_chunk';exception when others then null;end;
/
begin execute immediate 'drop function doom_mle_diet_canonical_length';exception when others then null;end;
/
begin execute immediate 'drop function doom_mle_diet_step';exception when others then null;end;
/
begin execute immediate 'drop function doom_mle_diet_step_command';exception when others then null;end;
/
begin execute immediate 'drop function doom_mle_diet_authority_step';exception when others then null;end;
/
begin execute immediate 'drop function doom_mle_diet_multi_step';exception when others then null;end;
/
begin execute immediate 'drop function doom_mle_diet_multi_init_skill';exception when others then null;end;
/
begin execute immediate 'drop function doom_mle_diet_multi_init';exception when others then null;end;
/
begin execute immediate 'drop function doom_mle_diet_initialize';exception when others then null;end;
/
begin execute immediate 'drop function doom_mle_diet_init';exception when others then null;end;
/
begin execute immediate 'drop function doom_mle_diet_multi_init_game';exception when others then null;end;
/
begin execute immediate 'drop function doom_mle_diet_table_load';exception when others then null;end;
/
begin execute immediate 'drop function doom_mle_diet_table_allocate';exception when others then null;end;
/
begin execute immediate 'drop function doom_mle_diet_load';exception when others then null;end;
/
begin execute immediate 'drop function doom_mle_diet_allocate';exception when others then null;end;
/
begin execute immediate 'drop mle module doom_mle_diet';exception when others then null;end;
/
begin execute immediate 'drop mle env doom_mle_diet_env';exception when others then null;end;
/
begin execute immediate 'drop table doom_mle_diet_source purge';exception when others then null;end;
/
SQL
}
if [[ "$keep" == 0 ]]; then trap cleanup EXIT;fi

{
  printf '%s\n' \
    'whenever oserror exit failure rollback' \
    'whenever sqlerror exit sql.sqlcode rollback' \
    'set define off echo off verify off feedback off heading off pages 0 lines 32767 trimspool on serveroutput on size unlimited' \
    'create table doom_mle_diet_source(source_blob blob not null);' \
    'insert into doom_mle_diet_source values(empty_blob());' \
    'declare l_blob blob;l_raw raw(32767);begin select source_blob into l_blob from doom_mle_diet_source for update;'
  base64 <"$artifact" | tr -d '\r\n' | fold -w "$fold_width" |
    while IFS= read -r piece || [[ -n "$piece" ]]; do
      printf "l_raw:=utl_encode.base64_decode(utl_raw.cast_to_raw('%s'));dbms_lob.writeappend(l_blob,utl_raw.length(l_raw),l_raw);\n" "$piece"
    done
  printf '%s\n' 'end;' '/' \
    "declare b blob;h varchar2(64);begin select source_blob into b from doom_mle_diet_source;h:=lower(rawtohex(dbms_crypto.hash(b,dbms_crypto.hash_sh256)));if dbms_lob.getlength(b)<>$bytes or h<>'$sha256' then raise_application_error(-20796,'init-diet source staging mismatch');end if;dbms_output.put_line('PMLE_INIT_DIET_STAGING|PASS|bytes=$bytes|sha256=$sha256');end;" '/' \
    'create mle env doom_mle_diet_env pure;' \
    'create mle module doom_mle_diet language javascript using blob (select source_blob from doom_mle_diet_source);' '/' \
    "create function doom_mle_diet_allocate(p_length number) return number as mle module doom_mle_diet env doom_mle_diet_env signature 'allocateIwad(number)';" '/' \
    "create function doom_mle_diet_load(p_offset number,p_chunk raw) return number as mle module doom_mle_diet env doom_mle_diet_env signature 'loadIwadChunk(number, Uint8Array)';" '/' \
    "create function doom_mle_diet_table_allocate(p_length number) return number as mle module doom_mle_diet env doom_mle_diet_env signature 'allocateTablePack(number)';" '/' \
    "create function doom_mle_diet_table_load(p_offset number,p_chunk raw) return number as mle module doom_mle_diet env doom_mle_diet_env signature 'loadTablePackChunk(number, Uint8Array)';" '/' \
    "create function doom_mle_diet_init(p_players number,p_deathmatch number,p_skill number,p_episode number,p_map number) return varchar2 as mle module doom_mle_diet env doom_mle_diet_env signature 'initializeMultiplayerGame(number, number, number, number, number)';" '/' \
    "create function doom_mle_diet_multi_init_game(p_players number,p_deathmatch number,p_skill number,p_episode number,p_map number) return varchar2 as mle module doom_mle_diet env doom_mle_diet_env signature 'initializeMultiplayerGame(number, number, number, number, number)';" '/' \
    "create function doom_mle_diet_initialize return varchar2 as mle module doom_mle_diet env doom_mle_diet_env signature 'initialize()';" '/' \
    "create function doom_mle_diet_multi_init(p_players number) return varchar2 as mle module doom_mle_diet env doom_mle_diet_env signature 'initializeMultiplayer(number)';" '/' \
    "create function doom_mle_diet_multi_init_skill(p_players number,p_skill number) return varchar2 as mle module doom_mle_diet env doom_mle_diet_env signature 'initializeMultiplayerAtSkill(number, number)';" '/' \
    "create function doom_mle_diet_multi_step(p_players number,p_commands raw) return number as mle module doom_mle_diet env doom_mle_diet_env signature 'stepMultiplayerBare(number, Uint8Array)';" '/' \
    "create function doom_mle_diet_authority_step(p_players number,p_membership_mask number,p_commands raw) return number as mle module doom_mle_diet env doom_mle_diet_env signature 'stepMultiplayerAuthoritative(number, number, Uint8Array)';" '/' \
    "create function doom_mle_diet_step(p_forward number,p_side number,p_turn number,p_buttons number) return varchar2 as mle module doom_mle_diet env doom_mle_diet_env signature 'step(number, number, number, number)';" '/' \
    "create function doom_mle_diet_step_command(p_forward number,p_side number,p_turn number,p_consistency number,p_buttons number) return number as mle module doom_mle_diet env doom_mle_diet_env signature 'stepCommandBare(number, number, number, number, number)';" '/' \
    "create function doom_mle_diet_canonical_length return number as mle module doom_mle_diet env doom_mle_diet_env signature 'canonicalStateLength()';" '/' \
    "create function doom_mle_diet_canonical_chunk(p_offset number,p_length number) return raw as mle module doom_mle_diet env doom_mle_diet_env signature 'canonicalStateChunk(number, number)';" '/' \
    "create function doom_mle_diet_checkpoint_length return number as mle module doom_mle_diet env doom_mle_diet_env signature 'checkpointLength()';" '/' \
    "create function doom_mle_diet_checkpoint_chunk(p_offset number,p_length number) return raw as mle module doom_mle_diet env doom_mle_diet_env signature 'checkpointChunk(number, number)';" '/' \
    "create function doom_mle_diet_restore_allocate(p_length number) return number as mle module doom_mle_diet env doom_mle_diet_env signature 'allocateCheckpoint(number)';" '/' \
    "create function doom_mle_diet_restore_load(p_offset number,p_chunk raw) return number as mle module doom_mle_diet env doom_mle_diet_env signature 'loadCheckpointChunk(number, Uint8Array)';" '/' \
    "create function doom_mle_diet_restore(p_expected_tic number) return varchar2 as mle module doom_mle_diet env doom_mle_diet_env signature 'restoreCheckpoint(number)';" '/' \
    "create function doom_mle_diet_state return varchar2 as mle module doom_mle_diet env doom_mle_diet_env signature 'currentState()';" '/' \
    "create procedure doom_mle_diet_release as mle module doom_mle_diet env doom_mle_diet_env signature 'release()';" '/' \
    'declare' \
    '  l_wad blob;l_pack blob;l_chunk raw(32767);l_length pls_integer;' \
    '  l_offset pls_integer;l_next number;l_started timestamp;l_ms number;' \
    '  l_state varchar2(32767);' \
    '  function elapsed_ms(p interval day to second)return number is' \
    '  begin return extract(day from p)*86400000+extract(hour from p)*3600000+' \
    '    extract(minute from p)*60000+extract(second from p)*1000;end;' \
    'begin' \
    "  select payload_bytes into l_wad from doom_engine_artifact where artifact_name='freedoom1.wad';" \
    '  l_length:=dbms_lob.getlength(l_wad);l_next:=doom_mle_diet_allocate(l_length);l_offset:=0;' \
    '  while l_offset<l_length loop l_chunk:=dbms_lob.substr(l_wad,least(32767,l_length-l_offset),l_offset+1);l_next:=doom_mle_diet_load(l_offset,l_chunk);l_offset:=l_offset+utl_raw.length(l_chunk);end loop;' \
    '  select table_pack_blob into l_pack from doom_teavm_sim_source;' \
    '  l_length:=dbms_lob.getlength(l_pack);l_next:=doom_mle_diet_table_allocate(l_length);l_offset:=0;' \
    '  while l_offset<l_length loop l_chunk:=dbms_lob.substr(l_pack,least(32767,l_length-l_offset),l_offset+1);l_next:=doom_mle_diet_table_load(l_offset,l_chunk);l_offset:=l_offset+utl_raw.length(l_chunk);end loop;' \
    '  l_started:=systimestamp;l_state:=doom_mle_diet_init(2,0,3,1,1);l_ms:=elapsed_ms(systimestamp-l_started);' \
    "  dbms_output.put_line('PMLE_INIT_DIET_MLE|wall_ms='||round(l_ms,3)||'|target_ms=30000|state='||doom_mle_diet_state);" \
    "  if l_ms>30000 then raise_application_error(-20795,'headless init diet exceeded target');end if;" \
    '  doom_mle_diet_release;' \
    'exception when others then begin doom_mle_diet_release;exception when others then null;end;raise;end;' '/'
} | "$root/scripts/db_sql.sh" -
