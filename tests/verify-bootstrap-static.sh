#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

for file in scripts/db_sql.sh scripts/bootstrap.sh scripts/drop_evaluator_schema.sh; do
  bash -n "$root/$file"
  test -x "$root/$file"
done
grep -q '^set -euo pipefail$' "$root/scripts/bootstrap.sh"
grep -q 'whenever sqlerror exit sql.sqlcode rollback' "$root/scripts/db_sql.sh"
grep -q "nls_numeric_characters = '.,'" "$root/scripts/db_sql.sh"
grep -q "time_zone = 'UTC'" "$root/scripts/db_sql.sh"
grep -q '^sql/bootstrap/000_bootstrap_state.sql$' "$root/sql/bootstrap/order.txt"
! "$root/scripts/drop_evaluator_schema.sh" DOOM >/dev/null 2>&1
! "$root/scripts/drop_evaluator_schema.sh" DOOMDB_EVAL-x >/dev/null 2>&1
printf 'PASS T1.2-static (10/10 assertions)\n'
