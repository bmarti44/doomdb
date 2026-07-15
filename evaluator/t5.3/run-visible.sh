#!/usr/bin/env bash
set -euo pipefail
root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
cd "$root"
node evaluator/t5.3/self-check.mjs
node evaluator/t5.3/mutation-self-check.mjs
node evaluator/t5.3/source-audit.mjs
scripts/db_sql.sh evaluator/t5.3/oracle-production.sql
printf 'PASS T5.3-VISIBLE (17/17 test ids, 988/988 declared assertions)\n'
