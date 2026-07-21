import assert from 'node:assert/strict';
import fs from 'node:fs';

const api = fs.readFileSync(new URL(
  '../sql/rest/010_doom_api.sql', import.meta.url), 'utf8');
const lifecycle = api.slice(api.indexOf('  function new_capability'),
  api.indexOf('  procedure new_game(', api.indexOf('  function new_capability')));
const specification = api.slice(api.indexOf('create or replace package doom_api'),
  api.indexOf('create or replace package body doom_api'));
const httpSmoke = fs.readFileSync(new URL(
  './verify-p13.1-multiplayer-autorest.mjs', import.meta.url), 'utf8');
const matchWorker = fs.readFileSync(new URL(
  '../sql/sim/084_multiplayer_worker.sql', import.meta.url), 'utf8');

for (const procedure of [
  'create_match', 'join_match', 'ready_match', 'match_status',
  'submit_match_step', 'submit_match_batch', 'submit_match_batch_input',
  'revise_match_input', 'match_input_frontier', 'poll_match_batch',
  'poll_match_frame', 'leave_match'
]) {
  assert.equal((api.match(new RegExp(`  procedure ${procedure}\\(`, 'g')) ?? []).length, 2,
    `${procedure} must appear once in the spec and once in the body`);
}
assert.match(api, /c_match_auth\s+constant pls_integer := -20713/);
assert.match(lifecycle, /dbms_crypto\.randombytes\(32\)/);
assert.match(lifecycle, /utl_raw\.concat\(p_salt,hextoraw\(p_capability\)\)/);
assert.match(lifecycle, /match unavailable/g);
assert.match(lifecycle, /for update/g);
assert.match(lifecycle, /l_recent>=16 or l_open>=32/);
assert.match(api, /procedure renew_match_lease/);
assert.match(api, /expires_at=p_now\+interval '20' minute/);
assert.match(api, /expires_at<p_now\+interval '10' minute/);
assert.match(lifecycle, /renew_match_lease\(p_match,l_now\)/);
assert.doesNotMatch(matchWorker,/expires_at\s*=/i,
  'autonomous worker must not renew an abandoned match lease');
assert.match(lifecycle, /upper\(p_game_mode\) not in\('COOP','DEATHMATCH'\)/);
assert.match(lifecycle, /'LOBBY',upper\(p_game_mode\)/);
assert.match(lifecycle, /interval '20' minute/);
assert.match(lifecycle, /membership_epoch=l_epoch/);
assert.match(lifecycle, /doom_match_worker\.start_ready\(p_match,30000,p_match_state\)/);
assert.match(lifecycle, /doom_match_worker\.recover_match\(p_match,0,l_recovery_state\)/);
assert.match(lifecycle, /l_worker_heartbeat<utc_now-interval '5' second/);
assert.match(lifecycle, /returns ACTIVE only after real Java tic-zero payloads/);
assert.match(lifecycle, /Supplying the previously returned player capability/);
assert.doesNotMatch(specification, /function new_capability|function capability_hash|require_match_shape/);
assert.doesNotMatch(lifecycle, /insert into doom_match_(?:tic|frame|checkpoint)/);
assert.doesNotMatch(lifecycle,
  /insert into [^(]+\([^)]*(?:capability_token|host_token|join_token|player_token)/is);
assert.doesNotMatch(lifecycle, /dbms_output|insert into doom_worker|doom_mocha_/i);
assert.match(httpSmoke, /two clients create\/join\/retry\/one-ready\/status\/leave/);
assert.match(api, /if l_state='ACTIVE' then/);
assert.match(api, /command_source='NEUTRAL_LEFT'/);
assert.match(api, /doom_match_worker\.stop_match\(p_match,l_generation\)/);
assert.match(httpSmoke, /Never include a response body in failures/);
assert.doesNotMatch(httpSmoke, /console\.(?:log|error)\([^)]*(?:capability|created|joined)/i);

process.stdout.write(
  'PASS P13.1-MULTIPLAYER-API-SOURCE allowlist, salted capabilities, locks, bounds, explicit start boundary\n');
