import assert from 'node:assert/strict';
import fs from 'node:fs';

const worker = fs.readFileSync(new URL(
  '../sql/sim/084_multiplayer_worker.sql', import.meta.url), 'utf8');
const schema = fs.readFileSync(new URL(
  '../sql/schema/048_multiplayer_worker.sql', import.meta.url), 'utf8');
const api = fs.readFileSync(new URL(
  '../sql/rest/010_doom_api.sql', import.meta.url), 'utf8');

assert.match(schema, /create table doom_match_worker_control/);
assert.match(schema, /deferrable initially deferred/);
assert.match(worker, /job_type=>'STORED_PROCEDURE'/);
assert.match(worker, /job_action=>'DOOM_MATCH_WORKER\.RUN_MATCH'/);
assert.match(worker, /returning response_blob into l_b0/);
assert.match(worker, /returning response_blob into l_b1/);
assert.match(worker, /complete two-player vector required/);
assert.match(worker, /listagg\(rawtohex\(ticcmd_raw\),''\) within group\(order by player_slot\)/);
assert.match(worker, /current_tic=p_tic-1/);
assert.match(worker, /request_status='PROCESSING' and requested_tic=p_tic/);
assert.match(worker, /l_existing<>p_ticcmd_raw or l_existing_seq<>p_command_seq/);
assert.match(worker, /p_command_seq<>l_seq_frontier\+1/);
assert.match(worker, /c_command_deadline_ms constant pls_integer:=75/);
assert.match(worker, /'NEUTRAL_DEADLINE'/);
assert.match(worker, /fill_deadline\(p_match,l_generation,l_epoch\)/);
assert.match(worker, /hextoraw\(lpad\(to_char\(l_neutral,'fmxx'\),2,'0'\)\)/);
assert.match(worker, /member_state='DISCONNECTED'/);
assert.match(worker, /last_seen_at<l_now-interval '3' second/);
assert.match(api, /member_state in\('ACTIVE','DISCONNECTED'\)/);
assert.match(worker, /if mod\(p_tic,32\)=0 then/);
assert.match(worker, /l_checkpoint_status:=doom_mocha_save\(l_checkpoint\)/);
assert.match(worker, /checkpoint locator length mismatch/);
assert.match(worker, /procedure recover_match\(/);
assert.match(worker, /doom_mocha_multiplayer_reconstruct/);
assert.match(worker, /recovery POV mismatch/);
assert.match(worker, /generation=l_new/);
assert.match(worker, /match_state='ACTIVE' then reconstruct_existing/);
assert.match(worker, /doom_mocha_multiplayer_new_game/);
assert.match(worker, /doom_mocha_multiplayer_step/);
assert.match(worker, /l_dispose:=doom_mocha_dispose/);
assert.match(worker, /l_ignored:=doom_mocha_dispose/);
assert.doesNotMatch(worker, /MULTI_ROOT\|'\|\|p_match/);
assert.match(worker, /restart reconstruction remains deferred/);
assert.match(api, /doom_match_worker\.start_ready\(p_match,30000,p_match_state\)/);
assert.doesNotMatch(api, /insert into doom_match_(?:tic|frame|checkpoint)/);
assert.doesNotMatch(worker, /grant |ords\.enable_object|doom_api\./i);
assert.match(api, /Request-time cascade deletion made NEW_GAME block for minutes/);
assert.doesNotMatch(api, /delete from game_sessions where session_token in/);

process.stdout.write(
  'PASS P13.2-RETAINED-MATCH-WORKER-SOURCE private scheduler, direct locators, fences, complete vectors\n');
