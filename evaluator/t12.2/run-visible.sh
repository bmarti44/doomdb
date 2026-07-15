#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
node "$root/evaluator/t12.2/self-check.mjs"
node "$root/evaluator/t12.2/mutation-self-check.mjs"
T122_REQUIRE_PRODUCTION=1 node "$root/evaluator/t12.2/source-audit.mjs"
"$root/verify.sh" evaluator-self-test
node "$root/evaluator/run-foundation.mjs"
evidence="${T122_EVIDENCE:-$root/.artifacts/t12.2/evidence.json}"
node "$root/scripts/run-performance-optimization.mjs" --verify-only "$evidence"
node "$root/evaluator/t12.2/validate-evidence.mjs" "$evidence" "$(dirname "$evidence")"
printf 'PASS T12.2-VISIBLE (15/15 test ids, 2248/2248 declared assertions)\n'
