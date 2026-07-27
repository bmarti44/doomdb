#!/usr/bin/env bash
set -Eeuo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
generated_file="$root/probes/mle/free-live-teavm/target/javascript/doom-mle-free-live-renderer.js"
wrapper_file="$root/probes/mle/free-live-renderer-hybrid.mjs"
pack_file="$root/probes/mle/target/free-live-renderer/free-live-render.pack"
[[ "${1:-}" == --emit-sql && "$#" == 1 ]] || {
  printf 'usage: %s --emit-sql\n' "$0" >&2;exit 2; }
for input in "$generated_file" "$wrapper_file" "$pack_file"; do
  [[ -s "$input" && ! -L "$input" ]] || {
    printf 'hybrid renderer input missing: %s\n' "$input" >&2;exit 2; }
done

generated_sha="$(shasum -a 256 "$generated_file" | awk '{print $1}')"
generated_bytes="$(wc -c <"$generated_file" | tr -d '[:space:]')"
wrapper_sha="$(shasum -a 256 "$wrapper_file" | awk '{print $1}')"
wrapper_bytes="$(wc -c <"$wrapper_file" | tr -d '[:space:]')"
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
  'function doom_free_hybrid_stats' \
  'function doom_free_hybrid_frame_chunk' \
  'function doom_free_hybrid_frame_batch' \
  'function doom_free_hybrid_frame' \
  'function doom_free_hybrid_texture_finalize' \
  'function doom_free_hybrid_texture_load' \
  'function doom_free_hybrid_texture_allocate' \
  'function doom_free_hybrid_finalize' \
  'function doom_free_hybrid_load' \
  'function doom_free_hybrid_allocate' \
  'function doom_free_gen_frame_chunk' \
  'function doom_free_gen_frame' \
  'function doom_free_gen_texture_finalize' \
  'function doom_free_gen_texture_load' \
  'function doom_free_gen_texture_allocate' \
  'function doom_free_gen_finalize' \
  'function doom_free_gen_load' \
  'function doom_free_gen_allocate'; do
  printf "begin execute immediate 'drop %s';exception when others then if sqlcode<>-4043 then raise;end if;end;\n/\n" \
    "$object"
done
printf '%s\n' \
  "begin execute immediate 'drop mle env doom_free_hybrid_env';exception when others then if sqlcode not in(-4080,-4103,-4105) then raise;end if;end;" \
  '/'
for module in doom_free_hybrid_renderer doom_free_generated_renderer; do
  printf "begin execute immediate 'drop mle module %s';exception when others then if sqlcode not in(-4080,-4103) then raise;end if;end;\n/\n" \
    "$module"
done
printf '%s\n' \
  "begin execute immediate 'drop table doom_free_hybrid_source purge';exception when others then if sqlcode<>-942 then raise;end if;end;" \
  '/' \
  'create table doom_free_hybrid_source(' \
  'generated_blob blob not null,wrapper_blob blob not null,pack_blob blob not null,' \
  'generated_bytes number not null,generated_sha varchar2(64) not null,' \
  'wrapper_bytes number not null,wrapper_sha varchar2(64) not null,' \
  'pack_bytes number not null,pack_sha varchar2(64) not null);' \
  "insert into doom_free_hybrid_source values(empty_blob(),empty_blob(),empty_blob(),$generated_bytes,'$generated_sha',$wrapper_bytes,'$wrapper_sha',$pack_bytes,'$pack_sha');" \
  'declare l_generated blob;l_wrapper blob;l_pack blob;l_raw raw(32767);begin' \
  'select generated_blob,wrapper_blob,pack_blob into l_generated,l_wrapper,l_pack from doom_free_hybrid_source for update;'
