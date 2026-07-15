#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
node "$root/evaluator/t10.3/self-check.mjs"
node "$root/evaluator/t10.3/mutation-self-check.mjs"
T103_REQUIRE_PRODUCTION=1 node "$root/evaluator/t10.3/source-audit.mjs"
"$root/scripts/verify-local-e2e.sh"
printf 'PASS T10.3-VISIBLE (16/16 test ids, 816/816 declared assertions)\n'
