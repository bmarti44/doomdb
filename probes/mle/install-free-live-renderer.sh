#!/usr/bin/env bash
set -Eeuo pipefail

project="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source_file="$project/free-live-renderer.mjs"
pack_file="$project/target/free-live-renderer/free-live-render.pack"
[[ "${1:-}" == --emit-sql && "$#" == 1 ]] || {
  printf 'usage: %s --emit-sql\n' "$0" >&2;exit 2; }
for input in "$source_file" "$pack_file"; do
  [[ -s "$input" && ! -L "$input" ]] || exit 2
done
source_sha="$(shasum -a 256 "$source_file" | awk '{print $1}')"
source_bytes="$(wc -c <"$source_file" | tr -d '[:space:]')"
pack_sha="$(shasum -a 256 "$pack_file" | awk '{print $1}')"
pack_bytes="$(wc -c <"$pack_file" | tr -d '[:space:]')"

emit_blob() {
  local file="$1" target="$2"
  base64 <"$file" | tr -d '\r\n' | fold -w 2000 |
    while IFS= read -r piece || [[ -n "$piece" ]]; do
      printf "l_raw:=utl_encode.base64_decode(utl_raw.cast_to_raw('%s'));\n" \
        "$piece"
      printf 'dbms_lob.writeappend(%s,utl_raw.length(l_raw),l_raw);\n' "$target"
    done
}

printf '%s\n' \
  'whenever oserror exit failure rollback' \
  'whenever sqlerror exit sql.sqlcode rollback' \
  'set define off echo off verify off feedback off heading off pages 0 lines 32767' \
  'set serveroutput on size unlimited'
for object in \
  'procedure doom_free_live_release' \
  'function doom_free_live_stats' \
  'function doom_free_live_frame_chunk' \
  'function doom_free_live_render_batch' \
  'function doom_free_live_render' \
  'function doom_free_live_texture_finalize' \
  'function doom_free_live_texture_load' \
  'function doom_free_live_texture_allocate' \
  'function doom_free_live_finalize' \
  'function doom_free_live_load' \
  'function doom_free_live_allocate'; do
  printf "begin execute immediate 'drop %s';exception when others then if sqlcode<>-4043 then raise;end if;end;\n/\n" \
    "$object"
done
printf '%s\n' \
  "begin execute immediate 'drop mle module doom_free_live_renderer';exception when others then if sqlcode not in(-4080,-4103) then raise;end if;end;" \
  '/' \
  "begin execute immediate 'drop table doom_free_live_source purge';exception when others then if sqlcode<>-942 then raise;end if;end;" \
  '/' \
  'create table doom_free_live_source(' \
  'source_blob blob not null,pack_blob blob not null,' \
  'source_bytes number not null,source_sha varchar2(64) not null,' \
  'pack_bytes number not null,pack_sha varchar2(64) not null,' \
  'repeat_start number);' \
  "insert into doom_free_live_source values(empty_blob(),empty_blob(),$source_bytes,'$source_sha',$pack_bytes,'$pack_sha',null);" \
  'declare l_source blob;l_pack blob;l_raw raw(32767);begin' \
  'select source_blob,pack_blob into l_source,l_pack from doom_free_live_source for update;'
