#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tmp="$root/.tmp-t12-$$"
mkdir -p "$tmp"
project="doomdb-t12-$$"

cleanup() {
  docker compose -f "$root/compose.yaml" -p "$project" down --volumes --remove-orphans >/dev/null 2>&1 || true
  rm -rf "$tmp"
}
trap cleanup EXIT INT TERM

printf '%s\n' 'T12Live-Oracle-7f3d9a!' > "$tmp/oracle.txt"
printf '%s\n' 'T12Live-Doom-8c4e2b!' > "$tmp/doom.txt"
chmod 600 "$tmp/oracle.txt" "$tmp/doom.txt"

export COMPOSE_PROJECT_NAME="$project"
export DOOMDB_ORACLE_PASSWORD_FILE="$tmp/oracle.txt"
export DOOMDB_APP_PASSWORD_FILE="$tmp/doom.txt"
export DOOMDB_DB_PORT="${DOOMDB_T12_DB_PORT:-12521}"
export DOOMDB_HTTP_PORT="${DOOMDB_T12_HTTP_PORT:-18081}"

docker compose -f "$root/compose.yaml" up --detach --wait --wait-timeout 1800

state_value() {
  printf '%s\n' \
    'set heading off feedback off pagesize 0' \
    "select component || '|' || to_char(semantic_version, 'FM9999999990', 'NLS_NUMERIC_CHARACTERS=''.,''') from doom_bootstrap_state order by component;" \
    | "$root/scripts/db_sql.sh" \
    | sed -n 's/^[[:space:]]*\(P1_BOOTSTRAP|1\)[[:space:]]*$/\1/p'
}

"$root/scripts/bootstrap.sh"
first="$(state_value)"
[[ "$first" == 'P1_BOOTSTRAP|1' ]]

"$root/scripts/bootstrap.sh"
second="$(state_value)"
[[ "$second" == 'P1_BOOTSTRAP|1' ]]
[[ "$first" == "$second" ]]

printf '%s\n' 'insert into doomdb_missing_seed_target values (1);' > "$tmp/failing-seed.sql"
if "$root/scripts/db_sql.sh" "$tmp/failing-seed.sql" >/dev/null 2>&1; then
  printf 'failed seed statement unexpectedly succeeded\n' >&2
  exit 1
fi

after_failure="$(state_value)"
[[ "$after_failure" == "$second" ]]
printf 'PASS T1.2-live (5/5 assertions)\n'
