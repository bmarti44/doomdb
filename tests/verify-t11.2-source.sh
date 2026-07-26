#!/usr/bin/env bash
set -Eeuo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tmp="$(mktemp -d "${TMPDIR:-/tmp}/doomdb-t112-source.XXXXXX")"
trap 'rm -rf "$tmp"' EXIT

bash -n "$root/scripts/verify-cloud-browser.sh"
bash -n "$root/scripts/load-hosted-statics.sh"
node "$root/tests/verify-t11.2-drop-inventory.mjs"
grep -q 'DOOMDB_CLOUD_EXECUTE.*YES' "$root/scripts/verify-cloud-browser.sh"
grep -q 'doomdb-t112-failure' "$root/scripts/verify-cloud-browser.sh"
grep -q 'OCI_AUTONOMOUS_DATABASE_HOSTED_ORDS' \
  "$root/scripts/t11.2-build-hosted-evidence.mjs"
grep -q 'database_asset_load' "$root/scripts/verify-cloud-browser.sh"
grep -q 'browser_30fps' "$root/scripts/verify-cloud-browser.sh"
! grep -q 'package-browser-assets.sh' "$root/scripts/verify-cloud-browser.sh"
grep -q '5ec18cbe4cff7192d384e81d1010e0133d357d44ff17fa65821e1489c4fd1ee3' \
  "$root/scripts/verify-cloud-browser.sh"
grep -q 'e55d5f1138fa94d4fc7efd0acf27cbc89cb8a894e3d6828d84837a364b4426dc' \
  "$root/scripts/verify-cloud-browser.sh"
grep -q "appUrl.pathname.*ords" "$root/deploy/cloud/t11.2/cloud-browser.spec.ts"
grep -q 'test.afterEach' "$root/deploy/cloud/t11.2/cloud-browser.spec.ts"
[[ "$(grep -c 'T112_MOVING_INPUT_EFFECTIVE_FENCE' \
  "$root/deploy/cloud/t11.2/cloud-browser.spec.ts")" == 2 ]]
grep -q 'await releaseMatch(page)' \
  "$root/deploy/cloud/t11.2/cloud-browser.spec.ts"
T112_HOSTED_INDEX_URL=https://example.oraclecloudapps.com/ords/doom/app/ \
T112_BROWSER_LEDGER="$tmp/browser-ledger.json" \
  "$root/node_modules/.bin/playwright" test \
    -c "$root/deploy/cloud/t11.2/playwright.config.ts" --list \
    >"$tmp/playwright-list.log"
grep -q 'Total: 1 test in 1 file' "$tmp/playwright-list.log"
node --check "$root/scripts/t11.2-build-client.mjs"
node --check "$root/scripts/t11.2-verify-database-inventory.mjs"
grep -q "normalizeDbOutput(catalogRaw)" \
  "$root/scripts/t11.2-verify-database-inventory.mjs"
node --check "$root/scripts/t11.2-verify-live-headers.mjs"
grep -q 'normalizeContentType' \
  "$root/scripts/t11.2-verify-live-headers.mjs"
printf '%s\r\n' 'HTTP/1.1 200 OK' \
  'Content-Type: text/plain;charset=utf-8' \
  'ETag: "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"' \
  'Cache-Control: no-cache, must-revalidate' '' \
  >"$tmp/semantic-headers.txt"
node "$root/scripts/t11.2-verify-live-headers.mjs" \
  "$tmp/semantic-headers.txt" 'text/plain; charset=utf-8' \
  'no-cache, must-revalidate' \
  0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef \
  >"$tmp/semantic-headers.json"
node --check "$root/scripts/t11.2-verify-not-modified.mjs"
printf '%s\r\n' 'HTTP/1.1 304 Not Modified' \
  'Cache-Control: public, max-age=31536000, immutable' \
  'ETag: "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"' \
  '' >"$tmp/not-modified-headers.txt"
: >"$tmp/not-modified-body"
node "$root/scripts/t11.2-verify-not-modified.mjs" \
  "$tmp/not-modified-headers.txt" "$tmp/not-modified-body" \
  'public, max-age=31536000, immutable' \
  0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef \
  >"$tmp/not-modified.json"
grep -v '^Cache-Control:' "$tmp/not-modified-headers.txt" \
  >"$tmp/not-modified-no-cache-header.txt"
node "$root/scripts/t11.2-verify-not-modified.mjs" \
  "$tmp/not-modified-no-cache-header.txt" "$tmp/not-modified-body" \
  'public, max-age=31536000, immutable' \
  0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef \
  >"$tmp/not-modified-no-cache-header.json"
node --check "$root/scripts/t11.2-build-hosted-evidence.mjs"
grep -q "dbms_output.put_line('T112_ENABLED|'||trim(r.parsing_object)" \
  "$root/scripts/verify-cloud-browser.sh"
grep -q 'trimout on trimspool on' "$root/scripts/verify-cloud-browser.sh"
"${JAVA_HOME:-/usr/local/opt/openjdk@21/libexec/openjdk.jdk/Contents/Home}/bin/javac" \
  --release 11 -d "$tmp/java" "$root/tools/cloud/DoomHostedStaticLoader.java"
