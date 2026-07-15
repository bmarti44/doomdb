#!/usr/bin/env bash
set -euo pipefail
root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
cd "$root"
node evaluator/t3.4/self-check.mjs
node evaluator/t3.4/mutation-self-check.mjs
node evaluator/t3.4/source-audit.mjs
scripts/db_sql.sh evaluator/t3.4/oracle-production.sql
printf 'PASS T3.4-VISIBLE (17/17 test ids, 3300/3300 declared assertions)\n'
