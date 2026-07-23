import assert from 'node:assert/strict';
import fs from 'node:fs';

const worker = fs.readFileSync(new URL(
  '../sql/sim/084_multiplayer_worker.sql', import.meta.url), 'utf8');
const schema = fs.readFileSync(new URL(
  '../sql/schema/048_multiplayer_worker.sql', import.meta.url), 'utf8');
const routeSchema = fs.readFileSync(new URL(
  '../sql/schema/049_multiplayer_route_diagnostics.sql', import.meta.url), 'utf8');
const api = fs.readFileSync(new URL(
  '../sql/rest/010_doom_api.sql', import.meta.url), 'utf8');
const adapter = fs.readFileSync(new URL(
  '../java/mochadoom-ojvm/src/doomdb/mocha/DoomDbMochaAdapter.java', import.meta.url), 'utf8');
const deploy = fs.readFileSync(new URL(
  '../scripts/mochadoom/deploy-ojvm-spike.sh', import.meta.url), 'utf8');
const coopRoute = fs.readFileSync(new URL(
  '../scripts/mochadoom/build-p13-coop-route-gate.mjs', import.meta.url), 'utf8');
const coopGolden = JSON.parse(fs.readFileSync(new URL(
  '../artifacts/p13.3-coop-e1m1-route.json', import.meta.url), 'utf8'));

assert.match(schema, /create table doom_match_worker_control/);
assert.match(schema, /deferrable initially deferred/);
assert.match(schema, /route_status_tic number\(12\)/);
assert.match(schema, /route_status varchar2\(4000\)/);
assert.match(routeSchema, /user_tab_columns/);
assert.match(routeSchema, /create table doom_match_route_trace/);
assert.match(coopRoute, /P13\.3 diag=/);
assert.match(coopRoute, /--guest-spawn-clear/);
assert.match(coopRoute, /--guest-strafe=/);
assert.match(coopRoute, /00E8000000000000/);
assert.match(coopRoute, /turnHeld < 6 \? 320/);
assert.equal(coopGolden.accepted.mode, 'INTERMISSION');
assert.equal(coopGolden.accepted.membershipHex, '03');
assert.equal(coopGolden.accepted.guestNonNeutralTics, 8);
assert.equal(coopGolden.accepted.freshReconstructionExact, true);
assert.ok(coopGolden.accepted.player1TerminalY - coopGolden.accepted.player1StartY
  >= 65536, 'player 1 input must change retained world state');
