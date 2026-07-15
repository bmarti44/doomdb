#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
order_text="$(node "$root/tools/wad/seed-load-order.mjs")"
mapfile_compat=()
while IFS= read -r file; do
  mapfile_compat+=("$file")
done <<< "$order_text"

if [[ "${#mapfile_compat[@]}" -eq 0 ]]; then
  printf 'seed manifest resolved to zero files\n' >&2
  exit 1
fi

{
  printf '%s\n' 'set feedback off heading off pagesize 0'
  for file in "${mapfile_compat[@]}"; do
    seed_file="$root/sql/seed/$file"
    [[ -f "$seed_file" ]] || { printf 'missing seed file: %s\n' "$file" >&2; exit 1; }
    printf 'prompt SEED %s\n' "$file"
    if [[ "$file" == 160_asset_texels_*.sql ]]; then
      node "$root/tools/wad/at-load-sql.mjs" "$seed_file"
    else
      command cat "$seed_file"
    fi
    # Each manifest file is already a deterministic, bounded batch group. A
    # complete rerun drops the schema first, so file-level commits avoid
    # retaining millions of rows of undo inside the required 2 GiB cgroup.
    printf '%s\n' 'commit;'
  done
} | "$root/scripts/db_sql.sh"

printf 'SEED LOAD COMPLETE (%d files)\n' "${#mapfile_compat[@]}"
