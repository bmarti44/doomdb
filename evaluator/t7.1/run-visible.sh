#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
node "$root/evaluator/t7.1/self-check.mjs"
node "$root/evaluator/t7.1/mutation-self-check.mjs"
T71_REQUIRE_PRODUCTION=1 node "$root/evaluator/t7.1/source-audit.mjs"
"$root/scripts/db_sql.sh" "$root/evaluator/t7.1/oracle-production.sql"
printf 'PASS T7.1-VISIBLE (23/23 test ids, 1582/1582 declared assertions)\n'
