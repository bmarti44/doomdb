#!/usr/bin/env bash
set -euo pipefail
root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd);cd "$root";tmp=$(mktemp -d);trap 'rm -rf "$tmp"' EXIT
scripts/db_sql.sh evaluator/t6.1/concurrency-setup.sql >/dev/null
scripts/db_sql.sh evaluator/t6.1/concurrency-worker.sql >"$tmp/a" 2>&1 & a=$!
scripts/db_sql.sh evaluator/t6.1/concurrency-worker.sql >"$tmp/b" 2>&1 & b=$!
sa=0;sb=0;wait "$a"||sa=$?;wait "$b"||sb=$?;[[ $sa -eq 0 && $sb -eq 0 ]]
ha=$(awk '/T61_RESULT/{print $2}' "$tmp/a");hb=$(awk '/T61_RESULT/{print $2}' "$tmp/b")
[[ "$ha" =~ ^[0-9a-f]{64}$ && "$ha" == "$hb" ]]
scripts/db_sql.sh evaluator/t6.1/concurrency-assert.sql
scripts/db_sql.sh evaluator/t6.1/concurrency-setup.sql >/dev/null
scripts/db_sql.sh evaluator/t6.1/concurrency-worker.sql >"$tmp/c" 2>&1 & c=$!
scripts/db_sql.sh evaluator/t6.1/concurrency-worker-conflict.sql >"$tmp/d" 2>&1 & d=$!
sc=0;sd=0;wait "$c"||sc=$?;wait "$d"||sd=$?
if [[ $sc -eq 0 && $sd -ne 0 ]];then grep -q 'ORA-20862' "$tmp/d"
elif [[ $sd -eq 0 && $sc -ne 0 ]];then grep -q 'ORA-20862' "$tmp/c"
else printf 'expected one concurrent success and one conflict, got %s/%s\n' "$sc" "$sd" >&2;exit 1;fi
scripts/db_sql.sh evaluator/t6.1/concurrency-assert.sql
printf 'PASS T6.1-CONCURRENCY (4/4 identical and conflicting callers serialized exactly once)\n'
