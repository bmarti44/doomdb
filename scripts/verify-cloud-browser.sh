#!/usr/bin/env bash
set -Eeuo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
policy="$root/deploy/cloud/t11.2/source-policy.json"
evidence=/tmp/doomdb-t112-evidence.json
tmp=''

not_run(){ printf 'T11.2 NOT RUN: %s\n' "$*" >&2; exit 2; }
die(){ printf 'T11.2 FAIL: %s\n' "$*" >&2; exit 1; }
sha(){ if command -v sha256sum >/dev/null 2>&1; then sha256sum "$1"|awk '{print $1}'; else shasum -a 256 "$1"|awk '{print $1}'; fi; }
cleanup(){
  local status=$?; trap - EXIT HUP INT TERM
  [[ -z "$tmp" ]] || rm -rf "$tmp"
  unset AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN AWS_REGION AWS_S3_BUCKET ADB_ORDS_BASE_URL T112_COMPLETION_LEDGER T112_S3_INDEX_URL T112_BROWSER_LEDGER
  exit "$status"
}
trap cleanup EXIT HUP INT TERM
rm -f "$evidence" /tmp/doomdb-t112-playwright.json

# Live authority is mandatory. An absent value is a nonzero NOT RUN and is never
# translated into PASS. Values stay in the environment and private temporary
# files; retained output contains hashes only.
for name in AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_REGION AWS_S3_BUCKET ADB_ORDS_BASE_URL T112_COMPLETION_LEDGER; do
  [[ -n "${!name:-}" ]] || not_run "required external authority is absent: $name"
  case "${!name,,}" in *placeholder*|*example*|*change-me*|*invalid*) not_run "$name is not a live value";; esac
