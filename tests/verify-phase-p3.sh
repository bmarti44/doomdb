#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tmp="$root/.tmp-p3-$$"
project="doomdb-p3-test-$$"
mkdir -p "$tmp"
cleanup() {
  docker compose -f "$root/compose.yaml" -p "$project" down --volumes --remove-orphans >/dev/null 2>&1 || true
  rm -rf "$tmp"
}
trap cleanup EXIT INT TERM

printf '%s\n' 'P3-Oracle-Only-7f3d9a!' > "$tmp/oracle.txt"
printf '%s\n' 'P3-Doom-Only-8c4e2b!' > "$tmp/doom.txt"
chmod 600 "$tmp/oracle.txt" "$tmp/doom.txt"
export COMPOSE_PROJECT_NAME="$project"
export DOOMDB_ORACLE_PASSWORD_FILE="$tmp/oracle.txt"
export DOOMDB_APP_PASSWORD_FILE="$tmp/doom.txt"
export DOOMDB_DB_PORT="${DOOMDB_P3_DB_PORT:-$((24000 + $$ % 5000))}"
export DOOMDB_HTTP_PORT="${DOOMDB_P3_HTTP_PORT:-$((34000 + $$ % 5000))}"

tests/verify-schema-static.sh
scripts/verify-secrets-ignored.sh
docker compose -f "$root/compose.yaml" up --detach --wait --wait-timeout 1800 db

fingerprint() {
  printf '%s\n' \
    'set heading off feedback off pagesize 0' \
    "select (select count(*) from doom_map_thing)||'|'||(select count(*) from doom_map_vertex)||'|'||(select count(*) from doom_map_linedef)||'|'||(select count(*) from doom_map_sidedef)||'|'||(select count(*) from doom_map_sector)||'|'||(select count(*) from doom_map_seg)||'|'||(select count(*) from doom_map_ssector)||'|'||(select count(*) from doom_map_node)||'|'||(select count(*) from doom_reject_byte)||'|'||(select count(*) from doom_blockmap_byte)||'|'||(select count(*) from doom_asset)||'|'||(select count(*) from doom_asset_source)||'|'||(select count(*) from at) from dual;" \
    | scripts/db_sql.sh | sed -n 's/^[[:space:]]*\([0-9][0-9|]*\)[[:space:]]*$/\1/p'
}

scripts/bootstrap.sh
first="$(fingerprint)"
expected='292|1196|1175|1829|182|2057|682|681|4141|7528|566|854|3040239'
[[ "$first" == "$expected" ]]

oracle_result="$(printf '%s\n' "set heading off feedback off pagesize 0 serveroutput on
declare
  n number;
  procedure eq(actual number, expected number, label varchar2) is
  begin if actual != expected then raise_application_error(-20931,label); end if; end;
begin
  select count(*) into n from doom_linedef; eq(n,1175,'spatial linedefs');
  select count(*) into n from doom_config; eq(n,10,'config');
  select count(*) into n from doom_state_def; eq(n,94,'states');
  select count(*) into n from doom_thing_type_def; eq(n,49,'thing defs');
  select count(*) into n from doom_rng_value; eq(n,256,'rng');
  select count(*) into n from user_constraints where status!='ENABLED' or validated!='VALIDATED'; eq(n,0,'constraints');
  select count(*) into n from user_objects where regexp_like(object_name,'(EVALUATOR|REFERENCE|GOLDEN)','i'); eq(n,0,'object audit');
  select count(*) into n from user_tables where table_name in ('GAME_SESSIONS','PLAYERS','MOBJS','SECTOR_STATE','LINE_STATE','ACTIVE_MOVERS','ACTIVE_SWITCHES','TIC_COMMANDS','GAME_EVENTS','AUDIO_EVENTS','STEP_RESPONSES','STATE_HISTORY','SAVE_SLOTS'); eq(n,13,'dynamic tables');
  dbms_output.put_line('PASS P3-SCHEMA-ORACLE');
end;
/" | scripts/db_sql.sh)"
grep -q 'PASS P3-SCHEMA-ORACLE' <<< "$oracle_result"

if printf '%s\n' "insert into doom_map_linedef(linedef_id,start_vertex_id,end_vertex_id,flags,special,tag,right_sidedef_id) values(99999,99999,0,0,0,0,0);" | scripts/db_sql.sh >/dev/null 2>&1; then
  printf 'invalid vertex reference unexpectedly succeeded\n' >&2; exit 1
fi
if printf '%s\n' "insert into at(a,x,y,c) values(99999,0,0,0);" | scripts/db_sql.sh >/dev/null 2>&1; then
  printf 'invalid asset reference unexpectedly succeeded\n' >&2; exit 1
fi
[[ "$(fingerprint)" == "$first" ]]

scripts/bootstrap.sh
[[ "$(fingerprint)" == "$first" ]]
printf 'PASS T3.1-live (13/13 assertions)\n'

evaluator/t3.2/run-visible.sh
evaluator/t3.3/run-visible.sh
evaluator/t3.4/run-visible.sh
printf 'PASS P3 (3928/3928 assertions)\n'
