#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
node "$root/evaluator/t11.1/self-check.mjs"
node "$root/evaluator/t11.1/mutation-self-check.mjs"
T111_REQUIRE_PRODUCTION=1 node "$root/evaluator/t11.1/source-audit.mjs"
"$root/verify.sh" evaluator-self-test
"$root/scripts/verify-cloud-database.sh"
node "$root/evaluator/t11.1/validate-evidence.mjs" /tmp/doomdb-t111-evidence.json
printf 'PASS T11.1-VISIBLE (14/14 test ids, 684/684 declared assertions)\n'
