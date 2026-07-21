#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$root"
match_file="${DOOMDB_MATCH_ID_FILE:-$(mktemp)}"
cleanup() {
  match="$(tr -d '\r\n' <"$match_file" 2>/dev/null || true)"
  if [[ "${DOOMDB_KEEP_MATCH:-0}" == 1 ]]; then
    printf 'RETAINED_MATCH=%s\n' "$match" >&2
    return 0
  fi
  rm -f "$match_file"
  [[ "$match" =~ ^[0-9a-f]{32}$ ]] || return 0
  container="$(docker compose ps -q db)"
  java_home=/opt/oracle/product/26ai/dbhomeFree
  {
    printf 'connect DOOM/"'
    docker exec "$container" sh -c "tr -d '\r\n' < /run/secrets/doom_password"
    printf '"@FREEPDB1\n'
    printf "begin doom_match_worker.stop_match('%s',1); exception when others then null; end;\n/\n" "$match"
    printf "begin dbms_session.sleep(.2); begin dbms_scheduler.drop_job('DOOM_MATCH_%s',true); exception when others then null; end; delete from doom_match where match_id='%s'; commit; end;\n/\nexit\n" "${match^^}" "$match"
  } | docker exec -i "$container" "$java_home/bin/sqlplus" -s /nolog >/dev/null
}
trap cleanup EXIT
for _ in $(seq 1 120); do
  if curl --fail --silent http://localhost:8080/health.txt >/dev/null; then
    break
  fi
  sleep .25
done
curl --fail --silent --show-error http://localhost:8080/health.txt >/dev/null
DOOMDB_MATCH_ID_FILE="$match_file" \
  DOOMDB_TEST_ORDS_RESTART="${DOOMDB_TEST_ORDS_RESTART:-1}" \
  node tests/verify-p13.3-multiplayer-client.mjs
