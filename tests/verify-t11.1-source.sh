#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tmp="$(mktemp -d "${TMPDIR:-/tmp}/doomdb-t111-source.XXXXXX")";trap 'rm -rf "$tmp"' EXIT

bash -n "$root/scripts/verify-cloud-database.sh"
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
! grep -q 'PASS' "$tmp/out"
[[ ! -e /tmp/doomdb-t111-evidence.json ]]

printf '%s\n' \
  'schema|sql/schema/a.sql|aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa' \
  'seed|sql/seed/b.sql|bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb' \
  'engine|sql/engine/c.sql|cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc' \
  'rest|sql/rest/d.sql|dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd' >"$tmp/ledger"
node "$root/scripts/t11.1-deployment-manifest.mjs" "$tmp/ledger" "$tmp/manifest.json"
jq -e '.domains|map(.domain)==["schema","seed","engine","rest"] and map(.order)==[1,2,3,4] and all(.files==1)' "$tmp/manifest.json" >/dev/null
cp "$tmp/ledger" "$tmp/mutant";printf '%s\n' 'rest|../escape.sql|eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee' >>"$tmp/mutant"
if node "$root/scripts/t11.1-deployment-manifest.mjs" "$tmp/mutant" "$tmp/mutant.json" >/dev/null 2>&1; then printf 'unsafe deployment mutation survived\n' >&2;exit 1;fi
printf 'PASS T11.1-SOURCE-FIRST (shell/static/self 22/22; mutations 24/24; guards fail closed)\n'
