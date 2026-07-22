#!/bin/sh
set -eu

ROOT=$(CDPATH='' cd -- "$(dirname -- "$0")/../.." && pwd)
. "$ROOT/deploy/cloud/lib.sh"

mode=dry-run
case "${1---dry-run}" in
  --dry-run) ;;
  --execute) mode=execute ;;
  *) cloud_die 'usage: teardown.sh [--dry-run|--execute]' ;;
esac

bucket=${AWS_S3_BUCKET:-doomdb-placeholder-bucket}
region=${AWS_REGION:-us-east-1}
ords_base=${ADB_ORDS_BASE_URL:-https://doomdb-placeholder.adb.us-ashburn-1.oraclecloudapps.com/ords/doom}
ords_base=${ords_base%/}
printf '{\n  "schema": 1,\n  "operation": "cloud-teardown",\n  "mode": "%s",\n  "delete_s3_objects": ["index.html"],\n  "s3_index_url": "https://%s.s3.%s.amazonaws.com/index.html",\n  "drop_sql": "deploy/cloud/sql/teardown-health.sql",\n  "managed_ords_url": "%s/public_health/"\n}\n' "$mode" "$bucket" "$region" "$ords_base"

[ "$mode" = execute ] || exit 0
cloud_check_execute_guard
cloud_require_value AWS_S3_BUCKET
cloud_require_value AWS_REGION
cloud_require_value AWS_ACCESS_KEY_ID
cloud_require_value AWS_SECRET_ACCESS_KEY
cloud_require_value ADB_CONNECTION_STRING
cloud_require_value ADB_USERNAME
cloud_require_value ADB_PASSWORD
cloud_validate_adb_credentials
aws_version=$(sed -n 's/.*"awsCli": "\([^"]*\)".*/\1/p' "$ROOT/versions.lock")
sqlcl_version=$(sed -n 's/.*"sqlcl": "\([^"]*\)".*/\1/p' "$ROOT/versions.lock")
cloud_check_tool_version aws "$aws_version"
cloud_check_tool_version sql "$sqlcl_version"
aws s3api delete-object --bucket "$bucket" --key index.html >/dev/null
{
  printf 'set echo off termout off define off\n'
  printf 'connect %s/"%s"@%s\n' "$ADB_USERNAME" "$ADB_PASSWORD" "$ADB_CONNECTION_STRING"
  printf 'set termout on\n'
  printf '@%s\n' "$ROOT/deploy/cloud/sql/teardown-health.sql"
  printf 'exit\n'
} | sql /nolog | node "$ROOT/scripts/redact-cloud-output.mjs"
