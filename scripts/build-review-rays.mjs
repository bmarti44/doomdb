#!/usr/bin/env node
import fs from 'node:fs';
import path from 'node:path';
import { spawnSync } from 'node:child_process';

const root = path.resolve(import.meta.dirname, '..');
const token = 'd00dd00dd00dd00dd00dd00dd00dd00d';
const sql = `
set feedback off heading off pagesize 0 linesize 32767 trimspool on
set constraints all deferred;
declare
  l_weapon doom_weapon_def.weapon_id%type;
  l_x number; l_y number; l_angle number;
begin
  delete from game_sessions where session_token='${token}';
  select min(weapon_id) into l_weapon from doom_weapon_def;
  select x,y,angle into l_x,l_y,l_angle from doom_map_thing
   where thing_id=(select min(thing_id) from doom_map_thing where thing_type=1);
  insert into game_sessions(session_token,game_mode,skill,current_tic,rng_cursor,map_status,paused,menu_state,automap_state,current_player_id,save_lineage,last_command_seq,expires_at,created_at)
  values('${token}','GAME',3,0,0,'ACTIVE',0,'NONE','OFF',null,'DASHBOARD',0,systimestamp+interval '1' hour,systimestamp);
  insert into players(session_token,player_id,x,y,z,momentum_x,momentum_y,momentum_z,angle,view_height,view_bob,health,armor,armor_type,blue_key,yellow_key,red_key,ammo_bullets,ammo_shells,ammo_rockets,ammo_cells,weapon_mask,selected_weapon,power_invulnerability,power_invisibility,power_ironfeet,power_lightamp,kill_count,item_count,secret_count,alive)
  values('${token}',0,l_x,l_y,0,0,0,0,l_angle,41,0,100,0,0,0,0,0,50,0,0,0,1,l_weapon,0,0,0,0,0,0,0,1);
  update game_sessions set current_player_id=0 where session_token='${token}';
end;
/
select json_object(
  'column' value r.column_no, 'camX' value r.cam_x,
  'rayX' value r.ray_x, 'rayY' value r.ray_y,
  'hitCount' value coalesce(h.hit_count,0),
  'nearestT' value n.hit_t, 'nearestU' value n.hit_u,
  'linedefId' value n.linedef_id, 'segId' value n.seg_id,
  'facingSide' value n.facing_side absent on null returning varchar2(4000))
from table(doom_r1_rays('${token}')) r
left join (select column_no,count(*) hit_count from table(doom_r1_hits('${token}')) group by column_no) h on h.column_no=r.column_no
left join table(doom_r1_nearest('${token}')) n on n.column_no=r.column_no
order by r.column_no;
select json_object('spawnX' value x,'spawnY' value y,'angle' value angle returning varchar2(4000))
from doom_map_thing where thing_id=(select min(thing_id) from doom_map_thing where thing_type=1);
delete from game_sessions where session_token='${token}';
commit;
`;

const run = spawnSync(path.join(root, 'scripts/db_sql.sh'), ['-'], {
  cwd: root, input: sql, encoding: 'utf8', maxBuffer: 16 * 1024 * 1024,
  env: process.env,
});
if (run.status !== 0) {
  process.stderr.write(run.stdout ?? '');
  process.stderr.write(run.stderr ?? '');
  process.exit(run.status ?? 1);
}
const rows = run.stdout.split(/\r?\n/).map(line => line.trim()).filter(line => line.startsWith('{'));
if (rows.length !== 321) throw new Error(`expected 320 ray rows plus spawn, received ${rows.length}`);
const columns = rows.slice(0, 320).map(JSON.parse);
const spawn = JSON.parse(rows[320]);
if (!columns.every((row, index) => row.column === index)) throw new Error('ray columns are not exactly 0..319');
const payload = {schema:1, kind:'doomdb-r1-ray-diagnostic', width:320, spawn, columns};
const outDir = path.join(root, 'client/dist/review');
fs.mkdirSync(outDir, {recursive:true});
fs.writeFileSync(path.join(outDir, 'rays.json'), `${JSON.stringify(payload)}\n`);
process.stdout.write(`PASS dashboard ray diagnostic (320/320 real database columns)\n`);
