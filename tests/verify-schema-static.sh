#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
passed=0
check() { "$@"; passed=$((passed + 1)); }

check bash -n "$root/scripts/bootstrap.sh"
check bash -n "$root/scripts/load_seed.sh"
check test -x "$root/scripts/load_seed.sh"
check test "$(node "$root/tools/wad/seed-load-order.mjs" | wc -l | tr -d ' ')" = 537
check grep -qx '@seed-manifest' "$root/sql/bootstrap/order.txt"
check grep -qx 'sql/schema/055_finalize_seed.sql' "$root/sql/bootstrap/order.txt"
check grep -q 'constraint at_asset_fk foreign key (a)' "$root/sql/schema/055_finalize_seed.sql"
check grep -q 'doom_map_linedef_start_fk' "$root/sql/schema/010_static.sql"
check grep -q 'doom_map_thing_type_fk' "$root/sql/schema/040_constraints.sql"
check grep -q 'doom_map_sector_special_fk' "$root/sql/schema/040_constraints.sql"
check grep -q 'create table game_sessions' "$root/sql/schema/030_dynamic.sql"
check grep -q 'create table step_responses' "$root/sql/schema/030_dynamic.sql"
check grep -q 'create table state_history' "$root/sql/schema/030_dynamic.sql"
check grep -q 'create table save_slots' "$root/sql/schema/030_dynamic.sql"
check grep -q 'create global temporary table frame_rle_run' "$root/sql/schema/030_dynamic.sql"
check grep -q "'FAR_DISTANCE' config_key, 8192" "$root/sql/schema/050_config.sql"
check grep -q "'PLAYER_RADIUS', 16" "$root/sql/schema/050_config.sql"
check grep -q 'create or replace view doom_vertex' "$root/sql/schema/010_static.sql"
check grep -q 'create table doom_linedef' "$root/sql/schema/010_static.sql"
check grep -q 'geom mdsys.sdo_geometry' "$root/sql/schema/010_static.sql"
check grep -q 'delete from user_sdo_geom_metadata' "$root/sql/schema/000_drop.sql"
check grep -q 'grant select on doom_config to public' "$root/sql/schema/060_grants.sql"
check sh -c "! rg -i 'evaluator/|goldens/|tools/reference|reports/|expected[_ -]output' '$root/sql/schema' '$root/sql/engine' '$root/scripts/load_seed.sh' '$root/tools/wad/seed-load-order.mjs' '$root/tools/wad/at-load-sql.mjs'"
# Exact checked-tree identity is tested without mutating the checked-in file.
tmp="$(mktemp)"
trap 'rm -f "$tmp"' EXIT
node "$root/tools/wad/generate-engine-sql.mjs" "$tmp"
check cmp -s "$tmp" "$root/sql/engine/010_engine_defs.sql"

printf 'PASS T3.1-static (%d/%d assertions)\n' "$passed" "$passed"