assert.match(worker, /job_type=>'STORED_PROCEDURE'/);
assert.match(worker, /job_action=>'DOOM_MATCH_WORKER\.RUN_MATCH'/);
assert.match(worker, /returning response_blob into l_b0/);
assert.match(worker, /returning response_blob into l_b1/);
assert.match(worker, /complete two-player vector required/);
assert.match(worker, /listagg\(rawtohex\(ticcmd_raw\),''\) within group\(order by player_slot\)/);
assert.match(worker, /current_tic=p_tic-1/);
assert.match(worker, /request_status='PROCESSING' and requested_tic=p_tic/);
assert.match(worker, /l_route_status:=status_field\(l_status,'routeDiag'\)/);
assert.match(worker, /route_status=case when l_route_diagnostics=1 then l_route_status/);
assert.match(worker, /insert into doom_match_route_trace/);
assert.match(worker, /l_existing<>p_ticcmd_raw or l_existing_seq<>p_command_seq/);
assert.match(worker, /p_command_seq<>l_seq_frontier\+1/);
assert.match(worker, /c_command_deadline_ms constant pls_integer:=2000/);
assert.match(worker, /c_initial_command_deadline_ms constant pls_integer:=500/);
assert.match(worker, /c_frame_retention_tics constant pls_integer:=128/);
assert.match(worker, /c_checkpoint_tics constant pls_integer:=1024/);
assert.match(worker, /c_command_lead_tics constant pls_integer:=8/);
assert.match(worker, /p_tic not between l_current\+1/);
assert.match(worker, /l_next_count=2 then 'QUEUED'/);
assert.match(worker, /tic=p_tic-c_frame_retention_tics/);
assert.match(worker, /delete from doom_match_checkpoint where match_id=p_match/);
assert.match(worker, /'NEUTRAL_DEADLINE'/);
assert.match(worker, /'NEUTRAL_LEFT'/);
assert.match(worker, /disconnected_at<l_now-interval '180' second/);
assert.match(worker, /leave_tic=\(select current_tic\+1/);
assert.match(worker, /doom_mocha_multiplayer_step\(\s*2,l_membership/);
assert.match(worker, /utl_raw\.concat\(vector_\.membership_bitmap,vector_\.command_vector\)/);
assert.match(worker, /fill_deadline\(p_match,l_generation,l_epoch\)/);
assert.match(worker, /hextoraw\(lpad\(to_char\(l_neutral,'fmxx'\),2,'0'\)\)/);
assert.match(worker, /member_state='DISCONNECTED'/);
assert.match(worker, /last_seen_at<l_now-interval '3' second/);
assert.match(api, /member_state in\('ACTIVE','DISCONNECTED'\)/);
assert.match(worker, /if p_tic=32 or mod\(p_tic,c_checkpoint_tics\)=0 then/);
assert.match(worker, /procedure materialize_paced_vector/);
assert.match(worker, /worker_mode='PACED_INPUT'/);
assert.match(worker, /l_boundary_ticks:=dbms_utility\.get_time/);
assert.match(worker, /dbms_session\.sleep\(l_delay_ticks\/100\)/);
assert.doesNotMatch(worker, /l_boundary:=utc_now/,
  'wall-clock corrections must not pace the retained worker');
assert.match(worker, /request_status='PROCESSING'/);
assert.match(worker,
  /raise_application_error\(c_error,'authority admission fence'\);[\s\S]+commit;[\s\S]+l_boundary_ticks:=dbms_utility\.get_time/,
  'tic zero and authority readiness must commit before the retained tic loop');
assert.match(worker, /l_checkpoint_status:=doom_mocha_save\(l_checkpoint\)/);
assert.match(worker, /checkpoint locator length mismatch/);
assert.match(worker, /procedure recover_match\(/);
assert.match(worker, /doom_mocha_multiplayer_reconstruct/);
assert.match(adapter, /commandStream\.length\(\) == 0L\s*\? new byte\[0\]/,
  'tic-zero recovery must accept its canonical empty command ledger');
assert.match(deploy, /doom_match_worker\.stop_match/);
assert.match(deploy, /job_name like 'DOOM_MATCH_%'/);
assert.match(worker, /recovery POV mismatch/);
assert.match(worker, /generation=l_new/);
assert.match(worker, /l_match_state='ACTIVE' then\s+reconstruct_existing/);
assert.match(worker, /doom_mocha_multiplayer_new_game/);
assert.match(worker, /doom_mocha_multiplayer_step/);
assert.match(worker, /doom_mle_match_runtime\.release/);
assert.match(worker, /named \*_ojvm_oracle and are unreachable from RUN_MATCH/);
assert.doesNotMatch(worker, /MULTI_ROOT\|'\|\|p_match/);
assert.match(worker, /DMC1 checkpoints and ordered-ledger reconstruction are both durable/);
assert.match(api, /doom_match_worker\.start_ready\(p_match,30000,p_match_state\)/);
assert.doesNotMatch(api, /insert into doom_match_(?:tic|frame|checkpoint)/);
assert.doesNotMatch(worker, /grant |ords\.enable_object|doom_api\./i);
assert.match(api, /Request-time cascade deletion made NEW_GAME block for minutes/);
assert.doesNotMatch(api, /delete from game_sessions where session_token in/);

process.stdout.write(
  'PASS P13.2-RETAINED-MATCH-WORKER-SOURCE private scheduler, direct locators, fences, complete vectors\n');
