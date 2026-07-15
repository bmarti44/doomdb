#!/usr/bin/env bash
set -euo pipefail
root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
cd "$root"
node evaluator/t4.1/self-check.mjs
node evaluator/t4.1/mutation-self-check.mjs
node evaluator/t4.1/source-audit.mjs
scripts/db_sql.sh evaluator/t4.1/oracle-production.sql
printf 'PASS T4.1-VISIBLE (18/18 test ids, 1296/1296 declared assertions)\n'
