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
grep -q 'verify-production-drop-inventory.mjs' \
  "$root/scripts/verify-cloud-database.sh"
grep -q 'schema-grants.sql' "$root/scripts/verify-cloud-database.sh"
grep -q 'create property graph to DOOM' \
  "$root/deploy/cloud/t11.1/schema-grants.sql"
grep -q 'install-validation-only' \
  "$root/deploy/cloud/t11.1/schema-grants.sql"
node "$root/tests/verify-cloud-schema-grants.mjs"
awk '
  /least_entry=deploy\/cloud\/t11\.1\/least-grants\.sql/ { least=NR }
  /command cat "\$root\/\$entry"/ { if (least>0 && final==0) final=NR }
  END { exit !(least>0 && final>least) }
' "$root/scripts/verify-cloud-database.sh"
awk '
  /verify-production-drop-inventory\.mjs/ { inventory=NR }
  /phase=capability_probe/ { mutation=NR }
  END { exit !(inventory>0 && mutation>inventory) }
' "$root/scripts/verify-cloud-database.sh"
grep -q 'chown -R oracle:oinstall' "$root/scripts/load-cloud-assets.sh"
grep -q 'redact-cloud-output.mjs.*iwad.log' "$root/scripts/load-cloud-assets.sh"
grep -q 'ords_schema_root=${ADB_ORDS_BASE_URL%/}' \
  "$root/scripts/verify-cloud-database.sh"
grep -q 'show_failure "$tmp/managed-ords-health.json"' \
  "$root/scripts/verify-cloud-database.sh"
grep -q 'doomdb-t111-failure' "$root/scripts/verify-cloud-database.sh"
! grep -q 'private diagnostics discarded' \
  "$root/scripts/verify-cloud-database.sh"
grep -q "plsql_ccflags='doom_dev_ojvm:false'" \
  "$root/scripts/verify-cloud-database.sh"
for source in t11.1-cloud-api.mjs t11.1-build-evidence.mjs t11.1-deployment-manifest.mjs; do node --check "$root/scripts/$source";done
node "$root/scripts/verify-db-output-helper.mjs" |
  grep -q 'DB_OUTPUT_HELPER|PASS'
grep -q "normalizeDbOutput(catalogRaw)" \
  "$root/scripts/t11.1-build-evidence.mjs"
bash -n "$root/scripts/sqlcl-dedicated-container.sh"
grep -q 'SQLcl is deliberately isolated from the Oracle database container' \
  "$root/scripts/sqlcl-dedicated-container.sh"
grep -q 'l_mle_specs<>27' \
  "$root/deploy/cloud/t11.1/catalog-observation.sql"
grep -q 'mleCallSpecs:27' "$root/scripts/t11.1-build-evidence.mjs"
grep -q "dbms_output.put_line('T111_PUBLIC_EXECUTE|'||trim(r.table_name))" \
  "$root/deploy/cloud/t11.1/catalog-observation.sql"
grep -q "dbms_output.put_line('T111_REST|'||trim(r.parsing_object)" \
  "$root/deploy/cloud/t11.1/catalog-observation.sql"
grep -q 'trimout on trimspool on' \
  "$root/deploy/cloud/t11.1/catalog-observation.sql"
grep -q 'e.catalog.javaObjects,0' "$root/evaluator/t11.1/reference.mjs"
grep -q 'e.catalog.mleCallSpecs,27' "$root/evaluator/t11.1/reference.mjs"
grep -q "case'javaProductionLeak':e.catalog.javaObjects=1" \
  "$root/evaluator/t11.1/mutation-self-check.mjs"
grep -q "case'mleSpecDrift':e.catalog.mleCallSpecs=26" \
  "$root/evaluator/t11.1/mutation-self-check.mjs"
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
printf '%s\n' '{"schema":1,"runtime":"MLE_JAVASCRIPT","teaVMVersion":"0.15.0","compilerRelease":11,"targetType":"JAVASCRIPT","moduleType":"ES2015","optimizationLevel":"ADVANCED","minifying":true,"profile":"simulation-engine-headless","inputBytecodeSha256":"289edf1d678f9aced34c969ed24dcc9c90b9dce38f1b15701b284a2e5384df7e","mochaBytecodeSha256":"c6d26633316b7a6251e79b9013bfb16ca877e2d93642ebbaba17bfc66c8861a4","authority":{"bytes":1090790,"sha256":"66dd235cde82a8b8fbcac88bb905912bacfd6ea40671d2808e5951ce290ce873"},"tablePack":{"bytes":180272,"sha256":"058cd0df9444131b356762a096fd422d5131ac3aea91163aee056e8ad4965b44"},"liveFrameRenderer":{"requiredAuthoritySha256":"66dd235cde82a8b8fbcac88bb905912bacfd6ea40671d2808e5951ce290ce873","bytes":48242,"sha256":"50835b7130486e5e705bec501c785a43e8158ce5e77202afe2ad9ff4f4133d17","coordinatorBytes":48960,"coordinatorSha256":"b8d2250f998f7fc5a1a7e4209dff0508abf02fec1672ba41e42de1dda73a5145"},"iwadSha256":"7323bcc168c5a45ff10749b339960e98314740a734c30d4b9f3337001f9e703d"}' >"$tmp/mle.json"
node "$root/scripts/t11.1-deployment-manifest.mjs" "$tmp/ledger" "$tmp/manifest.json" "$tmp/mle.json"
jq -e '(.domains|map(.domain)==["schema","seed","engine","rest"] and map(.order)==[1,2,3,4] and all(.files==1)) and .mleArtifact.runtime=="MLE_JAVASCRIPT" and .mleArtifact.authority.bytes==1090790 and (.javaArtifact|not)' "$tmp/manifest.json" >/dev/null
cp "$tmp/ledger" "$tmp/mutant";printf '%s\n' 'rest|../escape.sql|eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee' >>"$tmp/mutant"
if node "$root/scripts/t11.1-deployment-manifest.mjs" "$tmp/mutant" "$tmp/mutant.json" "$tmp/mle.json" >/dev/null 2>&1; then printf 'unsafe deployment mutation survived\n' >&2;exit 1;fi
printf 'PASS T11.1-SOURCE-FIRST (shell/static/self 22/22; mutations 26/26; guards fail closed)\n'
