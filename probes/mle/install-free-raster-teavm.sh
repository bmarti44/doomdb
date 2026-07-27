#!/usr/bin/env bash
set -Eeuo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source_file="$root/probes/mle/free-raster-teavm/target/javascript/doom-mle-free-raster-kernel.js"
[[ "${1:-}" == --emit-sql && "$#" == 1 ]] || {
  printf 'usage: %s --emit-sql\n' "$0" >&2;exit 2; }
[[ -s "$source_file" && ! -L "$source_file" ]] || exit 2
source_sha="$(shasum -a 256 "$source_file" | awk '{print $1}')"
source_bytes="$(wc -c <"$source_file" | tr -d '[:space:]')"

printf '%s\n' \
  'whenever oserror exit failure rollback' \
  'whenever sqlerror exit sql.sqlcode rollback' \
  'set define off echo off verify off feedback off heading off pages 0 lines 32767' \
  'set serveroutput on size unlimited'
for object in \
  'function doom_free_full_digest' \
  'function doom_free_full_view_chunk' \
  'function doom_free_full_view_prepare' \
  'function doom_free_full_count' \
  'function doom_free_full_batch' \
  'function doom_free_full_render' \
  'function doom_free_full_finalize' \
  'function doom_free_full_load' \
  'function doom_free_full_allocate' \
  'function doom_free_raster_frame_chunk' \
  'function doom_free_raster_command_count' \
  'function doom_free_raster_batch' \
  'function doom_free_raster_render' \
  'function doom_free_raster_finalize' \
  'function doom_free_raster_command_load' \
  'function doom_free_raster_command_allocate' \
  'function doom_free_raster_atlas_load' \
  'function doom_free_raster_atlas_allocate'; do
  printf "begin execute immediate 'drop %s';exception when others then if sqlcode<>-4043 then raise;end if;end;\n/\n" \
    "$object"
done
printf '%s\n' \
  "begin execute immediate 'drop mle module doom_free_raster_kernel';exception when others then if sqlcode not in(-4080,-4103) then raise;end if;end;" \
  '/' \
  "begin execute immediate 'drop table doom_free_raster_source purge';exception when others then if sqlcode<>-942 then raise;end if;end;" \
  '/' \
  'create table doom_free_raster_source(' \
  'source_blob blob not null,source_bytes number not null,source_sha varchar2(64) not null);' \
  "insert into doom_free_raster_source values(empty_blob(),$source_bytes,'$source_sha');" \
  'declare l_source blob;l_raw raw(32767);begin' \
  'select source_blob into l_source from doom_free_raster_source for update;'
base64 <"$source_file" | tr -d '\r\n' | fold -w 2000 |
  while IFS= read -r piece || [[ -n "$piece" ]]; do
    printf "l_raw:=utl_encode.base64_decode(utl_raw.cast_to_raw('%s'));\n" \
      "$piece"
    printf 'dbms_lob.writeappend(l_source,utl_raw.length(l_raw),l_raw);\n'
  done
printf '%s\n' \
  'end;' \
  '/' \
  'declare l_count number;begin' \
  'select count(*) into l_count from doom_free_raster_source' \
  'where dbms_lob.getlength(source_blob)=source_bytes' \
  'and lower(rawtohex(dbms_crypto.hash(source_blob,dbms_crypto.hash_sh256)))=source_sha;' \
  "if l_count<>1 then raise_application_error(-20796,'small raster staging mismatch');end if;" \
  "dbms_output.put_line('PMLE_FREE_RASTER_STAGING|PASS|source_bytes=$source_bytes|source_sha256=$source_sha');end;" \
  '/' \
  'create mle module doom_free_raster_kernel language javascript using blob' \
  '(select source_blob from doom_free_raster_source);' \
  '/' \
  "create function doom_free_raster_atlas_allocate(p_length number)return number as mle module doom_free_raster_kernel signature 'allocateAtlas(number)';" \
  '/' \
  "create function doom_free_raster_atlas_load(p_offset number,p_chunk raw)return number as mle module doom_free_raster_kernel signature 'loadAtlasChunk(number, Uint8Array)';" \
  '/' \
  "create function doom_free_raster_command_allocate(p_length number)return number as mle module doom_free_raster_kernel signature 'allocateCommands(number)';" \
  '/' \
  "create function doom_free_raster_command_load(p_offset number,p_chunk raw)return number as mle module doom_free_raster_kernel signature 'loadCommandChunk(number, Uint8Array)';" \
  '/' \
  "create function doom_free_raster_finalize return number as mle module doom_free_raster_kernel signature 'finalizeCommands()';" \
  '/' \
  "create function doom_free_raster_render(p_frame number)return number as mle module doom_free_raster_kernel signature 'renderFrame(number)';" \
  '/' \
  "create function doom_free_raster_batch(p_start number,p_count number)return number as mle module doom_free_raster_kernel signature 'renderBatch(number, number)';" \
  '/' \
  "create function doom_free_raster_command_count(p_frame number)return number as mle module doom_free_raster_kernel signature 'commandCount(number)';" \
  '/' \
  "create function doom_free_raster_frame_chunk(p_offset number,p_length number)return raw as mle module doom_free_raster_kernel signature 'frameChunk(number, number)';" \
  '/' \
  "create function doom_free_full_allocate(p_length number)return number as mle module doom_free_raster_kernel signature 'fullPackAllocate(number)';" \
  '/' \
  "create function doom_free_full_load(p_offset number,p_chunk raw)return number as mle module doom_free_raster_kernel signature 'fullPackLoad(number, Uint8Array)';" \
  '/' \
  "create function doom_free_full_finalize return number as mle module doom_free_raster_kernel signature 'fullPackFinalize()';" \
  '/' \
  "create function doom_free_full_render(p_frame number)return number as mle module doom_free_raster_kernel signature 'fullFrameRender(number)';" \
  '/' \
  "create function doom_free_full_batch(p_start number,p_count number)return number as mle module doom_free_raster_kernel signature 'fullFrameBatch(number, number)';" \
  '/' \
  "create function doom_free_full_count return number as mle module doom_free_raster_kernel signature 'fullFrameCount()';" \
  '/' \
  "create function doom_free_full_view_prepare return number as mle module doom_free_raster_kernel signature 'fullFramePrepareViewport()';" \
  '/' \
  "create function doom_free_full_view_chunk(p_offset number,p_length number)return raw as mle module doom_free_raster_kernel signature 'fullFrameViewportChunk(number, number)';" \
  '/' \
  "create function doom_free_full_digest(p_frame number)return raw as mle module doom_free_raster_kernel signature 'fullFrameViewportDigest(number)';" \
  '/' \
  'commit;'
