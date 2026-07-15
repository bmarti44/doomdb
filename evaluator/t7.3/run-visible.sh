#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
node "$root/evaluator/t7.3/self-check.mjs"
node "$root/evaluator/t7.3/mutation-self-check.mjs"
T73_REQUIRE_PRODUCTION=1 node "$root/evaluator/t7.3/source-audit.mjs"
"$root/scripts/db_sql.sh" "$root/evaluator/t7.3/oracle-production.sql"
npx playwright test --config "$root/evaluator/t7.3/playwright.config.ts"
node "$root/evaluator/playwright/validate-report.mjs" /tmp/t7.3-playwright-results.json "$root/evaluator/t7.3/browser-test-ids.json"
printf 'PASS T7.3-VISIBLE (20/20 test ids, 684/684 declared assertions)\n'