emit_blob "$generated_file" l_generated
emit_blob "$wrapper_file" l_wrapper
emit_blob "$pack_file" l_pack
printf '%s\n' \
  'end;' \
  '/' \
  'declare l_count number;begin' \
  'select count(*) into l_count from doom_free_hybrid_source' \
  'where dbms_lob.getlength(generated_blob)=generated_bytes' \
  'and dbms_lob.getlength(wrapper_blob)=wrapper_bytes' \
  'and dbms_lob.getlength(pack_blob)=pack_bytes' \
  'and lower(rawtohex(dbms_crypto.hash(generated_blob,dbms_crypto.hash_sh256)))=generated_sha' \
  'and lower(rawtohex(dbms_crypto.hash(wrapper_blob,dbms_crypto.hash_sh256)))=wrapper_sha' \
  'and lower(rawtohex(dbms_crypto.hash(pack_blob,dbms_crypto.hash_sh256)))=pack_sha;' \
  "if l_count<>1 then raise_application_error(-20796,'hybrid renderer staging mismatch');end if;" \
  "dbms_output.put_line('PMLE_FREE_LIVE_HYBRID_STAGING|PASS|generated_bytes=$generated_bytes|generated_sha256=$generated_sha|wrapper_bytes=$wrapper_bytes|wrapper_sha256=$wrapper_sha|pack_bytes=$pack_bytes|pack_sha256=$pack_sha');end;" \
  '/' \
  'create mle module doom_free_generated_renderer language javascript using blob' \
  '(select generated_blob from doom_free_hybrid_source);' \
  '/' \
  "create mle env doom_free_hybrid_env imports('doom_free_generated_renderer' module doom_free_generated_renderer);" \
  'create mle module doom_free_hybrid_renderer language javascript using blob' \
  '(select wrapper_blob from doom_free_hybrid_source);' \
  '/' \
  "create function doom_free_hybrid_allocate(p_length number)return number as mle module doom_free_hybrid_renderer env doom_free_hybrid_env signature 'allocatePack(number)';" \
  '/' \
  "create function doom_free_hybrid_load(p_offset number,p_chunk raw)return number as mle module doom_free_hybrid_renderer env doom_free_hybrid_env signature 'loadPackChunk(number, Uint8Array)';" \
  '/' \
  "create function doom_free_hybrid_finalize return number as mle module doom_free_hybrid_renderer env doom_free_hybrid_env signature 'finalizePack()';" \
  '/' \
  "create function doom_free_hybrid_texture_allocate(p_length number)return number as mle module doom_free_hybrid_renderer env doom_free_hybrid_env signature 'allocateWallTextures(number)';" \
  '/' \
  "create function doom_free_hybrid_texture_load(p_offset number,p_chunk raw)return number as mle module doom_free_hybrid_renderer env doom_free_hybrid_env signature 'loadWallTextureChunk(number, Uint8Array)';" \
  '/' \
  "create function doom_free_hybrid_texture_finalize return number as mle module doom_free_hybrid_renderer env doom_free_hybrid_env signature 'finalizeWallTextures()';" \
  '/' \
  "create function doom_free_hybrid_frame(p_pose number)return number as mle module doom_free_hybrid_renderer env doom_free_hybrid_env signature 'renderFrame(number)';" \
  '/' \
  "create function doom_free_hybrid_frame_batch(p_start number,p_count number)return number as mle module doom_free_hybrid_renderer env doom_free_hybrid_env signature 'renderFrameBatch(number, number)';" \
  '/' \
  "create function doom_free_hybrid_frame_chunk(p_offset number,p_length number)return raw as mle module doom_free_hybrid_renderer env doom_free_hybrid_env signature 'frameChunk(number, number)';" \
  '/' \
  "create function doom_free_hybrid_stats return varchar2 as mle module doom_free_hybrid_renderer env doom_free_hybrid_env signature 'stats()';" \
  '/' \
  "create function doom_free_gen_allocate(p_length number)return number as mle module doom_free_generated_renderer env doom_free_hybrid_env signature 'allocatePack(number)';" \
  '/' \
  "create function doom_free_gen_load(p_offset number,p_chunk raw)return number as mle module doom_free_generated_renderer env doom_free_hybrid_env signature 'loadPackChunk(number, Uint8Array)';" \
  '/' \
  "create function doom_free_gen_finalize return number as mle module doom_free_generated_renderer env doom_free_hybrid_env signature 'finalizePack()';" \
  '/' \
  "create function doom_free_gen_texture_allocate(p_length number)return number as mle module doom_free_generated_renderer env doom_free_hybrid_env signature 'allocateWallTextures(number)';" \
  '/' \
  "create function doom_free_gen_texture_load(p_offset number,p_chunk raw)return number as mle module doom_free_generated_renderer env doom_free_hybrid_env signature 'loadWallTextureChunk(number, Uint8Array)';" \
  '/' \
  "create function doom_free_gen_texture_finalize return number as mle module doom_free_generated_renderer env doom_free_hybrid_env signature 'finalizeWallTextures()';" \
  '/' \
  "create function doom_free_gen_frame(p_pose number)return number as mle module doom_free_generated_renderer env doom_free_hybrid_env signature 'renderFrame(number)';" \
  '/' \
  "create function doom_free_gen_frame_chunk(p_offset number,p_length number)return raw as mle module doom_free_generated_renderer env doom_free_hybrid_env signature 'frameChunk(number, number)';" \
  '/' \
  'commit;'