grep -q "p_module_name=>'doom.hosted.app'" \
  "$root/deploy/cloud/t11.2/install-hosted-statics.sql"
grep -q "p_base_path=>'/app/'" \
  "$root/deploy/cloud/t11.2/install-hosted-statics.sql"
grep -q 'p_source_type=>ords.source_type_plsql' \
  "$root/deploy/cloud/t11.2/install-hosted-statics.sql"
! grep -q 'p_source_type=>ords.source_type_media' \
  "$root/deploy/cloud/t11.2/install-hosted-statics.sql"
grep -q "p_name=>'If-None-Match'" \
  "$root/deploy/cloud/t11.2/install-hosted-statics.sql"
! grep -q "p_etag_type" \
  "$root/deploy/cloud/t11.2/install-hosted-statics.sql"
grep -q "p_name=>'Cache-Control'" \
  "$root/deploy/cloud/t11.2/install-hosted-statics.sql"
grep -q "p_bind_variable_name=>'cache_control_header'" \
  "$root/deploy/cloud/t11.2/install-hosted-statics.sql"
grep -q "p_access_method=>'OUT'" \
  "$root/deploy/cloud/t11.2/install-hosted-statics.sql"
grep -q ':cache_control_header:=l_cache_control' \
  "$root/deploy/cloud/t11.2/install-hosted-statics.sql"
grep -q "wpg_docload.download_file(l_payload)" \
  "$root/deploy/cloud/t11.2/install-hosted-statics.sql"
grep -q 'dbms_crypto.hash(payload' \
  "$root/tools/cloud/DoomHostedStaticLoader.java"
grep -q 'redact-cloud-output.mjs.*load.log' \
  "$root/scripts/load-hosted-statics.sh"
"$root/node_modules/.bin/tsc" -p "$root/client/tsconfig.json" --noEmit false --outDir "$tmp/client"
cp "$root/client/dist/play/index.html" "$tmp/client/index.html"
cp "$root/client/staging/multiplayer.html" "$tmp/client/multiplayer.html"
cp "$root/client/staging/solo.html" "$tmp/client/solo.html"
cp "$root/client/dist/play/doom-mle-authority-5ec18cbe4cff.js" "$tmp/client/"
cp "$root/client/dist/play/doom-mle-presentation-e55d5f1138fa.js" "$tmp/client/"
cp "$root/client/dist/play/canonical-runtime-v2-058cd0df9444.bin" "$tmp/client/"
cp "$root/client/dist/play/freedoom1-7323bcc168c5.bin" "$tmp/client/"
cp "$root/vendor/freedoom/0.13.0/COPYING.txt" \
  "$tmp/client/COPYING-freedoom.txt"
cp "$root/deploy/cloud/t11.2/SOURCE.txt" "$tmp/client/SOURCE.txt"
node "$root/scripts/t11.2-build-client.mjs" "$root" "$tmp/client" \
  https://example.oraclecloudapps.com/ords/doom \
  "$tmp/build.json" "$tmp/allowlist.txt" "$tmp/loader.tsv"
node - "$tmp" <<'NODE'
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
const tmp=process.argv[2],manifest=JSON.parse(fs.readFileSync(path.join(tmp,'build.json')));
const keys=fs.readFileSync(path.join(tmp,'allowlist.txt'),'utf8').trim().split('\n');
const loader=fs.readFileSync(path.join(tmp,'loader.tsv'),'utf8').trim().split('\n');
assert.equal(manifest.objects.length,keys.length);
assert.equal(keys.length,24);
assert.equal(loader.length,keys.length+1);
assert.ok(keys.includes('index.html'));
assert.ok(keys.includes('multiplayer.html'));
assert.ok(keys.includes('solo.html'));
assert.equal(keys.filter(key=>/^main-[0-9a-f]{12}\.js$/.test(key)).length,1);
assert.equal(keys.filter(key=>/^multiplayer-[0-9a-f]{12}\.js$/.test(key)).length,1);
assert.ok(!keys.includes('multiplayer.js'));
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

mkdir "$tmp/wallet"
set +e
env -i PATH="$PATH" HOME="${HOME:-/tmp}" DOOMDB_CLOUD_EXECUTE=YES \
  ADB_CONNECTION_STRING=doomdb_tp ADB_USERNAME=NOT_DOOM ADB_PASSWORD=test \
  ADB_WALLET_DIR="$tmp/wallet" SQL_CLIENT=/bin/false \
  ADB_ORDS_BASE_URL=https://cloud.oraclecloudapps.com/ords/doom \
  bash "$root/scripts/verify-cloud-browser.sh" >"$tmp/schema-out" 2>"$tmp/schema-err"
status=$?
set -e
[[ "$status" == 2 ]]
grep -q 'schema must be DOOM' "$tmp/schema-err"
[[ ! -e /tmp/doomdb-t112-evidence.json ]]

T112_REQUIRE_PRODUCTION=1 node "$root/evaluator/t11.2/source-audit.mjs"
node "$root/evaluator/t11.2/self-check.mjs"
node "$root/evaluator/t11.2/mutation-self-check.mjs"
printf 'PASS T11.2-SOURCE-FIRST (24-object single/multiplayer build, licenses present, fail-closed authority)\n'
