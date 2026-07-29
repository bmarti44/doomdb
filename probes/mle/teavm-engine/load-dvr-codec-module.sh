#!/usr/bin/env bash
set -Eeuo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
default_artifact="$root/artifacts/performance/pmle-dvr-compression/dvr-codec-candidate-e44884a58a0b.js"
artifact="$default_artifact"
base64_fold_width=2000
emit_only=0

for option in "$@"; do
  case "$option" in
    --emit-sql) emit_only=1 ;;
    --artifact=*) artifact="${option#--artifact=}" ;;
    *) printf 'unsupported option: %s\n' "$option" >&2; exit 2 ;;
  esac
done

test -s "$artifact"
artifact_bytes="$(wc -c <"$artifact" | tr -d '[:space:]')"
artifact_sha256="$(shasum -a 256 "$artifact" | awk '{print $1}')"

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
    'set serveroutput on size unlimited' \
    "begin execute immediate 'drop mle module doom_mle_dvr_codec'; exception when others then if sqlcode not in(-4080,-4103) then raise;end if;end;" \
    '/' \
    "begin execute immediate 'drop table doom_mle_dvr_codec_source purge'; exception when others then if sqlcode<>-942 then raise;end if;end;" \
    '/' \
    'create table doom_mle_dvr_codec_source(source_blob blob not null);' \
    'insert into doom_mle_dvr_codec_source values(empty_blob());' \
    'declare' \
    '  l_blob blob;' \
    '  l_raw raw(32767);' \
    'begin' \
    '  select source_blob into l_blob from doom_mle_dvr_codec_source for update;'

  base64 <"$artifact" | tr -d '\r\n' | fold -w "$base64_fold_width" |
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
    '  l_source blob;' \
    '  l_sha varchar2(64);' \
    'begin' \
    '  select source_blob into l_source from doom_mle_dvr_codec_source;' \
    '  l_sha:=lower(rawtohex(dbms_crypto.hash(l_source,dbms_crypto.hash_sh256)));' \
    "  if dbms_lob.getlength(l_source)<>$artifact_bytes or l_sha<>'$artifact_sha256' then" \
    "    raise_application_error(-20796,'DVR codec staging mismatch expected=$artifact_bytes/$artifact_sha256 actual='||dbms_lob.getlength(l_source)||'/'||l_sha);" \
    '  end if;' \
    "  dbms_output.put_line('PMLE_DVR_CODEC_STAGING|PASS|bytes=$artifact_bytes|sha256=$artifact_sha256');" \
    'end;' \
    '/' \
    'create mle module doom_mle_dvr_codec language javascript using blob' \
    '  (select source_blob from doom_mle_dvr_codec_source);' \
    '/' \
    'declare' \
    '  l_source blob;' \
    '  l_sha varchar2(64);' \
    'begin' \
    '  select source_blob into l_source from doom_mle_dvr_codec_source;' \
    '  l_sha:=lower(rawtohex(dbms_crypto.hash(l_source,dbms_crypto.hash_sh256)));' \
    "  if dbms_lob.getlength(l_source)<>$artifact_bytes or l_sha<>'$artifact_sha256' then" \
    "    raise_application_error(-20796,'DVR codec post-create mismatch expected=$artifact_bytes/$artifact_sha256 actual='||dbms_lob.getlength(l_source)||'/'||l_sha);" \
    '  end if;' \
    "  dbms_output.put_line('PMLE_DVR_CODEC_INSTALL|PASS|module=DOOM_MLE_DVR_CODEC|codec=DOOM_DFR1_RLE|version=1|bytes=$artifact_bytes|sha256=$artifact_sha256');" \
    'end;' \
    '/' \
    'commit;'
}

if [[ "$emit_only" == 1 ]]; then
  emit_sql
  exit 0
fi

output="$(mktemp "${TMPDIR:-/tmp}/doomdb-dvr-codec-load.XXXXXX")"
trap 'rm -f "$output"' EXIT HUP INT TERM
emit_sql | "$root/scripts/db_sql.sh" - >"$output"
cat "$output"
grep -Fxq \
  "PMLE_DVR_CODEC_STAGING|PASS|bytes=$artifact_bytes|sha256=$artifact_sha256" \
  "$output"
grep -Fxq \
  "PMLE_DVR_CODEC_INSTALL|PASS|module=DOOM_MLE_DVR_CODEC|codec=DOOM_DFR1_RLE|version=1|bytes=$artifact_bytes|sha256=$artifact_sha256" \
  "$output"
printf 'PASS PMLE-DVR-CODEC-INSTALL bytes=%s sha256=%s\n' \
  "$artifact_bytes" "$artifact_sha256"
