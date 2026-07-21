#!/usr/bin/env bash
set -Eeuo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$root"
match_file="${DOOMDB_MATCH_ID_FILE:-$(mktemp)}"
cleanup() {
  match="$(tr -d '\r\n' <"$match_file" 2>/dev/null || true)"
  rm -f "$match_file"
  if [[ "$match" =~ ^[0-9a-f]{32}$ ]]; then
    printf '%s\n' \
      "declare g number; begin select generation into g from doom_match_worker_control where match_id='$match'; doom_match_worker.stop_match('$match',g); exception when others then null; end;" '/' \
      "begin dbms_session.sleep(.2); begin dbms_scheduler.drop_job('DOOM_MATCH_${match^^}',true); exception when others then null; end; delete from doom_match where match_id='$match'; commit; end;" '/' |
      scripts/db_sql.sh - >/dev/null
  fi
  printf '%s\n' \
    "update doom_config set text_value='PACED_INPUT' where config_key='MATCH_WORKER_MODE';" \
    'commit;' | scripts/db_sql.sh - >/dev/null
}
trap cleanup EXIT
scripts/db_sql.sh - <<'SQL' >/dev/null
declare m varchar2(32);begin
  select text_value into m from doom_config where config_key='MATCH_WORKER_MODE' for update;
  if m<>'PACED_INPUT' then raise_application_error(-20000,'unexpected multiplayer worker mode');end if;
  update doom_config set text_value='LOCKSTEP' where config_key='MATCH_WORKER_MODE';commit;
end;
/
SQL
DOOMDB_MATCH_ID_FILE="$match_file" node tests/verify-p13.3-coop-browser-route.mjs
