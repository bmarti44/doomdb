#!/usr/bin/env bash
set -Eeuo pipefail

root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
stamp=$(date -u +%Y-%m-%dT%H%M%SZ)
output=${1:-"$root/artifacts/performance/pmle-live-frame-authority/local-cross-slot-$stamp.log"}
slot1_log="${output%.log}-slot1.log"
slot2_log="${output%.log}-slot2.log"
slot1_parked=0

for path in "$output" "$slot1_log" "$slot2_log"; do
  [[ ! -e "$path" ]] ||
    { printf 'refusing to overwrite cross-slot evidence: %s\n' "$path" >&2; exit 2; }
done
mkdir -p "$(dirname "$output")"
umask 077

restore_pool() {
  local status=$?
  trap - EXIT
  if [[ "$slot1_parked" == 1 ]]; then
    "$root/scripts/db_sql.sh" - >/dev/null <<'SQL' || status=1
begin doom_match_worker.start_warm_pool;end;
/
SQL
  fi
  exit "$status"
}
trap restore_pool EXIT

ready="$("$root/scripts/db_sql.sh" - <<'SQL'
set heading off feedback off pagesize 0
select 'READY='||count(*) from doom_mle_warm_slot
where slot_id in(1,2) and slot_status='READY' and assigned_match is null;
select 'ACTIVE='||count(*) from doom_match
where match_state in('LOBBY','STARTING','ACTIVE','RECOVERING');
SQL
)"
[[ "$(awk -F= '/^READY=/{print $2}' <<<"$ready")" == 2
  && "$(awk -F= '/^ACTIVE=/{print $2}' <<<"$ready")" == 0 ]] || {
  printf 'cross-slot gate requires two READY slots and no live match\n%s\n' \
    "$ready" >&2
  exit 1
}

DOOMDB_LIVE_FRAME_EXPECTED_SLOT=1 \
  "$root/tests/run-mle-live-frame-e2e.sh" "$slot1_log"

"$root/scripts/db_sql.sh" - >/dev/null <<'SQL'
declare
  l_count number;
begin
  select count(*) into l_count from doom_mle_warm_slot
    where slot_id=1 and slot_status='READY' and assigned_match is null;
  if l_count<>1 then
    raise_application_error(-20000,'slot 1 is not uniquely parkable');
  end if;
  for slot_ in (
    select * from doom_mle_warm_slot
    where slot_id=1 and slot_status='READY' and assigned_match is null
  ) loop
    doom_worker_lifecycle.stop_job(
      slot_.job_name,true,'live-frame cross-slot equality gate',
      slot_.incarnation_token,slot_.worker_sid,slot_.worker_serial,
      slot_.worker_spid,slot_.worker_job_run);
  end loop;
end;
/
SQL
slot1_parked=1

DOOMDB_LIVE_FRAME_EXPECTED_SLOT=2 \
  "$root/tests/run-mle-live-frame-e2e.sh" "$slot2_log"

marker1="$(grep '^PMLE_LIVE_FRAME_E2E|PASS|' "$slot1_log")"
marker2="$(grep '^PMLE_LIVE_FRAME_E2E|PASS|' "$slot2_log")"
[[ -n "$marker1" && -n "$marker2" ]]
field() {
  printf '%s\n' "$1" | tr '|' '\n' |
    awk -F= -v key="$2" '$1==key {print $2}'
}
for key in initial_sha256 moved_sha256 authority_sha256 renderer_sha256 \
    coordinator_sha256; do
  first="$(field "$marker1" "$key")"
  second="$(field "$marker2" "$key")"
  [[ "$first" =~ ^[0-9a-f]{64}$ && "$first" == "$second" ]] || {
    printf 'cross-slot %s mismatch: %s != %s\n' "$key" "$first" "$second" >&2
    exit 1
  }
done

"$root/scripts/db_sql.sh" - >/dev/null <<'SQL'
begin doom_match_worker.start_warm_pool;end;
/
SQL
restored="$("$root/scripts/db_sql.sh" - <<'SQL'
set heading off feedback off pagesize 0
select 'READY='||count(*) from doom_mle_warm_slot
where slot_id in(1,2) and slot_status='READY' and assigned_match is null;
SQL
)"
[[ "$(awk -F= '/^READY=/{print $2}' <<<"$restored")" == 2 ]] ||
  { printf 'cross-slot gate did not restore both retained slots\n' >&2; exit 1; }
slot1_parked=0

{
  printf 'PMLE_LIVE_FRAME_CROSS_SLOT|PASS'
  printf '|initial_sha256=%s' "$(field "$marker1" initial_sha256)"
  printf '|moved_sha256=%s' "$(field "$marker1" moved_sha256)"
  printf '|authority_sha256=%s' "$(field "$marker1" authority_sha256)"
  printf '|renderer_sha256=%s' "$(field "$marker1" renderer_sha256)"
  printf '|coordinator_sha256=%s' "$(field "$marker1" coordinator_sha256)"
  printf '|slots=1,2|full_world_seed=1|pool_restored=1\n'
} | tee "$output"
