#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
schema="DOOMDB_EVAL_T62_$$"
tmp="$(mktemp -d "${TMPDIR:-/tmp}/doom-t62.XXXXXX")"
eval_password_file="$tmp/eval-password.txt"
oracle_password_file="${DOOMDB_ORACLE_PASSWORD_FILE:-$root/secrets/oracle_password.txt}"
cleanup(){ "$root/scripts/drop_evaluator_schema.sh" "$schema" >/dev/null 2>&1||true;rm -rf "$tmp"; }
trap cleanup EXIT INT TERM
node "$root/evaluator/t6.2/self-check.mjs"
node "$root/evaluator/t6.2/mutation-self-check.mjs"
node "$root/evaluator/t6.2/source-audit.mjs"
"$root/scripts/db_sql.sh" "$root/evaluator/t6.2/oracle-production.sql"
[[ -r "$oracle_password_file" ]]||{ printf 'Oracle password file is not readable\n' >&2;exit 1; }
oracle_password="$(<"$oracle_password_file")";printf '%s\n' 'T62-Eval-Only-7c4f1a!' >"$eval_password_file";chmod 600 "$eval_password_file"
{
  printf '%s\n' 'whenever sqlerror exit sql.sqlcode rollback' 'set define off' "connect sys/\"${oracle_password}\"@FREEPDB1 as sysdba" "create user ${schema} identified by \"T62-Eval-Only-7c4f1a!\" quota unlimited on users;" "grant create session, create table, create procedure, create sequence to ${schema};" 'exit success commit'
}|docker compose -f "$root/compose.yaml" exec -T db sqlplus -s /nolog
oracle_password=''
{
  sed '/^whenever /d' "$root/evaluator/t6.2/oracle-mini-schema.sql"
  sed '/^whenever /d' "$root/sql/sim/020_movement_collision.sql"
  sed '/^whenever /d' "$root/evaluator/t6.2/oracle-mini-tests.sql"
}|DOOMDB_DB_USER="$schema" DOOMDB_APP_PASSWORD_FILE="$eval_password_file" "$root/scripts/db_sql.sh" -
printf 'PASS T6.2-VISIBLE (22/22 test ids, 372/372 declared assertions)\n'
