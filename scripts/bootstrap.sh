#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
order_file="${DOOMDB_BOOTSTRAP_ORDER:-$root/sql/bootstrap/order.txt}"
if [[ "$(basename "$order_file")" == production-order.txt ]]; then
  export DOOMDB_PLSQL_CCFLAGS=doom_dev_ojvm:false
fi

if [[ $# -ne 0 ]]; then
  printf 'usage: %s\n' "$0" >&2
  exit 2
fi
if [[ ! -f "$order_file" ]]; then
  printf 'bootstrap order file not found: %s\n' "$order_file" >&2
  exit 2
fi

declare -A seen=()
count=0
while IFS= read -r entry || [[ -n "$entry" ]]; do
  [[ -z "$entry" || "$entry" == \#* ]] && continue
  if [[ "$entry" == '@seed-manifest' ]]; then
    if [[ -n "${seen[$entry]:-}" ]]; then
      printf 'duplicate bootstrap entry: %s\n' "$entry" >&2
      exit 1
    fi
    seen[$entry]=1
    printf 'BOOTSTRAP %03d %s\n' "$((count + 1))" "$entry"
    "$root/scripts/load_seed.sh"
    count=$((count + 1))
    continue
  fi
  if [[ "$entry" == '@mle-module' ]]; then
    if [[ -n "${seen[$entry]:-}" ]]; then
      printf 'duplicate bootstrap entry: %s\n' "$entry" >&2
      exit 1
    fi
    seen[$entry]=1
    printf 'BOOTSTRAP %03d %s\n' "$((count + 1))" "$entry"
    "$root/probes/mle/teavm-engine/load-mle-module.sh" --production
    count=$((count + 1))
    continue
  fi
  if [[ ! "$entry" =~ ^sql/(bootstrap|schema|seed|engine|spatial|bsp|accel|render|sim|rest)/[A-Za-z0-9._/-]+\.sql$ || "$entry" == *'..'* ]]; then
    printf 'unsafe bootstrap entry: %s\n' "$entry" >&2
    exit 1
  fi
  if [[ -n "${seen[$entry]:-}" ]]; then
    printf 'duplicate bootstrap entry: %s\n' "$entry" >&2
    exit 1
  fi
  seen[$entry]=1
  sql_file="$root/$entry"
  if [[ ! -f "$sql_file" ]]; then
    printf 'missing bootstrap SQL: %s\n' "$entry" >&2
    exit 1
  fi
  printf 'BOOTSTRAP %03d %s\n' "$((count + 1))" "$entry"
  "$root/scripts/db_sql.sh" "$sql_file"
  count=$((count + 1))
done < "$order_file"

if [[ "$count" -eq 0 ]]; then
  printf 'bootstrap order contains no SQL files\n' >&2
  exit 1
fi
printf 'BOOTSTRAP COMPLETE (%d files)\n' "$count"
