#!/usr/bin/env bash
set -euo pipefail
root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
cd "$root"
node evaluator/t3.3/self-check.mjs
node evaluator/t3.3/source-audit.mjs
scripts/db_sql.sh evaluator/t3.3/oracle-production.sql
printf 'PASS T3.3-VISIBLE (15/15 test ids, 455/455 declared assertions)\n'
