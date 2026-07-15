#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
schema="DOOMDB_EVAL_T32_$$"
tmp="$(mktemp -d "${TMPDIR:-/tmp}/doom-t32.XXXXXX")"
eval_password_file="$tmp/eval-password.txt"
oracle_password_file="${DOOMDB_ORACLE_PASSWORD_FILE:-$root/secrets/oracle_password.txt}"

cleanup() {
  "$root/scripts/drop_evaluator_schema.sh" "$schema" >/dev/null 2>&1 || true
  rm -rf "$tmp"
}
trap cleanup EXIT INT TERM

[[ -r "$oracle_password_file" ]] || { printf 'Oracle password file is not readable\n' >&2; exit 1; }
oracle_password="$(<"$oracle_password_file")"
[[ -n "$oracle_password" && "$oracle_password" != *$'\n'* && "$oracle_password" != *'"'* ]] || {
  printf 'Oracle password file contains an unsupported value\n' >&2; exit 1;
}
printf '%s\n' 'T32-Eval-Only-9f7a3c!' > "$eval_password_file"
chmod 600 "$eval_password_file"

node "$root/evaluator/t3.2/source-audit.mjs"
"$root/scripts/db_sql.sh" "$root/evaluator/t3.2/oracle-production.sql"

{
  printf '%s\n' \
    'whenever oserror exit failure rollback' \
    'whenever sqlerror exit sql.sqlcode rollback' \
    'set define off echo off verify off' \
    "connect sys/\"${oracle_password}\"@FREEPDB1 as sysdba" \
    "create user ${schema} identified by \"T32-Eval-Only-9f7a3c!\" quota unlimited on users;" \
    "grant create session, create table, create sequence to ${schema};" \
    'exit success commit'
} | docker compose -f "$root/compose.yaml" exec -T db sqlplus -s /nolog
oracle_password=''

DOOMDB_DB_USER="$schema" DOOMDB_APP_PASSWORD_FILE="$eval_password_file" \
  "$root/scripts/db_sql.sh" "$root/evaluator/t3.2/oracle-mini-map.sql"

printf 'PASS T3.2 (136/136 assertions)\n'
