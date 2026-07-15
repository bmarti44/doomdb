#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
node "$root/evaluator/t7.2/self-check.mjs"
node "$root/evaluator/t7.2/mutation-self-check.mjs"
T72_REQUIRE_PRODUCTION=1 node "$root/evaluator/t7.2/source-audit.mjs"
"$root/scripts/db_sql.sh" "$root/evaluator/t7.2/oracle-production.sql"
printf 'PASS T7.2-VISIBLE (25/25 test ids, 2565/2565 declared assertions)\n'
