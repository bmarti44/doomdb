#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
node "$root/evaluator/t6.4/self-check.mjs"
node "$root/evaluator/t6.4/mutation-self-check.mjs"
T64_REQUIRE_PRODUCTION=1 node "$root/evaluator/t6.4/source-audit.mjs"
"$root/scripts/db_sql.sh" "$root/evaluator/t6.4/oracle-production.sql"
printf 'PASS T6.4-VISIBLE (28/28 test ids, 848/848 declared assertions)\n'