done
[[ "$AWS_REGION" =~ ^[a-z]{2}(-gov)?-[a-z]+-[1-9]$ ]] || not_run 'AWS region syntax is invalid'
[[ "$AWS_S3_BUCKET" =~ ^[a-z0-9][a-z0-9.-]{1,61}[a-z0-9]$ && "$AWS_S3_BUCKET" != *..* ]] || not_run 'S3 authority syntax is invalid'
[[ "$ADB_ORDS_BASE_URL" =~ ^https://[^/?#]+/ords/[A-Za-z0-9._~-]+/?$ ]] || not_run 'managed ORDS must be an HTTPS schema root'
[[ -f "$T112_COMPLETION_LEDGER" && ! -L "$T112_COMPLETION_LEDGER" ]] || not_run 'approved completion command ledger is absent'
node - "$T112_COMPLETION_LEDGER" <<'NODE' || not_run 'completion command ledger is not approved and deterministic'
import fs from 'node:fs';import assert from 'node:assert/strict';import crypto from 'node:crypto';const p=process.argv[2],x=JSON.parse(fs.readFileSync(p));assert.equal(x.schema,1);assert.equal(x.approved,true);assert.match(x.scriptSha256,/^[0-9a-f]{64}$/);assert.ok(Array.isArray(x.commands)&&x.commands.length>0);assert.equal(new Set(x.commands.map(c=>c.seq)).size,x.commands.length);for(const c of x.commands)assert.deepEqual(Object.keys(c).sort(),['automap','cheat','fire','forward','menu','pause','run','seq','strafe','turn','use','weapon'].sort());assert.equal(crypto.createHash('sha256').update(JSON.stringify(x.commands)).digest('hex'),x.scriptSha256,'approved command hash');
NODE

for tool in node npm aws curl jq rg; do command -v "$tool" >/dev/null 2>&1 || not_run "$tool is unavailable"; done
aws_version=$(aws --version 2>&1); [[ "$aws_version" == aws-cli/2.34.36\ * ]] || not_run 'pinned AWS CLI 2.34.36 is unavailable'
playwright_version=$(node -p "require('./node_modules/@playwright/test/package.json').version")
[[ "$playwright_version" == 1.61.0 ]] || not_run 'pinned Playwright 1.61.0 is unavailable'
[[ -x "$root/node_modules/.bin/playwright" ]] || not_run 'pinned Chromium launcher is unavailable'
[[ -s /tmp/doomdb-t111-evidence.json ]] || not_run 'passing T11.1 managed ORDS evidence is absent'
node "$root/evaluator/t11.1/validate-evidence.mjs" /tmp/doomdb-t111-evidence.json >/dev/null || not_run 'T11.1 evidence is not valid'

tmp=$(mktemp -d "${TMPDIR:-/tmp}/doomdb-t112.XXXXXX"); chmod 700 "$tmp"
mkdir -p "$tmp/client-dist" "$tmp/aws"; chmod 700 "$tmp/client-dist" "$tmp/aws"
touch "$tmp/aws/redaction.scan"; chmod 600 "$tmp/aws/redaction.scan"
aws_json(){ local output=$1; shift; if ! aws "$@" --no-cli-pager >"$output" 2>"$tmp/aws/aws-error.log"; then die 'private AWS operation failed'; fi; : >"$tmp/aws/aws-error.log"; }
aws_quiet(){ if ! aws "$@" --no-cli-pager >"$tmp/aws/aws-output.log" 2>"$tmp/aws/aws-error.log"; then die 'private AWS operation failed'; fi; : >"$tmp/aws/aws-output.log"; : >"$tmp/aws/aws-error.log"; }

# Build client/dist semantics in an isolated directory. ADB_ORDS_BASE_URL is
# replaced at build/compile time; no runtime configuration or proxy is emitted.
"$root/node_modules/.bin/tsc" -p "$root/client/tsconfig.json" --noEmit false --outDir "$tmp/client-dist"
cp "$root/client/staging/index.html" "$tmp/client-dist/index.html"
node "$root/scripts/t11.2-build-client.mjs" "$root" "$tmp/client-dist" "$ADB_ORDS_BASE_URL" "$tmp/build-manifest.json" "$tmp/artifact-allowlist.txt"
chmod 600 "$tmp/build-manifest.json" "$tmp/artifact-allowlist.txt"

# Credential values may not already be retained in repository files. This is a
# value scan, not a scan for documented environment-variable names.
for secret in "$AWS_ACCESS_KEY_ID" "$AWS_SECRET_ACCESS_KEY" "${AWS_SESSION_TOKEN:-}"; do
  [[ -z "$secret" ]] && continue
  if rg -F --hidden --glob '!node_modules/**' --glob '!.git/**' -- "$secret" "$root" >/dev/null; then die 'credential value exists in repository content'; fi
done
printf 'credential-value-scan-passed\n' >"$tmp/aws/redaction.scan"

# Bind the run to live AWS and the target bucket without preserving identities.
# Equivalent pinned operations: aws sts get-caller-identity and the s3api
# location call. The wrapper confines all target-bearing diagnostics to tmp.
aws_json "$tmp/aws/identity.json" sts get-caller-identity
aws_json "$tmp/aws/location.json" s3api get-bucket-location --bucket "$AWS_S3_BUCKET"
node - "$tmp/aws/location.json" "$AWS_REGION" <<'NODE'
import fs from 'node:fs';import assert from 'node:assert/strict';const [p,want]=process.argv.slice(2),x=JSON.parse(fs.readFileSync(p)),got=x.LocationConstraint??'us-east-1';assert.equal(got,want,'bucket region differs from AWS_REGION');
NODE

# Remove every non-allowlisted key before upload. The resulting inventory must
# equal the deterministic artifact-allowlist exactly; no source maps or tools
# can remain from a prior deployment. Every object has exact Content-Type and
# Cache-Control metadata, verified again through live HEAD and GET operations.
aws_json "$tmp/aws/before.json" s3api list-objects-v2 --bucket "$AWS_S3_BUCKET"
jq -r '.Contents[]?.Key' "$tmp/aws/before.json" | while IFS= read -r key; do
  if ! grep -Fqx -- "$key" "$tmp/artifact-allowlist.txt"; then aws_quiet s3api delete-object --bucket "$AWS_S3_BUCKET" --key "$key"; fi
done
while IFS= read -r key; do
  [[ -n "$key" ]] || continue
  content_type=$(jq -r --arg key "$key" '.objects[]|select(.key==$key)|.contentType' "$tmp/build-manifest.json")
  cache_control=$(jq -r --arg key "$key" '.objects[]|select(.key==$key)|.cacheControl' "$tmp/build-manifest.json")
  digest=$(sha "$tmp/client-dist/$key")
  aws_quiet s3api put-object --bucket "$AWS_S3_BUCKET" --key "$key" --body "$tmp/client-dist/$key" --content-type "$content_type" --cache-control "$cache_control" --metadata "sha256=$digest"
done <"$tmp/artifact-allowlist.txt"
aws_json "$tmp/aws/inventory.json" s3api list-objects-v2 --bucket "$AWS_S3_BUCKET"
while IFS= read -r key; do
  [[ -n "$key" ]] || continue; safe=${key//\//__}
  aws_json "$tmp/aws/$safe.head.json" s3api head-object --bucket "$AWS_S3_BUCKET" --key "$key"
  aws_quiet s3api get-object --bucket "$AWS_S3_BUCKET" --key "$key" "$tmp/aws/$safe.get"
done <"$tmp/artifact-allowlist.txt"

export T112_S3_INDEX_URL="https://${AWS_S3_BUCKET}.s3.${AWS_REGION}.amazonaws.com/index.html"
if ! curl --proto '=https' --tlsv1.2 --fail --silent --max-redirs 0 --dump-header "$tmp/aws/index.headers" --output "$tmp/aws/index.get" "$T112_S3_INDEX_URL" 2>"$tmp/aws/curl-error.log"; then die 'explicit S3 index fetch failed'; fi
[[ "$(sha "$tmp/aws/index.get")" == "$(jq -r '.objects[]|select(.key=="index.html")|.sha256' "$tmp/build-manifest.json")" ]] || die 'explicit index.html bytes differ from build'

# The pinned playwright test uses serviceWorkers: block, workers: 1, retries: 0. It never
# fulfills routes. The real browser proves CORS OPTIONS plus NEW_GAME, STEP,
# GET_ASSET, SAVE_GAME, LOAD_GAME, START_REPLAY, STEP_REPLAY, canvas
# getImageData, AudioContext scheduling, and completion from the S3 document;
# requestfailed, pageerror, and console errors all fail the machine run.
export T112_BROWSER_LEDGER="$tmp/browser-ledger.json"
"$root/node_modules/.bin/playwright" test -c "$root/deploy/cloud/t11.2/playwright.config.ts"
[[ -s "$T112_BROWSER_LEDGER" && -s /tmp/doomdb-t112-playwright.json ]] || die 'browser ledger or machine report is absent'

candidate="$tmp/doomdb-t112-evidence.json"
node "$root/scripts/t11.2-build-evidence.mjs" "$policy" "$tmp/build-manifest.json" "$tmp/aws" "$T112_BROWSER_LEDGER" /tmp/doomdb-t112-playwright.json "$T112_S3_INDEX_URL" "$ADB_ORDS_BASE_URL" "$candidate"
node "$root/evaluator/t11.2/validate-evidence.mjs" "$candidate" >/dev/null
if rg -n -i '(aws_access|secret_access|session_token|authorization|bearer |bucket|region|account_id|password|wallet|private_key|adb_ords|https://|s3\.amazonaws|oraclecloud|game_token|session_id)' "$candidate" >/dev/null; then die 'credential or target material reached retained evidence'; fi
mv "$candidate" /tmp/doomdb-t112-evidence.json
printf 'PASS T11.2-CLOUD-BROWSER (live S3 HTTPS and managed ORDS browser evidence published)\n'
