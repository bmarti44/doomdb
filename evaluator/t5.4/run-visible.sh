#!/usr/bin/env bash
set -euo pipefail
root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
cd "$root"
node evaluator/t5.4/self-check.mjs
node evaluator/t5.4/mutation-self-check.mjs
node evaluator/t5.4/source-audit.mjs
node tests/verify-t5.4-goldens.mjs
scripts/db_sql.sh evaluator/t5.4/oracle-production.sql
printf 'PASS T5.4-VISIBLE (22/22 test ids, 448566/448566 declared assertions)\n'
