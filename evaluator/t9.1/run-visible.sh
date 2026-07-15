#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
node "$root/evaluator/t9.1/self-check.mjs"
node "$root/evaluator/t9.1/mutation-self-check.mjs"
T91_REQUIRE_PRODUCTION=1 node "$root/evaluator/t9.1/source-audit.mjs"
one="$(mktemp)";two="$(mktemp)";trap 'rm -f "$one" "$two"' EXIT
"$root/scripts/db_sql.sh" "$root/evaluator/t9.1/oracle-production.sql" | tee "$one"
"$root/scripts/db_sql.sh" "$root/evaluator/t9.1/oracle-production.sql" | tee "$two"
node "$root/evaluator/t9.1/validate-oracle-output.mjs" "$one" "$two"
if [[ "$(node -p "require('$root/evaluator/t9.1/fixtures.json').visualReview.status")" != "APPROVED" ]]; then
  printf 'FAIL T9.1: real database-derived 150-frame animation visual checkpoint is still PENDING\n' >&2
  exit 1
fi
printf 'PASS T9.1-VISIBLE (21/21 test ids, 12731825/12731825 declared assertions, visual checkpoint approved)\n'
