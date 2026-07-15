#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
password_file="${DOOMDB_ORACLE_PASSWORD_FILE:-$root/secrets/oracle_password.txt}"

if [[ $# -ne 1 || ! "$1" =~ ^DOOMDB_EVAL(_[A-Z0-9_]+)?$ ]]; then
  printf 'refusing to drop schema outside DOOMDB_EVAL[_SUFFIX]\n' >&2
  exit 2
fi
schema="$1"
if [[ ! -r "$password_file" ]]; then
  printf 'Oracle password file is not readable: %s\n' "$password_file" >&2
  exit 2
fi
password="$(<"$password_file")"
if [[ -z "$password" || "$password" == *$'\n'* || "$password" == *'"'* ]]; then
  printf 'Oracle password file contains an unsupported value\n' >&2
  exit 2
fi

{
  printf '%s\n' \
    'whenever oserror exit failure rollback' \
    'whenever sqlerror exit sql.sqlcode rollback' \
    'set define off echo off verify off' \
    "connect sys/\"${password}\"@FREEPDB1 as sysdba" \
    "declare n number; begin select count(*) into n from dba_users where username = '${schema}'; if n = 1 then execute immediate 'drop user ${schema} cascade'; end if; end;" \
    '/' \
    'exit success commit'
} | docker compose -f "$root/compose.yaml" exec -T db sqlplus -s /nolog
password=''
