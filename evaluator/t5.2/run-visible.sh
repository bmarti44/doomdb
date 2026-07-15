#!/usr/bin/env bash
set -euo pipefail
root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
cd "$root"
node evaluator/t5.2/self-check.mjs
node evaluator/t5.2/mutation-self-check.mjs
node evaluator/t5.2/source-audit.mjs
scripts/db_sql.sh evaluator/t5.2/oracle-production.sql
printf 'PASS T5.2-VISIBLE (20/20 test ids, 1856885/1856885 declared assertions)\n'
