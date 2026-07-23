#!/usr/bin/env bash
set -Eeuo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tmp="$(mktemp -d "${TMPDIR:-/tmp}/doomdb-t112-source.XXXXXX")"
trap 'rm -rf "$tmp"' EXIT

bash -n "$root/scripts/verify-cloud-browser.sh"
grep -q 'DOOMDB_CLOUD_EXECUTE.*YES' "$root/scripts/verify-cloud-browser.sh"
grep -q 'without dots' "$root/scripts/verify-cloud-browser.sh"
grep -q 'Access-Control-Request-Headers.*content-type,accept' "$root/scripts/verify-cloud-browser.sh"
grep -q 'S3 was not mutated' "$root/scripts/verify-cloud-browser.sh"
grep -q "const ordsBase = ordsRoot.endsWith('/')" "$root/deploy/cloud/t11.2/cloud-browser.spec.ts"
node --check "$root/scripts/t11.2-build-client.mjs"
node --check "$root/scripts/build-t11.2-completion-ledger.mjs"
"$root/node_modules/.bin/tsc" -p "$root/client/tsconfig.json" --noEmit false --outDir "$tmp/client"
cp "$root/client/dist/play/index.html" "$tmp/client/index.html"
cp "$root/client/staging/multiplayer.html" "$tmp/client/multiplayer.html"
cp "$root/client/staging/mle.html" "$tmp/client/mle.html"
node "$root/scripts/t11.2-build-client.mjs" "$root" "$tmp/client" \
  https://example.oraclecloudapps.com/ords/doom \
  "$tmp/build.json" "$tmp/allowlist.txt"
node "$root/scripts/build-t11.2-completion-ledger.mjs" "$tmp/completion.json" >/dev/null

node - "$tmp" <<'NODE'
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
const tmp=process.argv[2],manifest=JSON.parse(fs.readFileSync(path.join(tmp,'build.json')));
const keys=fs.readFileSync(path.join(tmp,'allowlist.txt'),'utf8').trim().split('\n');
assert.equal(manifest.objects.length,keys.length);
assert.ok(keys.includes('index.html'));
assert.ok(keys.includes('multiplayer.html'));
assert.ok(keys.includes('mle.html'));
assert.equal(keys.filter(key=>/^main-[0-9a-f]{12}\.js$/.test(key)).length,1);
assert.equal(keys.filter(key=>/^multiplayer-[0-9a-f]{12}\.js$/.test(key)).length,1);
assert.ok(!keys.includes('multiplayer.js'));
const completion=JSON.parse(fs.readFileSync(path.join(tmp,'completion.json')));
assert.equal(completion.approved,true);
assert.equal(completion.commands.length,13272);
assert.equal(completion.commands.at(-1).seq,13272);
NODE

rm -f /tmp/doomdb-t112-evidence.json
set +e
env -i PATH="$PATH" HOME="${HOME:-/tmp}" \
  bash "$root/scripts/verify-cloud-browser.sh" >"$tmp/out" 2>"$tmp/err"
status=$?
set -e
[[ "$status" == 2 ]]
grep -q '^T11.2 NOT RUN:' "$tmp/err"
[[ ! -e /tmp/doomdb-t112-evidence.json ]]

set +e
env -i PATH="$PATH" HOME="${HOME:-/tmp}" DOOMDB_CLOUD_EXECUTE=YES \
  AWS_ACCESS_KEY_ID=AKIATEST AWS_SECRET_ACCESS_KEY=testsecret \
  AWS_REGION=us-east-1 AWS_S3_BUCKET=doomdb.test \
  ADB_ORDS_BASE_URL=https://cloud.oraclecloudapps.com/ords/doom \
  T112_COMPLETION_LEDGER="$tmp/completion.json" \
  bash "$root/scripts/verify-cloud-browser.sh" >"$tmp/dotted-out" 2>"$tmp/dotted-err"
status=$?
set -e
[[ "$status" == 2 ]]
grep -q 'without dots' "$tmp/dotted-err"
[[ ! -e /tmp/doomdb-t112-evidence.json ]]
printf 'PASS T11.2-SOURCE-FIRST (12-object single/multiplayer build, approved completion ledger, fail-closed authority)\n'
