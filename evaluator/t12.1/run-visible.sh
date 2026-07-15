#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
node "$root/evaluator/t12.1/self-check.mjs"
node "$root/evaluator/t12.1/mutation-self-check.mjs"
T121_REQUIRE_PRODUCTION=1 node "$root/evaluator/t12.1/source-audit.mjs"
"$root/verify.sh" evaluator-self-test
node "$root/evaluator/run-foundation.mjs"
evidence="${T121_EVIDENCE:-$root/.artifacts/t12.1/evidence.json}"
node "$root/scripts/verify-performance-baseline.mjs" "$evidence"
node "$root/evaluator/t12.1/validate-evidence.mjs" "$evidence" "$(dirname "$evidence")"
printf 'PASS T12.1-VISIBLE (13/13 test ids, 864/864 declared assertions)\n'
