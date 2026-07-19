#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
node "$root/evaluator/t8.2/self-check.mjs"
node "$root/evaluator/t8.2/mutation-self-check.mjs"
T82_REQUIRE_PRODUCTION=1 node "$root/evaluator/t8.2/source-audit.mjs"
node "$root/evaluator/t8.2/direct-api.mjs"
npx playwright test --config "$root/evaluator/t8.2/playwright.config.ts"
node "$root/evaluator/playwright/validate-report.mjs" /tmp/t8.2-playwright-results.json "$root/evaluator/t8.2/browser-test-ids.json"
printf 'PASS T8.2-VISIBLE (29/29 test ids, 323136/323136 declared assertions)\n'
