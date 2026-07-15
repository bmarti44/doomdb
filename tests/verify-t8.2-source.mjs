import assert from 'node:assert/strict';
import fs from 'node:fs';

const read=name=>fs.readFileSync(new URL(`../${name}`,import.meta.url),'utf8');
const schema=read('sql/sim/staged/t8.2_schema.sql');
const workflow=read('sql/sim/080_workflows.sql');
const ticHook=read('sql/sim/staged/t8.2_tic_hook.sql');
const apiHook=read('sql/rest/staged/t8.2_api_hook.sql');
const client=read('client/staged/t8.2/workflows.mjs');

for(const token of ['menu_selection','god_mode','fullmap','workflow_generation',
  'intermission_kills','intermission_items','intermission_secrets',
  'intermission_time_tics','intermission_state_sha','intermission_frame_sha',
  'automap_discovery'])assert.ok(schema.toLowerCase().includes(token),token);
for(const token of ["'NONE','OPEN','DOWN','UP','SELECT','BACK','RESTART'",
  "'GOD','ALL','NOCLIP','FULLMAP'",'^REWIND:(0|[1-9][0-9]*)$',
  'doom_ammo_def','doom_weapon_def','game_mode=\'DEAD\'',
  "game_mode='INTERMISSION'",'p_gameplay_enabled'])assert.ok(workflow.includes(token),token);
assert.match(workflow,/where session_token=p_session for update/i);
assert.match(workflow,/p_menu_action='NONE'/i);
assert.match(workflow,/map_status='DONE'/i);
assert.match(ticHook,/doom_workflow\.apply_control/i);
assert.match(ticHook,/doom_history\.rewind_to_tic/i);
assert.match(ticHook,/doom_workflow\.finish_gameplay/i);
assert.match(ticHook,/doom_workflow\.seal_terminal/i);
assert.match(apiHook,/doom_workflow\.initialize_session/i);
for(const endpoint of ['new_game/','step/','save_game/','load_game/',
  'start_replay/','step_replay/'])assert.ok(client.includes(endpoint),endpoint);
for(const forbidden of ['execute immediate','dbms_random','autonomous_transaction',
  'commit;','rollback;','evaluator/t8.2','fixtures.json','playwright']) {
  assert.ok(!`${workflow}\n${ticHook}\n${apiHook}`.toLowerCase().includes(forbidden),forbidden);
}
process.stdout.write('PASS T8.2-STAGED-SOURCE-AUDIT (SQL ownership, STEP hooks, terminal and persistence seams)\n');
