#!/usr/bin/env bash
set -euo pipefail
root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd);cd "$root"
node evaluator/t6.1/self-check.mjs
node evaluator/t6.1/mutation-self-check.mjs
node evaluator/t6.1/source-audit.mjs
scripts/db_sql.sh evaluator/t6.1/oracle-production.sql
evaluator/t6.1/run-concurrency.sh
printf 'PASS T6.1-VISIBLE (20/20 test ids, 430/430 declared assertions)\n'
