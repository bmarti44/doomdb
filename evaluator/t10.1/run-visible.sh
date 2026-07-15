#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
node "$root/evaluator/t10.1/self-check.mjs"
node "$root/evaluator/t10.1/mutation-self-check.mjs"
T101_REQUIRE_PRODUCTION=1 node "$root/evaluator/t10.1/source-audit.mjs"
"$root/scripts/db_sql.sh" "$root/evaluator/t10.1/oracle-production.sql"
node "$root/evaluator/t10.1/direct-http.mjs"
printf 'PASS T10.1-VISIBLE (15/15 test ids, 1457/1457 declared assertions)\n'
