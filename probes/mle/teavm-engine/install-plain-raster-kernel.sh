#!/usr/bin/env bash
set -Eeuo pipefail

project="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source_file="$project/plain-raster-kernel.mjs"
emit_only=0
[[ "${1:-}" == --emit-sql ]] && emit_only=1
[[ "$#" -le 1 && -s "$source_file" && ! -L "$source_file" ]] || exit 2
sha="$(shasum -a 256 "$source_file" | awk '{print $1}')"
bytes="$(wc -c <"$source_file" | tr -d '[:space:]')"

emit_sql() {
  printf '%s\n' \
    'whenever oserror exit failure rollback' \
    'whenever sqlerror exit sql.sqlcode rollback' \
    'set define off echo off verify off feedback off heading off pages 0 lines 32767' \
    'set serveroutput on size unlimited' \
    "begin execute immediate 'drop procedure doom_plain_raster_release';exception when others then if sqlcode<>-4043 then raise;end if;end;" \
    '/' \
    "begin execute immediate 'drop function doom_plain_raster_footprint';exception when others then if sqlcode<>-4043 then raise;end if;end;" \
    '/' \
    "begin execute immediate 'drop function doom_plain_raster_frame';exception when others then if sqlcode<>-4043 then raise;end if;end;" \
    '/' \
    "begin execute immediate 'drop mle module doom_plain_raster_kernel';exception when others then if sqlcode not in(-4080,-4103) then raise;end if;end;" \
    '/' \
    "begin execute immediate 'drop table doom_plain_raster_source purge';exception when others then if sqlcode<>-942 then raise;end if;end;" \
    '/' \
    'create table doom_plain_raster_source(' \
    'source_blob blob not null,expected_bytes number not null,' \
    'expected_sha256 varchar2(64) not null);' \
    "insert into doom_plain_raster_source values(empty_blob(),$bytes,'$sha');" \
    'declare l_blob blob;l_raw raw(32767);begin' \
    'select source_blob into l_blob from doom_plain_raster_source for update;'
  base64 <"$source_file" | tr -d '\r\n' | fold -w 2000 |
    while IFS= read -r piece || [[ -n "$piece" ]]; do
      printf "l_raw:=utl_encode.base64_decode(utl_raw.cast_to_raw('%s'));\n" "$piece"
      printf '%s\n' 'dbms_lob.writeappend(l_blob,utl_raw.length(l_raw),l_raw);'
    done
  printf '%s\n' \
    'end;' \
    '/' \
    'declare l_count number;begin' \
    'select count(*) into l_count from doom_plain_raster_source' \
    'where dbms_lob.getlength(source_blob)=expected_bytes' \
    'and lower(rawtohex(dbms_crypto.hash(source_blob,dbms_crypto.hash_sh256)))=expected_sha256;' \
    "if l_count<>1 then raise_application_error(-20796,'plain raster staging mismatch');end if;" \
    "dbms_output.put_line('PMLE_PLAIN_RASTER_STAGING|PASS|bytes=$bytes|sha256=$sha');end;" \
    '/' \
    'create mle module doom_plain_raster_kernel language javascript using blob' \
    '(select source_blob from doom_plain_raster_source);' \
    '/' \
    "create function doom_plain_raster_frame(p_frames number)return number as mle module doom_plain_raster_kernel signature 'rasterFrame(number)';" \
    '/' \
    "create function doom_plain_raster_footprint return number as mle module doom_plain_raster_kernel signature 'footprint()';" \
    '/' \
    "create procedure doom_plain_raster_release as mle module doom_plain_raster_kernel signature 'release()';" \
    '/' \
    'commit;'
}

[[ "$emit_only" == 1 ]] || {
  printf '%s\n' 'plain raster installer is emit-only' >&2; exit 2; }
emit_sql
