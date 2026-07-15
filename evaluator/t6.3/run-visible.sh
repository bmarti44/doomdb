#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
node "$root/evaluator/t6.3/self-check.mjs"
node "$root/evaluator/t6.3/mutation-self-check.mjs"
node "$root/evaluator/t6.3/source-audit.mjs"
"$root/scripts/db_sql.sh" "$root/evaluator/t6.3/oracle-production.sql"
printf 'PASS T6.3-VISIBLE (28/28 test ids, 906/906 declared assertions)\n'
