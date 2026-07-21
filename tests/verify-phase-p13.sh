#!/usr/bin/env bash
set -Eeuo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$root"

sql() {
  scripts/db_sql.sh "$1"
}

# Static authority/security checks first: a failure here must not create a
# match, retained Scheduler session, or secret-bearing HTTP response.
node tests/verify-p13.1-multiplayer-schema.mjs
node tests/verify-p13.1-multiplayer-api.mjs
node tests/verify-p13.2-multiplayer-adapter.mjs
node tests/verify-p13.2-retained-match-worker.mjs
node tests/verify-p13.5-operations.mjs
node tests/verify-session-cleanup-static.mjs

# Engine/schema/lifecycle and retained-authority gates.
sql tests/verify-p13.0-multiplayer-probe.sql
sql scripts/mochadoom/multiplayer-feasibility-benchmark.sql
sql tests/verify-p13.1-multiplayer-schema.sql
sql tests/verify-p13.1-multiplayer-api.sql
sql tests/verify-p13.1-multiplayer-rate-limit.sql
node tests/verify-p13.1-multiplayer-autorest.mjs
sql tests/verify-p13.2-multiplayer-adapter.sql
sql tests/verify-p13.2-retained-match-worker.sql
sql tests/verify-p13.2-paced-input.sql
sql tests/verify-p13.2-active-leave.sql
bash tests/verify-p13.2-multiplayer-autorest.sh

# Real routes, recovery, selected modes/cap, and operations bounds.
bash tests/verify-p13.3-coop-route.sh
bash tests/verify-p13.3-coop-browser-route.sh
bash tests/verify-p13.3-multiplayer-client.sh
sql tests/verify-p13.4-deathmatch-probe.sql
sql tests/verify-p13.4-deathmatch-lifecycle.sql
bash tests/verify-p13.4-deathmatch-client.sh
sql tests/verify-p13.5-active-retention.sql
sql tests/verify-session-cleanup-live.sql

# Selection requires two consecutive 300-frame browser passes. The soak is
# deliberately last and defaults to the full contractual 30 minutes.
bash tests/verify-p13.5-multiplayer-performance.sh
bash tests/verify-p13.5-multiplayer-performance.sh
DOOMDB_MULTIPLAYER_SOAK_SECONDS="${DOOMDB_MULTIPLAYER_SOAK_SECONDS:-1800}" \
  bash tests/verify-p13.5-multiplayer-soak.sh

printf 'PASS P13 (database-authoritative two-player co-op/deathmatch, replay, recovery, performance, 30-minute soak)\n'
