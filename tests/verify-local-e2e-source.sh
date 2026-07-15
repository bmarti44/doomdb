#!/usr/bin/env bash
set -Eeuo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$root"

bash -n scripts/verify-local-e2e.sh deploy/local/t10.3/db_sql.sh
node scripts/t10.3-inspect.mjs --self-test
node scripts/t10.3-extract-record.mjs --self-test
node evaluator/t10.3/self-check.mjs
node evaluator/t10.3/mutation-self-check.mjs
node evaluator/t10.3/source-audit.mjs
T103_REQUIRE_PRODUCTION=1 node evaluator/t10.3/source-audit.mjs

tmp="$(mktemp -d "${TMPDIR:-/tmp}/doomdb-t103-source.XXXXXXXX")"
trap 'rm -rf "$tmp"' EXIT
printf 'not-a-secret' > "$tmp/oracle"
printf 'not-a-secret' > "$tmp/app"
DOOMDB_ORACLE_PASSWORD_FILE="$tmp/oracle" \
DOOMDB_APP_PASSWORD_FILE="$tmp/app" \
T103_RUN_ID=doomdb-t103-0123456789abcdef \
T103_EVIDENCE_DIR="$tmp" \
T103_INFRASTRUCTURE_JSON='{}' \
docker compose -f deploy/local/t10.3/compose.yaml config --quiet

printf 'PASS T10.3-SOURCE-FIRST (10/10 static and orchestration-unit assertions)\n'
