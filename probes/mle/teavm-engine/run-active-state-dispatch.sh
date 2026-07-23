#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
project="$root/probes/mle/teavm-engine"
artifact="$project/target/javascript/doom-mle-active-state-dispatch.js"
[[ -s "$project/target/mochadoom-mle-simulation.jar" ]] || {
  printf 'build the simulation artifact first\n' >&2;exit 2;
}
docker run --rm -v doomdb-maven-cache:/root/.m2 -v "$root:/work" \
  -w /work/probes/mle/teavm-engine maven:3.9.11-eclipse-temurin-17 \
  mvn -B -DskipTests -Pactive-state-dispatch package >/dev/null
[[ -s "$artifact" ]] || { printf 'dispatch artifact missing\n' >&2;exit 1; }
artifact_bytes="$(wc -c <"$artifact" | tr -d '[:space:]')"
artifact_sha256="$(shasum -a 256 "$artifact" | awk '{print $1}')"
base64_fold_width=2000

cleanup() {
  "$root/scripts/db_sql.sh" - >/dev/null 2>&1 <<'SQL' || true
begin execute immediate 'drop function doom_mle_dispatch_state';exception when others then null;end;
/
begin execute immediate 'drop function doom_mle_dispatch_table';exception when others then null;end;
/
begin execute immediate 'drop mle module doom_mle_dispatch';exception when others then null;end;
/
begin execute immediate 'drop mle env doom_mle_dispatch_env';exception when others then null;end;
/
begin execute immediate 'drop table doom_mle_dispatch_source purge';exception when others then null;end;
/
SQL
}
trap cleanup EXIT

{
  printf '%s\n' 'whenever oserror exit failure rollback' \
    'whenever sqlerror exit sql.sqlcode rollback' \
    'set lines 32767 trimspool on serveroutput on size unlimited' \
    'create table doom_mle_dispatch_source(source_blob blob);' \
    'insert into doom_mle_dispatch_source values(empty_blob());' \
    'declare l_blob blob;l_raw raw(32767);begin select source_blob into l_blob from doom_mle_dispatch_source for update;'
  # Keep generated SQL lines below the SQL*Plus parser boundary. A 3,000-byte
  # base64 piece placed a quote exactly on that boundary and corrupted source.
  base64 <"$artifact" | tr -d '\r\n' | fold -w "$base64_fold_width" |
    while IFS= read -r piece || [[ -n "$piece" ]]; do
    printf "l_raw:=utl_encode.base64_decode(utl_raw.cast_to_raw('%s'));dbms_lob.writeappend(l_blob,utl_raw.length(l_raw),l_raw);\n" "$piece"
  done
  printf '%s\n' 'end;' '/' \
    "declare b blob;h varchar2(64);begin select source_blob into b from doom_mle_dispatch_source;h:=lower(rawtohex(dbms_crypto.hash(b,dbms_crypto.hash_sh256)));if dbms_lob.getlength(b)<>$artifact_bytes or h<>'$artifact_sha256' then raise_application_error(-20796,'dispatch source staging mismatch');end if;dbms_output.put_line('DISPATCH_SOURCE_GATE|PASS|bytes=$artifact_bytes|sha256=$artifact_sha256');end;" '/' \
    'create mle env doom_mle_dispatch_env pure;' \
    'create mle module doom_mle_dispatch language javascript using blob (select source_blob from doom_mle_dispatch_source);' '/' \
    "create function doom_mle_dispatch_state(p_iterations number) return number as mle module doom_mle_dispatch env doom_mle_dispatch_env signature 'stateLookup(number)';" '/' \
    "create function doom_mle_dispatch_table(p_iterations number) return number as mle module doom_mle_dispatch env doom_mle_dispatch_env signature 'tableLookup(number)';" '/'
  printf '%s\n' "select name||'|'||type||'|'||line||'|'||position||'|'||text from user_errors where name in ('DOOM_MLE_DISPATCH','DOOM_MLE_DISPATCH_STATE','DOOM_MLE_DISPATCH_TABLE') order by name,sequence;"
} | "$root/scripts/db_sql.sh" -
"$root/scripts/db_sql.sh" "$project/benchmark-active-state-dispatch.sql"
