#!/usr/bin/env bash
set -euo pipefail
root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
cd "$root"
node evaluator/t4.2/self-check.mjs
node evaluator/t4.2/mutation-self-check.mjs
node evaluator/t4.2/source-audit.mjs
scripts/db_sql.sh evaluator/t4.2/oracle-production.sql
printf 'PASS T4.2-VISIBLE (20/20 test ids, 384426/384426 declared assertions)\n'
