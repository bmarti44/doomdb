#!/usr/bin/env bash
set -Eeuo pipefail

# A fresh config volume requires the wrapper to replace Oracle Free's bundled
# ORDS repository. That supported uninstall/reinstall also removes REST-enabled
# object metadata, so publish the application only after the vendor entrypoint
# has completed the repository installation.
password_file=${DOOMDB_APP_PASSWORD_FILE:-/run/secrets/doom_password}
[[ -r "${password_file}" ]] || {
  printf '%s\n' 'ERROR: Doom application password secret is not readable.' >&2
  exit 1
}
password=$(tr -d '\r\n' < "${password_file}")
[[ -n "${password}" && "${password}" != *'"'* ]] || {
  printf '%s\n' 'ERROR: Doom application password secret has an unsupported value.' >&2
  exit 1
}

{
  printf '%s\n' \
    'whenever oserror exit failure rollback' \
    'whenever sqlerror exit sql.sqlcode rollback' \
    'set define off echo off verify off' \
    "connect DOOM/\"${password}\"@//${DBHOST}:${DBPORT}/${DBSERVICENAME}"
  cat /doomdb/020_ords_enable.sql
  printf '%s\n' 'exit success commit'
} | sql -s /nolog

password=''
