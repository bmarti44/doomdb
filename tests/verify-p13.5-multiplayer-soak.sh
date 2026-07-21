#!/usr/bin/env bash
set -Eeuo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$root"
match_file="${DOOMDB_MATCH_ID_FILE:-$(mktemp)}"
cleanup() {
  match="$(tr -d '\r\n' <"$match_file" 2>/dev/null || true)"
  rm -f "$match_file"
  [[ "$match" =~ ^[0-9a-f]{32}$ ]] || return 0
  printf '%s\n' \
    "begin doom_match_worker.stop_match('$match',1); exception when others then null; end;" '/' \
    "begin dbms_session.sleep(.2); begin dbms_scheduler.drop_job('DOOM_MATCH_${match^^}',true); exception when others then null; end; delete from doom_match where match_id='$match'; commit; end;" '/' |
    scripts/db_sql.sh - >/dev/null
}
trap cleanup EXIT
for _ in $(seq 1 120); do
  curl --fail --silent http://localhost:8080/health.txt >/dev/null && break
  sleep .25
done
DOOMDB_MATCH_ID_FILE="$match_file" node tests/verify-p13.5-multiplayer-soak.mjs
