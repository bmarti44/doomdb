#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tmp="$(mktemp -d "${TMPDIR:-/tmp}/doomdb-t111-source.XXXXXX")";trap 'rm -rf "$tmp"' EXIT

bash -n "$root/scripts/verify-cloud-database.sh"
bash -n "$root/scripts/mochadoom/build-ojvm-jar.sh" "$root/scripts/mochadoom/load-cloud-ojvm.sh"
for marker in build-ojvm-jar.sh ojvm-preflight.sql load-cloud-ojvm.sh ojvm-postload.sql deploy-pre-java.sql deploy-post-java.sql; do
  grep -q "$marker" "$root/scripts/verify-cloud-database.sh"
done
grep -q 'DOOMDB_CLOUD_EXECUTE' "$root/scripts/verify-cloud-database.sh"
grep -q 'chown -R oracle:oinstall' "$root/scripts/mochadoom/load-cloud-ojvm.sh"
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
printf '%s\n' '{"schema":1,"javaRelease":8,"revision":"c0af1322ee5fd168b5cf8aaaf504cab2d1aabe93","classCount":830,"jarSha256":"a27903f2dcd81aecb0292f605453969ad3d4389382bebdb8386dff3cb13f23ab"}' >"$tmp/java.json"
node "$root/scripts/t11.1-deployment-manifest.mjs" "$tmp/ledger" "$tmp/manifest.json" "$tmp/java.json"
jq -e '(.domains|map(.domain)==["schema","seed","engine","rest"] and map(.order)==[1,2,3,4] and all(.files==1)) and .javaArtifact.javaRelease==8 and .javaArtifact.classCount==830' "$tmp/manifest.json" >/dev/null
cp "$tmp/ledger" "$tmp/mutant";printf '%s\n' 'rest|../escape.sql|eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee' >>"$tmp/mutant"
if node "$root/scripts/t11.1-deployment-manifest.mjs" "$tmp/mutant" "$tmp/mutant.json" "$tmp/java.json" >/dev/null 2>&1; then printf 'unsafe deployment mutation survived\n' >&2;exit 1;fi
printf 'PASS T11.1-SOURCE-FIRST (shell/static/self 22/22; mutations 24/24; guards fail closed)\n'
