#!/usr/bin/env bash
set -Eeuo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
pack="${PMLE_FULL_COMMAND_PACK:-$root/probes/mle/teavm-engine/target/full-command-capture-v3.bin}"
[[ "${1:-}" == --emit-sql && "$#" == 1 ]] || {
  printf 'usage: %s --emit-sql\n' "$0" >&2;exit 2; }
[[ -s "$pack" && ! -L "$pack" ]] || {
  printf 'full-command pack missing: %s\n' "$pack" >&2;exit 2; }
pack_sha="$(shasum -a 256 "$pack" | awk '{print $1}')"
pack_bytes="$(wc -c <"$pack" | tr -d '[:space:]')"

printf '%s\n' \
  'whenever oserror exit failure rollback' \
  'whenever sqlerror exit sql.sqlcode rollback' \
  'set define off echo off verify off feedback off heading off pages 0 lines 32767' \
  'set serveroutput on size unlimited' \
  "begin execute immediate 'drop table doom_free_full_pack purge';exception when others then if sqlcode<>-942 then raise;end if;end;" \
  '/' \
  'create table doom_free_full_pack(' \
  'pack_blob blob not null,pack_bytes number not null,pack_sha varchar2(64) not null);' \
  "insert into doom_free_full_pack values(empty_blob(),$pack_bytes,'$pack_sha');" \
  'declare l_blob blob;l_raw raw(32767);begin' \
  'select pack_blob into l_blob from doom_free_full_pack for update;'
base64 <"$pack" | tr -d '\r\n' | fold -w 2000 |
  while IFS= read -r piece || [[ -n "$piece" ]]; do
    printf "l_raw:=utl_encode.base64_decode(utl_raw.cast_to_raw('%s'));\n" \
      "$piece"
    printf 'dbms_lob.writeappend(l_blob,utl_raw.length(l_raw),l_raw);\n'
  done
printf '%s\n' \
  'end;' \
  '/' \
  'declare l_count number;begin' \
  'select count(*) into l_count from doom_free_full_pack' \
  'where dbms_lob.getlength(pack_blob)=pack_bytes' \
  'and lower(rawtohex(dbms_crypto.hash(pack_blob,dbms_crypto.hash_sh256)))=pack_sha;' \
  "if l_count<>1 then raise_application_error(-20796,'full-command staging mismatch');end if;" \
  "dbms_output.put_line('PMLE_FULL_COMMAND_STAGING|PASS|pack_bytes=$pack_bytes|pack_sha256=$pack_sha');end;" \
  '/' \
  'commit;'
