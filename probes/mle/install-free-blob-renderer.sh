#!/usr/bin/env bash
set -Eeuo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
wrapper="$root/probes/mle/free-live-renderer-blob.mjs"
[[ "${1:-}" == --emit-sql && "$#" == 1 ]] || {
  printf 'usage: %s --emit-sql\n' "$0" >&2;exit 2; }
[[ -s "$wrapper" && ! -L "$wrapper" ]] || exit 2
wrapper_sha="$(shasum -a 256 "$wrapper" | awk '{print $1}')"
wrapper_bytes="$(wc -c <"$wrapper" | tr -d '[:space:]')"

printf '%s\n' \
  'whenever oserror exit failure rollback' \
  'whenever sqlerror exit sql.sqlcode rollback' \
  'set define off echo off verify off feedback off heading off pages 0 lines 32767' \
  'set serveroutput on size unlimited'
for object in \
  'function doom_free_blob_ref_chunk' \
  'function doom_free_blob_ref_frame' \
  'function doom_free_blob_stats' \
  'function doom_free_blob_frame_chunk' \
  'function doom_free_blob_frame' \
  'function doom_free_blob_reset' \
  'function doom_free_blob_texture_finalize' \
  'function doom_free_blob_texture_load' \
  'function doom_free_blob_texture_allocate' \
  'function doom_free_blob_finalize' \
  'function doom_free_blob_load' \
  'function doom_free_blob_allocate'; do
  printf "begin execute immediate 'drop %s';exception when others then if sqlcode<>-4043 then raise;end if;end;\n/\n" \
    "$object"
done
printf '%s\n' \
  "begin execute immediate 'drop mle env doom_free_blob_env';exception when others then if sqlcode not in(-4080,-4103,-4105) then raise;end if;end;" \
  '/' \
  "begin execute immediate 'drop mle module doom_free_blob_renderer';exception when others then if sqlcode not in(-4080,-4103) then raise;end if;end;" \
  '/' \
  "begin execute immediate 'drop table doom_free_blob_source purge';exception when others then if sqlcode<>-942 then raise;end if;end;" \
  '/' \
  'create table doom_free_blob_source(' \
  'source_blob blob not null,source_bytes number not null,source_sha varchar2(64) not null);' \
  "insert into doom_free_blob_source values(empty_blob(),$wrapper_bytes,'$wrapper_sha');" \
  'declare l_source blob;l_raw raw(32767);begin' \
  'select source_blob into l_source from doom_free_blob_source for update;'
base64 <"$wrapper" | tr -d '\r\n' | fold -w 2000 |
  while IFS= read -r piece || [[ -n "$piece" ]]; do
    printf "l_raw:=utl_encode.base64_decode(utl_raw.cast_to_raw('%s'));\n" \
      "$piece"
    printf 'dbms_lob.writeappend(l_source,utl_raw.length(l_raw),l_raw);\n'
  done
printf '%s\n' \
  'end;' \
  '/' \
  'declare l_count number;begin' \
  'select count(*) into l_count from doom_free_blob_source' \
  'where dbms_lob.getlength(source_blob)=source_bytes' \
  'and lower(rawtohex(dbms_crypto.hash(source_blob,dbms_crypto.hash_sh256)))=source_sha;' \
  "if l_count<>1 then raise_application_error(-20796,'Blob renderer staging mismatch');end if;" \
  "dbms_output.put_line('PMLE_FREE_BLOB_STAGING|PASS|source_bytes=$wrapper_bytes|source_sha256=$wrapper_sha');end;" \
  '/' \
  "create mle env doom_free_blob_env imports('doom_free_generated_renderer' module doom_free_generated_renderer);" \
  'create mle module doom_free_blob_renderer language javascript using blob' \
  '(select source_blob from doom_free_blob_source);' \
  '/' \
  "create function doom_free_blob_allocate(p_length number)return number as mle module doom_free_blob_renderer env doom_free_blob_env signature 'allocatePack(number)';" \
  '/' \
  "create function doom_free_blob_load(p_offset number,p_chunk raw)return number as mle module doom_free_blob_renderer env doom_free_blob_env signature 'loadPackChunk(number, Uint8Array)';" \
  '/' \
  "create function doom_free_blob_finalize return number as mle module doom_free_blob_renderer env doom_free_blob_env signature 'finalizePack()';" \
  '/' \
  "create function doom_free_blob_texture_allocate(p_length number)return number as mle module doom_free_blob_renderer env doom_free_blob_env signature 'allocateWallTextures(number)';" \
  '/' \
  "create function doom_free_blob_texture_load(p_offset number,p_chunk raw)return number as mle module doom_free_blob_renderer env doom_free_blob_env signature 'loadWallTextureChunk(number, Uint8Array)';" \
  '/' \
  "create function doom_free_blob_texture_finalize return number as mle module doom_free_blob_renderer env doom_free_blob_env signature 'finalizeWallTextures()';" \
  '/' \
  "create function doom_free_blob_reset return number as mle module doom_free_blob_renderer env doom_free_blob_env signature 'reset()';" \
  '/' \
  "create function doom_free_blob_frame(p_pose number)return blob as mle module doom_free_blob_renderer env doom_free_blob_env signature 'renderFrame(number)';" \
  '/' \
  "create function doom_free_blob_frame_chunk(p_offset number,p_length number)return raw as mle module doom_free_blob_renderer env doom_free_blob_env signature 'frameChunk(number, number)';" \
  '/' \
  "create function doom_free_blob_stats return varchar2 as mle module doom_free_blob_renderer env doom_free_blob_env signature 'stats()';" \
  '/' \
  "create function doom_free_blob_ref_frame(p_pose number)return number as mle module doom_free_blob_renderer env doom_free_blob_env signature 'renderReference(number)';" \
  '/' \
  "create function doom_free_blob_ref_chunk(p_offset number,p_length number)return raw as mle module doom_free_blob_renderer env doom_free_blob_env signature 'referenceChunk(number, number)';" \
  '/' \
  'commit;'
