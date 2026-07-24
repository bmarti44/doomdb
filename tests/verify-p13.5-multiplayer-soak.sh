#!/usr/bin/env bash
set -Eeuo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$root"
match_file="${DOOMDB_MATCH_ID_FILE:-$(mktemp)}"
cleanup() {
  match="$(tr -d '\r\n' <"$match_file" 2>/dev/null || true)"
  rm -f "$match_file"
  [[ "$match" =~ ^[0-9a-f]{32}$ ]] || return 0
  if [[ "${DOOMDB_PRESERVE_DIAGNOSTIC_MATCH:-0}" == 1 ]]; then
    printf 'PMLE_SOAK_CLEANUP|PRESERVED|match=%s\n' "$match"
    return 0
  fi
  scripts/db_sql.sh - >/dev/null <<SQL
declare
  l_generation number;
  l_owned number;
  l_assigned number:=0;
  l_deadline timestamp with time zone;
begin
  select generation,
    (select count(*) from doom_match_member mm
      where mm.match_id=m.match_id and mm.player_slot=0
        and mm.display_name='SOAK HOST')
    into l_generation,l_owned
    from doom_match m where match_id='$match';
  if l_owned<>1 then
    raise_application_error(-20796,'refusing to clean a non-SOAK match');
  end if;
  doom_match_worker.stop_match('$match',l_generation);
  l_deadline:=systimestamp+numtodsinterval(10,'SECOND');
  loop
    select count(*) into l_assigned from doom_mle_warm_slot
      where assigned_match='$match'
        and slot_status in('CLAIMED','RUNNING');
    exit when l_assigned=0 or systimestamp>=l_deadline;
    dbms_session.sleep(.1);
  end loop;
  if l_assigned<>0 then
    for slot_ in (
      select job_name,incarnation_token,worker_sid,worker_serial,
        worker_spid,worker_job_run from doom_mle_warm_slot
      where assigned_match='$match' and slot_status in('CLAIMED','RUNNING')
    ) loop
      doom_worker_lifecycle.stop_job(
        slot_.job_name,true,'SOAK cleanup of dead retained incarnation',
        slot_.incarnation_token,slot_.worker_sid,slot_.worker_serial,
        slot_.worker_spid,slot_.worker_job_run);
    end loop;
  end if;
  select count(*) into l_assigned from doom_mle_warm_slot
    where assigned_match='$match' and slot_status in('CLAIMED','RUNNING');
  if l_assigned<>0 then
    raise_application_error(-20796,'SOAK retained slots did not release');
  end if;
  delete from doom_match where match_id='$match';
  commit;
exception
  when no_data_found then null;
end;
/
SQL
}
trap cleanup EXIT
for _ in $(seq 1 120); do
  curl --fail --silent http://localhost:8080/health.txt >/dev/null && break
  sleep .25
done
DOOMDB_MATCH_ID_FILE="$match_file" node tests/verify-p13.5-multiplayer-soak.mjs
