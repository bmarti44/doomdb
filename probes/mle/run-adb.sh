#!/usr/bin/env bash
set -Eeuo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
die(){ printf 'PMLE ADB NOT RUN: %s\n' "$*" >&2;exit 1; }
[[ "${DOOMDB_CLOUD_EXECUTE:-}" == YES ]] || die 'DOOMDB_CLOUD_EXECUTE=YES is required'
for name in ADB_CONNECTION_STRING ADB_USERNAME ADB_PASSWORD ADB_WALLET_DIR;do
  [[ -n "${!name:-}" ]]||die "required environment variable is absent: $name"
done
[[ "$ADB_USERNAME" =~ ^[A-Za-z][A-Za-z0-9_\$#]{0,127}$ ]]||die 'unsafe ADB username'
[[ "$ADB_CONNECTION_STRING" =~ ^[A-Za-z0-9._:/?=@-]+$ ]]||die 'unsafe connection identifier'
[[ "$ADB_PASSWORD" != *'"'* && "$ADB_PASSWORD" != *$'\n'* && "$ADB_PASSWORD" != *$'\r'* ]]||die 'password cannot be represented safely'
[[ -d "$ADB_WALLET_DIR" && ! -L "$ADB_WALLET_DIR" ]]||die 'wallet directory is invalid'
command -v sql >/dev/null||die 'Oracle SQLcl is required'
command -v timeout >/dev/null||die 'timeout is required'
export TNS_ADMIN="$ADB_WALLET_DIR"

run_sql(){
  local file=$1
  {
    printf '%s\n' 'whenever oserror exit failure rollback' 'whenever sqlerror exit sql.sqlcode rollback'
    printf 'connect %s/"%s"@%s\n' "$ADB_USERNAME" "$ADB_PASSWORD" "$ADB_CONNECTION_STRING"
    command cat "$file"
    printf '%s\n' 'exit success commit'
  }|timeout 900 sql -s /nolog|node "$root/scripts/redact-cloud-output.mjs"
}
cleanup(){ local rc=$?;trap - EXIT HUP INT TERM;run_sql "$root/probes/mle/adb-cleanup.sql" >/dev/null||rc=1;unset ADB_PASSWORD;exit "$rc"; }
trap cleanup EXIT HUP INT TERM
run_sql "$root/probes/mle/adb-install.sql" >/dev/null
run_sql "$root/probes/mle/adb-benchmark.sql"
