#!/usr/bin/env bash
set -Eeuo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
input="${1:--}"

[[ "$#" -le 1 ]] || {
  printf 'usage: %s [sql-file|-]\n' "$0" >&2; exit 2; }
[[ "$input" == - || -f "$input" && ! -L "$input" ]] || {
  printf 'SQL input is unavailable\n' >&2; exit 2; }
for name in ADB_CONNECTION_STRING ADB_ADMIN_USERNAME ADB_ADMIN_PASSWORD \
  ADB_WALLET_DIR SQL_CLIENT; do
  [[ -n "${!name:-}" ]] || {
    printf 'required cloud admin SQL authority is absent: %s\n' "$name" >&2
    exit 2
  }
done
[[ "$ADB_ADMIN_USERNAME" =~ ^[A-Z][A-Z0-9_$#]{0,127}$ ]] || {
  printf 'ADB admin username is invalid\n' >&2; exit 2; }
[[ "$ADB_ADMIN_PASSWORD" != *'"'* && "$ADB_ADMIN_PASSWORD" != *$'\n'* \
    && "$ADB_ADMIN_PASSWORD" != *$'\r'* ]] || {
  printf 'ADB admin password cannot be represented safely\n' >&2; exit 2; }
[[ "$ADB_CONNECTION_STRING" =~ ^[A-Za-z0-9._:/?=@-]+$ ]] || {
  printf 'ADB connection identifier is invalid\n' >&2; exit 2; }
[[ -d "$ADB_WALLET_DIR" && ! -L "$ADB_WALLET_DIR" ]] || {
  printf 'ADB wallet directory is invalid\n' >&2; exit 2; }
[[ -x "$SQL_CLIENT" ]] || {
  printf 'pinned SQL client is unavailable\n' >&2; exit 2; }

export TNS_ADMIN="$ADB_WALLET_DIR"
{
  printf '%s\n' \
    'whenever oserror exit failure rollback' \
    'whenever sqlerror exit sql.sqlcode rollback' \
    'set define off echo off verify off' \
    "connect ${ADB_ADMIN_USERNAME}/\"${ADB_ADMIN_PASSWORD}\"@${ADB_CONNECTION_STRING}" \
    "alter session set nls_numeric_characters = '.,';" \
    "alter session set nls_territory = 'AMERICA';" \
    "alter session set nls_language = 'AMERICAN';" \
    "alter session set time_zone = 'UTC';"
  if [[ "$input" == - ]]; then command cat; else command cat "$input"; fi
  printf '%s\n' 'exit success commit'
} | "$SQL_CLIENT" -s /nolog
