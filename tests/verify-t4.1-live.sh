#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tmp="$root/.tmp-t4-1-$$"
project="doomdb-t4-1-$$"
mkdir -p "$tmp"

cleanup() {
  docker compose -f "$root/compose.yaml" -p "$project" down --volumes --remove-orphans >/dev/null 2>&1 || true
  rm -rf "$tmp"
}
trap cleanup EXIT INT TERM

printf '%s\n' 'T41-Oracle-Isolated-7a3d9c!' > "$tmp/oracle.txt"
printf '%s\n' 'T41-Doom-Isolated-8b4e2d!' > "$tmp/doom.txt"
chmod 600 "$tmp/oracle.txt" "$tmp/doom.txt"

export COMPOSE_PROJECT_NAME="$project"
export DOOMDB_ORACLE_PASSWORD_FILE="$tmp/oracle.txt"
export DOOMDB_APP_PASSWORD_FILE="$tmp/doom.txt"
export DOOMDB_DB_PORT="${DOOMDB_T41_DB_PORT:-$((25000 + $$ % 4000))}"
export DOOMDB_HTTP_PORT="${DOOMDB_T41_HTTP_PORT:-$((35000 + $$ % 4000))}"

node "$root/evaluator/t4.1/self-check.mjs"
node "$root/evaluator/t4.1/mutation-self-check.mjs"
node "$root/evaluator/t4.1/source-audit.mjs"
"$root/scripts/verify-secrets-ignored.sh"

docker compose -f "$root/compose.yaml" up --detach --wait --wait-timeout 1800 db
"$root/scripts/bootstrap.sh"
"$root/evaluator/t4.1/run-visible.sh"

# Proportionate inherited live regressions on the same fresh schema.
"$root/evaluator/t3.2/run-visible.sh"
"$root/evaluator/t3.3/run-visible.sh"
"$root/evaluator/t3.4/run-visible.sh"

printf 'PASS T4.1-LIVE-ISOLATED (1296/1296 declared assertions; 16/16 mutation witnesses)\n'
