#!/usr/bin/env bash
set -Eeuo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source_file="$root/probes/mle/free-live-teavm/target/javascript/doom-mle-free-live-renderer.js"
pack_file="$root/probes/mle/target/free-live-renderer/free-live-render.pack"
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
  'function doom_free_gen_raster_writes' \
  'function doom_free_gen_native_misses' \
  'function doom_free_gen_native_commands' \
  'function doom_free_gen_native_record_length' \
  'function doom_free_gen_native_chunk' \
  'function doom_free_gen_native_tape' \
  'function doom_free_gen_frame_chunk' \
  'function doom_free_gen_frame_batch' 'function doom_free_gen_frame' \
  'function doom_free_gen_texture_finalize' \
  'function doom_free_gen_texture_load' \
  'function doom_free_gen_texture_allocate' \
  'function doom_free_gen_batch' 'function doom_free_gen_render' \
  'function doom_free_gen_finalize' 'function doom_free_gen_load' \
  'function doom_free_gen_allocate'; do
  printf "begin execute immediate 'drop %s';exception when others then if sqlcode<>-4043 then raise;end if;end;\n/\n" \
    "$object"
done
printf '%s\n' \
  "begin execute immediate 'drop mle module doom_free_generated_renderer';exception when others then if sqlcode not in(-4080,-4103) then raise;end if;end;" \
  '/' \
  "begin execute immediate 'drop table doom_free_generated_source purge';exception when others then if sqlcode<>-942 then raise;end if;end;" \
  '/' \
  'create table doom_free_generated_source(' \
  'source_blob blob not null,pack_blob blob not null,' \
  'source_bytes number not null,source_sha varchar2(64) not null,' \
  'pack_bytes number not null,pack_sha varchar2(64) not null);' \
  "insert into doom_free_generated_source values(empty_blob(),empty_blob(),$source_bytes,'$source_sha',$pack_bytes,'$pack_sha');" \
  'declare l_source blob;l_pack blob;l_raw raw(32767);begin' \
  'select source_blob,pack_blob into l_source,l_pack from doom_free_generated_source for update;'
emit_blob "$source_file" l_source
emit_blob "$pack_file" l_pack
printf '%s\n' \
  'end;' \
  '/' \
  'declare l_count number;begin' \
  'select count(*) into l_count from doom_free_generated_source' \
  'where dbms_lob.getlength(source_blob)=source_bytes' \
  'and dbms_lob.getlength(pack_blob)=pack_bytes' \
  'and lower(rawtohex(dbms_crypto.hash(source_blob,dbms_crypto.hash_sh256)))=source_sha' \
  'and lower(rawtohex(dbms_crypto.hash(pack_blob,dbms_crypto.hash_sh256)))=pack_sha;' \
  "if l_count<>1 then raise_application_error(-20796,'generated renderer staging mismatch');end if;" \
  "dbms_output.put_line('PMLE_FREE_LIVE_TEAVM_STAGING|PASS|source_bytes=$source_bytes|source_sha256=$source_sha|pack_bytes=$pack_bytes|pack_sha256=$pack_sha');end;" \
  '/' \
  'create mle module doom_free_generated_renderer language javascript using blob' \
  '(select source_blob from doom_free_generated_source);' \
  '/' \
  "create function doom_free_gen_allocate(p_length number)return number as mle module doom_free_generated_renderer signature 'allocatePack(number)';" \
  '/' \
  "create function doom_free_gen_load(p_offset number,p_chunk raw)return number as mle module doom_free_generated_renderer signature 'loadPackChunk(number, Uint8Array)';" \
  '/' \
  "create function doom_free_gen_finalize return number as mle module doom_free_generated_renderer signature 'finalizePack()';" \
  '/' \
  "create function doom_free_gen_render(p_pose number)return number as mle module doom_free_generated_renderer signature 'renderGeometry(number)';" \
  '/' \
  "create function doom_free_gen_batch(p_start number,p_count number)return number as mle module doom_free_generated_renderer signature 'renderGeometryBatch(number, number)';" \
  '/' \
  "create function doom_free_gen_texture_allocate(p_length number)return number as mle module doom_free_generated_renderer signature 'allocateWallTextures(number)';" \
  '/' \
  "create function doom_free_gen_texture_load(p_offset number,p_chunk raw)return number as mle module doom_free_generated_renderer signature 'loadWallTextureChunk(number, Uint8Array)';" \
  '/' \
  "create function doom_free_gen_texture_finalize return number as mle module doom_free_generated_renderer signature 'finalizeWallTextures()';" \
  '/' \
  "create function doom_free_gen_frame(p_pose number)return number as mle module doom_free_generated_renderer signature 'renderFrame(number)';" \
  '/' \
  "create function doom_free_gen_frame_batch(p_start number,p_count number)return number as mle module doom_free_generated_renderer signature 'renderFrameBatch(number, number)';" \
  '/' \
  "create function doom_free_gen_frame_chunk(p_offset number,p_length number)return raw as mle module doom_free_generated_renderer signature 'frameChunk(number, number)';" \
  '/' \
  "create function doom_free_gen_native_tape(p_pose number)return number as mle module doom_free_generated_renderer signature 'renderNativeTape(number)';" \
  '/' \
  "create function doom_free_gen_native_chunk(p_offset number,p_length number)return raw as mle module doom_free_generated_renderer signature 'nativeTapeChunk(number, number)';" \
  '/' \
  "create function doom_free_gen_native_record_length(p_offset number,p_maximum number)return number as mle module doom_free_generated_renderer signature 'nativeTapeRecordChunkLength(number, number)';" \
  '/' \
  "create function doom_free_gen_native_commands return number as mle module doom_free_generated_renderer signature 'nativeTapeCommandCount()';" \
  '/' \
  "create function doom_free_gen_native_misses return number as mle module doom_free_generated_renderer signature 'nativeTapeMissCount()';" \
  '/' \
  "create function doom_free_gen_raster_writes return number as mle module doom_free_generated_renderer signature 'rasterPixelWrites()';" \
  '/' \
  'commit;'
