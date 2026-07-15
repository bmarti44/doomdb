#!/usr/bin/env bash
set -Eeuo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
password_file="${DOOMDB_APP_PASSWORD_FILE:-/run/secrets/doom_password}"
db_user="${DOOMDB_DB_USER:-DOOM}"
db_host="${DOOMDB_DB_HOST:-db}"
db_port="${DOOMDB_DB_PORT:-1521}"
db_service="${DOOMDB_DB_SERVICE:-FREEPDB1}"

if [[ $# -gt 1 ]]; then
  printf 'usage: %s [sql-file|-]\n' "$0" >&2
  exit 2
fi
input="${1:--}"
[[ "$input" == - || -f "$input" ]] || { printf 'SQL file not found: %s\n' "$input" >&2; exit 2; }
[[ "$db_user" =~ ^[A-Z][A-Z0-9_]{0,29}$ ]] || { printf 'invalid database user name\n' >&2; exit 2; }
[[ "$db_host" =~ ^[A-Za-z0-9.-]+$ ]] || { printf 'invalid database host name\n' >&2; exit 2; }
[[ "$db_port" =~ ^[0-9]{1,5}$ ]] || { printf 'invalid database port\n' >&2; exit 2; }
[[ "$db_service" =~ ^[A-Za-z0-9._-]+$ ]] || { printf 'invalid database service name\n' >&2; exit 2; }
[[ -r "$password_file" ]] || { printf 'database password file is not readable\n' >&2; exit 2; }

password="$(<"$password_file")"
[[ -n "$password" && "$password" != *$'\n'* && "$password" != *'"'* ]] || {
  printf 'database password file contains an unsupported value\n' >&2
  exit 2
}

emit_sql() {
  printf '%s\n' \
    'whenever oserror exit failure rollback' \
    'whenever sqlerror exit sql.sqlcode rollback' \
    'set define off echo off verify off' \
    "connect ${db_user}/\"${password}\"@//${db_host}:${db_port}/${db_service}" \
    "alter session set nls_numeric_characters = '.,';" \
    "alter session set nls_territory = 'AMERICA';" \
    "alter session set nls_language = 'AMERICAN';" \
    "alter session set time_zone = 'UTC';"
  if [[ "$input" == - ]]; then cat; else cat "$input"; fi
  printf '%s\n' 'exit success commit'
}

emit_sql | sqlplus -s /nolog
password=''
