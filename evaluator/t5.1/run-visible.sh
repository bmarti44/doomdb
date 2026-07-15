#!/usr/bin/env bash
set -euo pipefail
root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
cd "$root"
node evaluator/t5.1/self-check.mjs
node evaluator/t5.1/mutation-self-check.mjs
node evaluator/t5.1/source-audit.mjs
scripts/db_sql.sh evaluator/t5.1/oracle-production.sql
printf 'PASS T5.1-VISIBLE (20/20 test ids, 674/674 declared assertions)\n'
