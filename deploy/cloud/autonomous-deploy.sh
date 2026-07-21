#!/bin/sh
set -eu

ROOT=$(CDPATH='' cd -- "$(dirname -- "$0")/../.." && pwd)
. "$ROOT/deploy/cloud/lib.sh"

mode=dry-run
case "${1---dry-run}" in
  --dry-run) ;;
  --execute) mode=execute ;;
  *) cloud_die 'usage: autonomous-deploy.sh [--dry-run|--execute]' ;;
esac

sql_file=$ROOT/deploy/cloud/sql/health.sql
ords_base=${ADB_ORDS_BASE_URL:-https://doomdb-placeholder.adb.us-ashburn-1.oraclecloudapps.com/ords/doom}
ords_base=${ords_base%/}
sql_digest=$(cloud_sha256 "$sql_file")
printf '{\n  "schema": 1,\n  "operation": "autonomous-sql",\n  "mode": "%s",\n  "sql": [{"path":"deploy/cloud/sql/health.sql","sha256":"%s"}],\n  "managed_ords_url": "%s/public_health/"\n}\n' "$mode" "$sql_digest" "$ords_base"

[ "$mode" = execute ] || exit 0
cloud_check_execute_guard
cloud_require_value ADB_CONNECTION_STRING
cloud_require_value ADB_USERNAME
cloud_require_value ADB_PASSWORD
cloud_require_value ADB_ORDS_BASE_URL
cloud_validate_adb_credentials
sqlcl_version=$(sed -n 's/.*"sqlcl": "\([^"]*\)".*/\1/p' "$ROOT/versions.lock")
cloud_check_tool_version sql "$sqlcl_version"
{
  printf 'set echo off termout off define off\n'
  printf 'connect %s/"%s"@%s\n' "$ADB_USERNAME" "$ADB_PASSWORD" "$ADB_CONNECTION_STRING"
  printf 'set termout on\n'
  printf '@%s\n' "$sql_file"
  printf 'exit\n'
} | sql /nolog | node "$ROOT/scripts/redact-cloud-output.mjs"
