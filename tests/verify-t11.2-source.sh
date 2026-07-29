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
grep -q 'runtime_postflight' "$root/scripts/verify-cloud-browser.sh"
grep -q 't11.2-verify-runtime-postflight.mjs' \
  "$root/scripts/verify-cloud-browser.sh"
grep -q "new URL('../versions.lock',import.meta.url)" \
  "$root/scripts/t11.2-build-hosted-evidence.mjs"
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
node --check "$root/scripts/t11.2-verify-runtime-postflight.mjs"
cat >"$tmp/runtime-postflight.log" <<'EOF'
T112_RUNTIME|match_sha256=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa|authority_sha256=66dd235cde82a8b8fbcac88bb905912bacfd6ea40671d2808e5951ce290ce873|renderer_sha256=c60a34dd81d6e184be7262f494ff3070adb1ab2fb926ecaafedc4043b22cf93c|coordinator_sha256=59acb671e6e0a03ee89735806c8f0178a53dc792d22b87fb2c22db5f226fdd85|current_tic=300|checkpoint_count=0|checkpoint_unmeasured_count=0|checkpoint_slow_count=0|checkpoint_max_step_ms=0|checkpoint_max_save_ms=0|checkpoint_max_publish_ms=0|checkpoint_max_stage_ms=0
EOF
node "$root/scripts/t11.2-verify-runtime-postflight.mjs" \
  "$tmp/runtime-postflight.log" \
  aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa \
  1 300 "$root/versions.lock" "$tmp/runtime-postflight.json"
node -e "const r=require('$tmp/runtime-postflight.json');if(r.result!=='PASS'||r.checkpointCount!==0)process.exit(1)"
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
grep -q "database-generated framebuffer client" \
  "$root/deploy/cloud/t11.2/cloud-browser.spec.ts"
grep -q "operations).toContain('EXCHANGE_MATCH_PIXEL_BATCH')" \
  "$root/deploy/cloud/t11.2/cloud-browser.spec.ts"
grep -q 'selectedDepths.every(value=>value===6)' \
  "$root/deploy/cloud/t11.2/cloud-browser.spec.ts"
grep -q "operations).not.toContain('POLL_MATCH_TRANSITIONS')" \
  "$root/deploy/cloud/t11.2/cloud-browser.spec.ts"
grep -q 'expect(verifiedBlobModuleLoads).toBe(0)' \
  "$root/deploy/cloud/t11.2/cloud-browser.spec.ts"
grep -q "frame.source==='database-framebuffer'" \
  "$root/deploy/cloud/t11.2/cloud-browser.spec.ts"
grep -Fq 'expect(p99).toBeLessThanOrEqual(2*1000/35)' \
  "$root/deploy/cloud/t11.2/cloud-browser.spec.ts"
grep -Fq 'expect(maximumInterval).toBeLessThanOrEqual(100)' \
  "$root/deploy/cloud/t11.2/cloud-browser.spec.ts"
grep -Fq 'expect(pixelPollsPerScoredFrame).toBeLessThanOrEqual(2.5)' \
  "$root/deploy/cloud/t11.2/cloud-browser.spec.ts"
grep -Fq 'bufferOccupancyMin:bufferedFrames[0]' \
  "$root/deploy/cloud/t11.2/cloud-browser.spec.ts"
grep -Fq 'selectedDepthMax:Math.max(...selectedDepths)' \
  "$root/deploy/cloud/t11.2/cloud-browser.spec.ts"
grep -Fq "['doom:multiplayer-pixel-starvation','pixel-starvation']" \
  "$root/deploy/cloud/t11.2/cloud-browser.spec.ts"
grep -Fq 'const scoredNetworkStart=network.length' \
  "$root/deploy/cloud/t11.2/cloud-browser.spec.ts"
grep -Fq 'Number(row.detail.bufferedFrames)>=' \
  "$root/deploy/cloud/t11.2/cloud-browser.spec.ts"
grep -Fq "row.name==='pixel-starvation'||row.name==='pixel-resync'" \
  "$root/deploy/cloud/t11.2/cloud-browser.spec.ts"
grep -q "checkpointTimingSource:'EXACT_STAGE_PLUS_SPARSE_GT_100MS_TOTAL'" \
  "$root/scripts/t11.2-verify-runtime-postflight.mjs"
grep -Fq 'greatest(cp.save_elapsed_ms,cp.publish_elapsed_ms)>250' \
  "$root/scripts/verify-cloud-browser.sh"
! grep -Eq 'doom-mle-(authority|presentation)|canonical-runtime|freedoom1-[0-9a-f]' \
  "$root/scripts/verify-cloud-browser.sh"
grep -Fq "'authority.js','authority-batch.js','authority-mirror.js','teavm-browser.js'" \
  "$root/scripts/t11.2-build-client.mjs"
grep -q 'dbms_crypto.hash(payload' \
  "$root/tools/cloud/DoomHostedStaticLoader.java"
grep -q 'redact-cloud-output.mjs.*load.log' \
  "$root/scripts/load-hosted-statics.sh"
"$root/node_modules/.bin/tsc" -p "$root/client/tsconfig.json" --noEmit false --outDir "$tmp/client"
cp "$root/client/dist/play/index.html" "$tmp/client/index.html"
cp "$root/client/staging/multiplayer.html" "$tmp/client/multiplayer.html"
cp "$root/client/staging/solo.html" "$tmp/client/solo.html"
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
assert.equal(keys.length,17);
assert.equal(loader.length,keys.length+1);
assert.ok(keys.includes('index.html'));
assert.ok(keys.includes('multiplayer.html'));
assert.ok(keys.includes('solo.html'));
assert.equal(keys.filter(key=>/^main-[0-9a-f]{12}\.js$/.test(key)).length,1);
assert.equal(keys.filter(key=>/^multiplayer-[0-9a-f]{12}\.js$/.test(key)).length,1);
assert.ok(!keys.includes('multiplayer.js'));
assert.ok(!keys.some(key=>/^doom-mle-(?:authority|presentation)-/.test(key)));
assert.ok(!keys.some(key=>/^(?:canonical-runtime|freedoom1)-/.test(key)));
for(const diagnosticOnly of [
  'authority.js','authority-batch.js','authority-mirror.js','teavm-browser.js'
]) assert.ok(!keys.includes(diagnosticOnly));
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
printf 'PASS T11.2-SOURCE-FIRST (17-object DB-pixel build, licenses present, fail-closed runtime)\n'
