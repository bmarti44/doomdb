#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
out="${DOOMDB_T43_ARTIFACT_DIR:-$root/artifacts/t4.3-review}"
token='41414141414141414141414141414141'
mkdir -p "$out"
rm -f "$out"/*.observation.json "$out"/*.png "$out"/*.rgba "$out"/*.diagnostics.json

cleanup() {
  printf '%s\n' "delete from game_sessions where session_token='$token';" commit\; \
    | "$root/scripts/db_sql.sh" >/dev/null 2>&1 || true
}
trap cleanup EXIT INT TERM

"$root/scripts/db_sql.sh" - <<SQL
set constraints all deferred;
declare l_weapon doom_weapon_def.weapon_id%type;
begin
  delete from game_sessions where session_token='$token';
  select min(weapon_id) into l_weapon from doom_weapon_def;
  insert into game_sessions(session_token,game_mode,skill,current_tic,rng_cursor,map_status,paused,menu_state,automap_state,current_player_id,save_lineage,last_command_seq,expires_at,created_at)
  values('$token','GAME',3,0,0,'ACTIVE',0,'NONE','OFF',null,'T43',0,systimestamp+interval '1' hour,systimestamp);
  insert into players(session_token,player_id,x,y,z,momentum_x,momentum_y,momentum_z,angle,view_height,view_bob,health,armor,armor_type,blue_key,yellow_key,red_key,ammo_bullets,ammo_shells,ammo_rockets,ammo_cells,weapon_mask,selected_weapon,power_invulnerability,power_invisibility,power_ironfeet,power_lightamp,kill_count,item_count,secret_count,alive)
  values('$token',0,-416,256,0,0,0,0,0,41,0,100,0,0,0,0,0,50,0,0,0,1,l_weapon,0,0,0,0,0,0,0,1);
  update game_sessions set current_player_id=0 where session_token='$token';
  commit;
end;
/
SQL

container="$(docker compose -f "$root/compose.yaml" ps -q db)"
[[ -n "$container" ]]
capture_pose() {
  local id="$1" x="$2" y="$3" angle="$4" prefix="/tmp/doomdb-t43-$1"
  {
    printf 'define 1 = %s\n' "$token"
    printf 'define 2 = %s\n' "$x"
    printf 'define 3 = %s\n' "$y"
    printf 'define 4 = %s\n' "$angle"
    printf 'define 5 = %s\n' "$prefix"
    cat "$root/evaluator/t4.3/capture-pose.sql"
  } | "$root/scripts/db_sql.sh" - >/dev/null
  for suffix in pixels palette rle; do
    # SQL*Plus consumes the first dot after &5 as the substitution terminator.
    docker cp "$container:$prefix$suffix.csv" "$out/$id.$suffix.csv" >/dev/null
    docker compose -f "$root/compose.yaml" exec -T db rm -f "$prefix$suffix.csv"
  done
  node "$root/evaluator/t4.3/build-observation.mjs" "$out/$id" "$id" "$x" "$y" "$angle" "$out/$id.observation.json"
  node "$root/evaluator/t4.3/run-observation.mjs" "$out/$id.observation.json" "$out"
  rm -f "$out/$id.pixels.csv" "$out/$id.palette.csv" "$out/$id.rle.csv"
}

capture_pose spawn-east -416 256 0
capture_pose spawn-north -416 256 90
capture_pose spawn-south -416 256 270
node "$root/tests/verify-t4.3-artifacts.mjs" "$out"
