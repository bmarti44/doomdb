#!/bin/sh
set -eu

ROOT=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
cd "$ROOT"
tmp=${TMPDIR:-/tmp}/doomdb-cloud-test.$$
trap 'rm -rf "$tmp"' EXIT HUP INT TERM
mkdir -p "$tmp/artifacts"

fail() { printf 'verify cloud skeleton: %s\n' "$*" >&2; exit 1; }
assertions=0
pass() { assertions=$((assertions + 1)); }

deploy/cloud/s3-upload.sh > "$tmp/s3-a.json"
deploy/cloud/s3-upload.sh > "$tmp/s3-b.json"
cmp -s "$tmp/s3-a.json" "$tmp/s3-b.json" || fail 'S3 manifest is not deterministic'
cmp -s deploy/cloud/manifests/s3-upload.json "$tmp/s3-a.json" || fail 'S3 manifest differs from checked-in output'
pass
deploy/cloud/autonomous-deploy.sh > "$tmp/adb-a.json"
deploy/cloud/autonomous-deploy.sh > "$tmp/adb-b.json"
cmp -s "$tmp/adb-a.json" "$tmp/adb-b.json" || fail 'Autonomous manifest is not deterministic'
cmp -s deploy/cloud/manifests/autonomous-sql.json "$tmp/adb-a.json" || fail 'Autonomous manifest differs from checked-in output'
pass
deploy/cloud/teardown.sh > "$tmp/teardown.json"
cmp -s deploy/cloud/manifests/teardown.json "$tmp/teardown.json" || fail 'teardown manifest differs from checked-in output'
for manifest in "$tmp/s3-a.json" "$tmp/adb-a.json" "$tmp/teardown.json"; do
  jq -e '.schema == 1 and .mode == "dry-run"' "$manifest" >/dev/null || fail "invalid dry-run manifest: $manifest"
done
pass
jq -e '.artifacts | length == 1 and .[0].key == "index.html"' "$tmp/s3-a.json" >/dev/null || fail 'artifact manifest differs from allowlist'
pass
jq -e '.index_url | test("^https://[^/]+\\.s3\\.[^/]+\\.amazonaws\\.com/index\\.html$")' "$tmp/s3-a.json" >/dev/null || fail 'explicit S3 HTTPS URL absent'
pass
jq -e '.sql | length == 1 and .[0].path == "deploy/cloud/sql/health.sql"' "$tmp/adb-a.json" >/dev/null || fail 'Autonomous manifest contains unexpected SQL'
pass
jq -e '.managed_ords_url | test("^https://.+/ords/doom/public_health/$")' "$tmp/adb-a.json" >/dev/null || fail 'managed ORDS URL absent'
pass
node scripts/redact-cloud-output.mjs < tests/fixtures/cloud-secrets.in > "$tmp/redacted"
cmp -s tests/fixtures/cloud-secrets.expected "$tmp/redacted" || fail 'secret fixture did not redact exactly'
pass
cp deploy/cloud/placeholder-client/index.html "$tmp/artifacts/index.html"
printf 'not allowlisted\n' > "$tmp/artifacts/debug.txt"
if DOOMDB_CLIENT_ARTIFACT_DIR="$tmp/artifacts" deploy/cloud/s3-upload.sh > /dev/null 2>&1; then
  fail 'extra artifact was accepted'
fi
pass
if deploy/cloud/s3-upload.sh --execute > /dev/null 2>&1; then
  fail 'execute mode was accepted without explicit guard'
fi
pass
for script in deploy/cloud/s3-upload.sh deploy/cloud/autonomous-deploy.sh deploy/cloud/teardown.sh; do
  grep -q 'cloud_check_execute_guard' "$script" || fail "$script lacks explicit execution guard"
done
grep -q 'DOOMDB_CLOUD_EXECUTE' deploy/cloud/lib.sh || fail 'shared execution guard is absent'
pass
[ "$(grep -c '^index.html$' deploy/cloud/artifact-allowlist.txt)" -eq 1 ] || fail 'allowlist is not exact'
pass

printf 'PASS T1.3 (%s/%s assertions)\n' "$assertions" "$assertions"