emit_blob "$source_file" l_source
emit_blob "$pack_file" l_pack
printf '%s\n' \
  'end;' \
  '/' \
  'declare l_count number;begin' \
  'select count(*) into l_count from doom_free_live_source' \
  'where dbms_lob.getlength(source_blob)=source_bytes' \
  'and dbms_lob.getlength(pack_blob)=pack_bytes' \
  'and lower(rawtohex(dbms_crypto.hash(source_blob,dbms_crypto.hash_sh256)))=source_sha' \
  'and lower(rawtohex(dbms_crypto.hash(pack_blob,dbms_crypto.hash_sh256)))=pack_sha;' \
  "if l_count<>1 then raise_application_error(-20796,'free live staging mismatch');end if;" \
  "dbms_output.put_line('PMLE_FREE_LIVE_STAGING|PASS|source_bytes=$source_bytes|source_sha256=$source_sha|pack_bytes=$pack_bytes|pack_sha256=$pack_sha');end;" \
  '/' \
  'create mle module doom_free_live_renderer language javascript using blob' \
  '(select source_blob from doom_free_live_source);' \
  '/' \
  "create function doom_free_live_allocate(p_length number)return number as mle module doom_free_live_renderer signature 'allocatePack(number)';" \
  '/' \
  "create function doom_free_live_load(p_offset number,p_chunk raw)return number as mle module doom_free_live_renderer signature 'loadPackChunk(number, Uint8Array)';" \
  '/' \
  "create function doom_free_live_finalize return number as mle module doom_free_live_renderer signature 'finalizePack()';" \
  '/' \
  "create function doom_free_live_texture_allocate(p_length number)return number as mle module doom_free_live_renderer signature 'allocateWallTextures(number)';" \
  '/' \
  "create function doom_free_live_texture_load(p_offset number,p_chunk raw)return number as mle module doom_free_live_renderer signature 'loadWallTextureChunk(number, Uint8Array)';" \
  '/' \
  "create function doom_free_live_texture_finalize return number as mle module doom_free_live_renderer signature 'finalizeWallTextures()';" \
  '/' \
  "create function doom_free_live_render(p_pose number)return number as mle module doom_free_live_renderer signature 'renderPose(number)';" \
  '/' \
  "create function doom_free_live_render_batch(p_start number,p_count number)return number as mle module doom_free_live_renderer signature 'renderBatch(number, number)';" \
  '/' \
  "create function doom_free_live_frame_chunk(p_offset number,p_length number)return raw as mle module doom_free_live_renderer signature 'frameChunk(number, number)';" \
  '/' \
  "create function doom_free_live_stats return varchar2 as mle module doom_free_live_renderer signature 'stats()';" \
  '/' \
  "create procedure doom_free_live_release as mle module doom_free_live_renderer signature 'release()';" \
  '/' \
  'declare l_pack blob;l_bytes number;l_offset number:=0;l_chunk raw(16000);l_loaded number;begin' \
  'select pack_blob,pack_bytes into l_pack,l_bytes from doom_free_live_source;' \
  'l_loaded:=doom_free_live_allocate(l_bytes);' \
  "if l_loaded<>l_bytes then raise_application_error(-20796,'free live allocation mismatch');end if;" \
  'while l_offset<l_bytes loop' \
  'l_chunk:=dbms_lob.substr(l_pack,least(16000,l_bytes-l_offset),l_offset+1);' \
  'l_loaded:=doom_free_live_load(l_offset,l_chunk);' \
  'l_offset:=l_offset+utl_raw.length(l_chunk);' \
  "if l_loaded<>l_offset then raise_application_error(-20796,'free live load mismatch');end if;" \
  'end loop;' \
  "if doom_free_live_finalize<>l_bytes then raise_application_error(-20796,'free live finalize mismatch');end if;" \
  "dbms_output.put_line('PMLE_FREE_LIVE_PACK_LOAD|PASS|bytes='||l_bytes||'|'||doom_free_live_stats);end;" \
  '/' \
  'declare l_blob blob;l_bytes number;l_expected_sha varchar2(64);l_actual_sha varchar2(64);' \
  'l_offset number:=0;l_chunk raw(16000);l_loaded number;begin' \
  "select encoded_bytes,dbms_lob.getlength(encoded_bytes),payload_sha256 into l_blob,l_bytes,l_expected_sha from doom_renderer_asset_pack where asset_kind='wall_texture';" \
  'l_actual_sha:=lower(rawtohex(dbms_crypto.hash(l_blob,dbms_crypto.hash_sh256)));' \
  "if l_actual_sha<>l_expected_sha then raise_application_error(-20796,'wall texture source hash mismatch');end if;" \
  'l_loaded:=doom_free_live_texture_allocate(l_bytes);' \
  'while l_offset<l_bytes loop' \
  'l_chunk:=dbms_lob.substr(l_blob,least(16000,l_bytes-l_offset),l_offset+1);' \
  'l_loaded:=doom_free_live_texture_load(l_offset,l_chunk);' \
  'l_offset:=l_offset+utl_raw.length(l_chunk);' \
  "if l_loaded<>l_offset then raise_application_error(-20796,'wall texture load mismatch');end if;" \
  'end loop;' \
  "if doom_free_live_texture_finalize<>l_bytes then raise_application_error(-20796,'wall texture finalize mismatch');end if;" \
  "dbms_output.put_line('PMLE_FREE_LIVE_TEXTURE_LOAD|PASS|bytes='||l_bytes||'|sha256='||l_actual_sha);end;" \
  '/' \
  'commit;'
