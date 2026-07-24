#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tmp="$(mktemp -d "${TMPDIR:-/tmp}/doomdb-t111-source.XXXXXX")";trap 'rm -rf "$tmp"' EXIT

bash -n "$root/scripts/verify-cloud-database.sh"
bash -n "$root/scripts/load-cloud-assets.sh" \
  "$root/probes/mle/teavm-engine/load-mle-module.sh"
for marker in production-order.txt load-cloud-assets.sh \
  'load-mle-module.sh.*--production' deploy-pre-mle.sql deploy-post-mle.sql; do
  grep -q "$marker" "$root/scripts/verify-cloud-database.sh"
done
! grep -Eq 'build-ojvm|load-cloud-ojvm|loadjava|ojvm-preflight|ojvm-postload' \
  "$root/scripts/verify-cloud-database.sh"
grep -q 'DOOMDB_CLOUD_EXECUTE' "$root/scripts/verify-cloud-database.sh"
grep -q 'chown -R oracle:oinstall' "$root/scripts/load-cloud-assets.sh"
grep -q "plsql_ccflags='doom_dev_ojvm:false'" \
  "$root/scripts/verify-cloud-database.sh"
for source in t11.1-cloud-api.mjs t11.1-build-evidence.mjs t11.1-deployment-manifest.mjs; do node --check "$root/scripts/$source";done
T111_REQUIRE_PRODUCTION=1 node "$root/evaluator/t11.1/source-audit.mjs"
node "$root/evaluator/t11.1/self-check.mjs"
node "$root/evaluator/t11.1/mutation-self-check.mjs"

set +e
env -i PATH="$PATH" HOME="${HOME:-/tmp}" bash "$root/scripts/verify-cloud-database.sh" >"$tmp/out" 2>"$tmp/err"
rc=$?
set -e
[[ "$rc" -ne 0 ]]
grep -q '^T11.1 NOT RUN:' "$tmp/err"
grep -q 'DOOMDB_CLOUD_EXECUTE=YES' "$tmp/err"
! grep -q 'PASS' "$tmp/out"
[[ ! -e /tmp/doomdb-t111-evidence.json ]]

mkdir "$tmp/wallet";printf 'fixture\n' >"$tmp/wallet/tnsnames.ora";chmod 600 "$tmp/wallet/tnsnames.ora"
printf '{}\n' >"$tmp/seeds.json"
set +e
env -i PATH="$PATH" HOME="${HOME:-/tmp}" DOOMDB_CLOUD_EXECUTE=YES \
  ADB_CONNECTION_STRING=doomdb_low ADB_USERNAME=DOOM \
  ADB_PASSWORD='unsafe"password' ADB_WALLET_DIR="$tmp/wallet" \
  ADB_ORDS_BASE_URL=https://example.invalid/ords/doom \
  ADB_LOCAL_SEED_EVIDENCE="$tmp/seeds.json" ADB_EXPECTED_MAX_CPU=2 \
  ADB_EXPECTED_MAX_STORAGE_GB=20 ADB_EXPECTED_AUTOSCALING=false \
  bash "$root/scripts/verify-cloud-database.sh" >"$tmp/injection.out" 2>"$tmp/injection.err"
rc=$?
set -e
[[ "$rc" -ne 0 ]]
grep -q 'cannot be represented safely' "$tmp/injection.err"
[[ ! -e /tmp/doomdb-t111-evidence.json ]]

printf '%s\n' \
  'schema|sql/schema/a.sql|aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa' \
  'seed|sql/seed/b.sql|bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb' \
  'engine|sql/engine/c.sql|cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc' \
  'rest|sql/rest/d.sql|dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd' >"$tmp/ledger"
printf '%s\n' '{"schema":1,"runtime":"MLE_JAVASCRIPT","teaVMVersion":"0.15.0","compilerRelease":11,"targetType":"JAVASCRIPT","moduleType":"ES2015","optimizationLevel":"ADVANCED","minifying":true,"profile":"simulation-engine-headless","inputBytecodeSha256":"83ebc323785cefcacf7b2c434b856e6d62f1f9ae4f77b063e6bce1f0a0e0f099","mochaBytecodeSha256":"42b25147133bb5c84c3b19c1511583bbd36219fb2a68996244106f40078f943e","authority":{"bytes":1170639,"sha256":"103e15e913b3a8f9a84497af601666fde5f47a720ac4b22fd7843db2559b665e"},"tablePack":{"bytes":180272,"sha256":"058cd0df9444131b356762a096fd422d5131ac3aea91163aee056e8ad4965b44"},"iwadSha256":"7323bcc168c5a45ff10749b339960e98314740a734c30d4b9f3337001f9e703d"}' >"$tmp/mle.json"
node "$root/scripts/t11.1-deployment-manifest.mjs" "$tmp/ledger" "$tmp/manifest.json" "$tmp/mle.json"
jq -e '(.domains|map(.domain)==["schema","seed","engine","rest"] and map(.order)==[1,2,3,4] and all(.files==1)) and .mleArtifact.runtime=="MLE_JAVASCRIPT" and .mleArtifact.authority.bytes==1170639 and (.javaArtifact|not)' "$tmp/manifest.json" >/dev/null
cp "$tmp/ledger" "$tmp/mutant";printf '%s\n' 'rest|../escape.sql|eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee' >>"$tmp/mutant"
if node "$root/scripts/t11.1-deployment-manifest.mjs" "$tmp/mutant" "$tmp/mutant.json" "$tmp/mle.json" >/dev/null 2>&1; then printf 'unsafe deployment mutation survived\n' >&2;exit 1;fi
printf 'PASS T11.1-SOURCE-FIRST (shell/static/self 22/22; mutations 24/24; guards fail closed)\n'
