#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
project="$root/probes/mle/teavm"
javascript="$project/target/javascript/doom-mle-probe.js"
expected_checksum=325244176

if [[ "${1:-}" != --no-build ]]; then
  "$project/build.sh"
fi
test -s "$javascript"
javascript_bytes="$(wc -c <"$javascript" | tr -d '[:space:]')"
javascript_sha256="$(shasum -a 256 "$javascript" | awk '{print $1}')"
base64_fold_width=2000

# CREATE MLE MODULE accepts a BLOB subquery. Loading the generated ES module
# through a temporary BLOB avoids CREATE DIRECTORY/BFILE privileges and works
# on Autonomous Database as well as the local 26ai Free container. Base64
# pieces stay below both SQL and RAW literal limits and are four-byte aligned.
emit_sql() {
  printf '%s\n' \
    'whenever oserror exit failure rollback' \
    'whenever sqlerror exit sql.sqlcode rollback' \
    'set heading off feedback off pages 0 lines 32767 trimspool on serveroutput on size unlimited' \
    "begin execute immediate 'drop function doom_teavm_checksum'; exception when others then if sqlcode <> -4043 then raise; end if; end;" \
    '/' \
    "begin execute immediate 'drop mle module doom_teavm_probe'; exception when others then if sqlcode not in (-4080,-4103) then raise; end if; end;" \
    '/' \
    "begin execute immediate 'drop table doom_teavm_source purge'; exception when others then if sqlcode <> -942 then raise; end if; end;" \
    '/' \
    'create table doom_teavm_source (module_name varchar2(30) primary key, source_blob blob not null);' \
    "insert into doom_teavm_source values ('DOOM_TEAVM_PROBE', empty_blob());" \
    'declare' \
    '  l_blob blob;' \
    '  l_raw raw(32767);' \
    'begin' \
    "  select source_blob into l_blob from doom_teavm_source where module_name='DOOM_TEAVM_PROBE' for update;"

  base64 <"$javascript" | tr -d '\r\n' | fold -w "$base64_fold_width" |
    while IFS= read -r piece || [[ -n "$piece" ]]; do
    printf "  l_raw := utl_encode.base64_decode(utl_raw.cast_to_raw('%s'));\n" "$piece"
    printf '%s\n' '  dbms_lob.writeappend(l_blob, utl_raw.length(l_raw), l_raw);'
  done

  printf '%s\n' \
    'end;' \
    '/' \
    "declare b blob;h varchar2(64);begin select source_blob into b from doom_teavm_source where module_name='DOOM_TEAVM_PROBE';h:=lower(rawtohex(dbms_crypto.hash(b,dbms_crypto.hash_sh256)));if dbms_lob.getlength(b)<>$javascript_bytes or h<>'$javascript_sha256' then raise_application_error(-20796,'TeaVM probe source staging mismatch');end if;dbms_output.put_line('PMLE_TEAVM_PROBE_STAGING_GATE|PASS|bytes=$javascript_bytes|sha256=$javascript_sha256');end;" \
    '/' \
    "create mle module doom_teavm_probe language javascript using blob (select source_blob from doom_teavm_source where module_name='DOOM_TEAVM_PROBE');" \
    '/' \
    "create function doom_teavm_checksum return number as mle module doom_teavm_probe signature 'tablesChecksum()';" \
    '/' \
    'drop table doom_teavm_source purge;' \
    "select 'PMLE_TEAVM_MLE|checksum=' || doom_teavm_checksum from dual;"
}

output="$(mktemp "${TMPDIR:-/tmp}/doomdb-teavm-deploy.XXXXXX")"
trap 'rm -f "$output"' EXIT HUP INT TERM
emit_sql | "$root/scripts/db_sql.sh" - >"$output"
cat "$output"
grep -q "^PMLE_TEAVM_MLE|checksum=$expected_checksum$" "$output"
printf 'PASS PMLE-TEAVM-MLE checksum=%s\n' "$expected_checksum"
