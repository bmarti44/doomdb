#!/bin/sh
set -eu

ROOT=$(CDPATH='' cd -- "$(dirname -- "$0")/../.." && pwd)
. "$ROOT/deploy/cloud/lib.sh"

mode=dry-run
case "${1---dry-run}" in
  --dry-run) ;;
  --execute) mode=execute ;;
  *) cloud_die 'usage: s3-upload.sh [--dry-run|--execute]' ;;
esac

artifact_dir=${DOOMDB_CLIENT_ARTIFACT_DIR:-$ROOT/deploy/cloud/placeholder-client}
allowlist=$ROOT/deploy/cloud/artifact-allowlist.txt
bucket=${DOOMDB_S3_BUCKET:-doomdb-placeholder-bucket}
region=${AWS_REGION:-us-east-1}
cloud_validate_allowlist "$artifact_dir" "$allowlist"

printf '{\n  "schema": 1,\n  "operation": "s3-upload",\n  "mode": "%s",\n  "bucket": "%s",\n  "region": "%s",\n  "index_url": "https://%s.s3.%s.amazonaws.com/index.html",\n  "artifacts": [\n' "$mode" "$bucket" "$region" "$bucket" "$region"
cloud_sep=
while IFS= read -r cloud_key; do
  [ -n "$cloud_key" ] || continue
  cloud_digest=$(cloud_sha256 "$artifact_dir/$cloud_key")
  printf '%s    {"key":"%s","sha256":"%s","cache_control":"no-cache","content_type":"text/html; charset=utf-8"}' "$cloud_sep" "$cloud_key" "$cloud_digest"
  cloud_sep=',\n'
done < "$allowlist"
printf '\n  ]\n}\n'

[ "$mode" = execute ] || exit 0
cloud_check_execute_guard
cloud_require_value DOOMDB_S3_BUCKET
cloud_require_value AWS_REGION
cloud_require_value AWS_ACCESS_KEY_ID
cloud_require_value AWS_SECRET_ACCESS_KEY
aws_version=$(sed -n 's/.*"awsCli": "\([^"]*\)".*/\1/p' "$ROOT/versions.lock")
cloud_check_tool_version aws "$aws_version"
while IFS= read -r cloud_key; do
  [ -n "$cloud_key" ] || continue
  cloud_digest=$(cloud_sha256 "$artifact_dir/$cloud_key")
  aws s3api put-object \
    --bucket "$bucket" \
    --key "$cloud_key" \
    --body "$artifact_dir/$cloud_key" \
    --content-type 'text/html; charset=utf-8' \
    --cache-control 'no-cache' \
    --metadata "sha256=$cloud_digest" >/dev/null
done < "$allowlist"
