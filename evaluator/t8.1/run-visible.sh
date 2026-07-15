#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
node "$root/evaluator/t8.1/self-check.mjs"
node "$root/evaluator/t8.1/mutation-self-check.mjs"
node "$root/evaluator/t8.1/source-audit.mjs"
if [[ ! -f "$root/evaluator/t8.1/approved-route.json" ]]; then
  printf 'FAIL T8.1: approved route/milestone/screenshot golden absent; actual live review required\n' >&2
  exit 1
fi
"$root/scripts/db_sql.sh" "$root/evaluator/t8.1/oracle-production.sql"
printf 'FAIL T8.1: live public-API route driver is not promoted until T7.1-T7.3 and visual review complete\n' >&2
exit 1
