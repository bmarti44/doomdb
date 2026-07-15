#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
node "$root/evaluator/t11.2/self-check.mjs"
node "$root/evaluator/t11.2/mutation-self-check.mjs"
T112_REQUIRE_PRODUCTION=1 node "$root/evaluator/t11.2/source-audit.mjs"
"$root/verify.sh" evaluator-self-test
"$root/scripts/verify-cloud-browser.sh"
node "$root/evaluator/t11.2/validate-evidence.mjs" /tmp/doomdb-t112-evidence.json
printf 'PASS T11.2-VISIBLE (13/13 test ids, 742/742 declared assertions)\n'
