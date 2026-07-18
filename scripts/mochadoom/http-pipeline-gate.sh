#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
container="$(docker compose -f "$root/compose.yaml" ps -q db)"
tmp="$(mktemp -d "${TMPDIR:-/tmp}/doomdb-mocha-http.XXXXXX")"
session=""

sql() {
  {
    printf 'connect DOOM/"'
    docker exec "$container" sh -c "tr -d '\r\n' < /run/secrets/doom_password"
    printf '"@FREEPDB1\n'
    printf '%s\n' "$1"
  } | docker exec -i "$container" \
    /opt/oracle/product/26ai/dbhomeFree/bin/sqlplus -s /nolog
}

cleanup() {
  set +e
  if [[ -n "$session" ]]; then
    sql "update doom_worker_control set stop_requested=1 where target_session='$session';
commit;
begin
 for i in 1..100 loop
  declare n number;begin
   select count(*) into n from doom_worker_control where target_session='$session';
   exit when n=0;
  end;
  dbms_session.sleep(.1);
 end loop;
end;
/
delete from game_sessions where session_token='$session';
update doom_config set text_value='SQL' where config_key='GAME_ENGINE';
commit;" >/dev/null
  else
    sql "update doom_config set text_value='SQL' where config_key='GAME_ENGINE'; commit;" \
      >/dev/null
  fi
  rm -rf "$tmp"
}
trap cleanup EXIT

sql "whenever sqlerror exit failure rollback
update doom_config set text_value='MOCHA' where config_key='GAME_ENGINE';
commit;" >/dev/null

set +e
DOOM_FIRE_EVERY="${DOOM_FIRE_EVERY:-8}" \
DOOM_SUBMIT_DEPTH="${DOOM_SUBMIT_DEPTH:-4}" \
DOOM_FETCH_DEPTH="${DOOM_FETCH_DEPTH:-2}" \
DOOM_BUFFER_FRAMES="${DOOM_BUFFER_FRAMES:-10}" \
  node "$root/scripts/performance/autorest-async-pipeline-benchmark.mjs" \
  >"$tmp/result.json" 2>"$tmp/error.log"
exit_code=$?
set -e

session="$(node -e "const fs=require('fs');try{const x=JSON.parse(fs.readFileSync(process.argv[1],'utf8').trim().split(/\\n/).at(-1));process.stdout.write(x.session||'')}catch{}" "$tmp/result.json")"
if [[ -z "$session" ]]; then
  session="$(sql "set heading off feedback off pages 0
select session_token from doom_mocha_lineage order by created_at desc fetch first 1 row only;" \
    | tail -n 1 | tr -d '[:space:]')"
fi
cat "$tmp/result.json"
cat "$tmp/error.log" >&2
exit "$exit_code"
