#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
password_file="${DOOMDB_APP_PASSWORD_FILE:-$root/secrets/doom_password.txt}"
db_user="${DOOMDB_DB_USER:-DOOM}"
db_service="${DOOMDB_DB_SERVICE:-FREEPDB1}"
compose_service="${DOOMDB_DB_COMPOSE_SERVICE:-db}"

if [[ $# -gt 1 ]]; then
  printf 'usage: %s [sql-file|-]\n' "$0" >&2
  exit 2
fi
input="${1:--}"
if [[ "$input" != - && ! -f "$input" ]]; then
  printf 'SQL file not found: %s\n' "$input" >&2
  exit 2
fi
if [[ ! "$db_user" =~ ^[A-Z][A-Z0-9_]{0,29}$ ]]; then
  printf 'invalid database user name\n' >&2
  exit 2
fi
if [[ ! "$db_service" =~ ^[A-Za-z0-9._-]+$ ]]; then
  printf 'invalid database service name\n' >&2
  exit 2
fi
if [[ ! -r "$password_file" ]]; then
  printf 'database password file is not readable: %s\n' "$password_file" >&2
  exit 2
fi

password="$(<"$password_file")"
if [[ -z "$password" || "$password" == *$'\n'* || "$password" == *'"'* ]]; then
  printf 'database password file contains an unsupported value\n' >&2
  exit 2
fi

emit_sql() {
  printf '%s\n' \
    'whenever oserror exit failure rollback' \
    'whenever sqlerror exit sql.sqlcode rollback' \
    'set define off echo off verify off' \
    "connect ${db_user}/\"${password}\"@${db_service}" \
    "alter session set nls_numeric_characters = '.,';" \
    "alter session set nls_territory = 'AMERICA';" \
    "alter session set nls_language = 'AMERICAN';" \
    "alter session set time_zone = 'UTC';"
  if [[ "$input" == - ]]; then
    cat
  else
    cat "$input"
  fi
  printf '%s\n' 'exit success commit'
}

emit_sql | docker compose -f "$root/compose.yaml" exec -T "$compose_service" sqlplus -s /nolog
password=''
