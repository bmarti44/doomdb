import assert from 'node:assert/strict';
import fs from 'node:fs';

const index=fs.readFileSync('client/dist/play/index.html','utf8');
const mleIndex=fs.readFileSync('client/dist/play/mle.html','utf8');
const menu=fs.readFileSync('client/src/main.ts','utf8');
const client=fs.readFileSync('client/src/multiplayer.ts','utf8');
const api=fs.readFileSync('client/src/api.ts','utf8');
const schema=fs.readFileSync('sql/schema/053_singleplayer_mle.sql','utf8');
const rest=fs.readFileSync('sql/rest/010_doom_api.sql','utf8');
const worker=fs.readFileSync('sql/sim/084_multiplayer_worker.sql','utf8');

assert.match(index,/src="\/play\/main\.js"/);
assert.match(mleIndex,/<body data-doom-solo>/);
assert.match(mleIndex,/src="\/play\/multiplayer\.js"/);
assert.match(menu,/new URL\('mle\.html', location\.href\)/);
assert.match(menu,/location\.assign\(mleUrl\);\s*return;/);
assert.match(client,/const soloMode = document\.body\.hasAttribute\('data-doom-solo'\)/);
assert.match(client,/createMatch\('PLAYER 1',soloSkill,'COOP',1\)/);
assert.match(client,/await readyMatch\(value\.match,value\.playerCapability,true\)/);
assert.match(client,/function scheduleLobbyRefresh\(\): void/);
assert.doesNotMatch(client,/lobbyTimer = window\.setInterval/);
assert.match(api,/p_display_name: displayName, p_max_players: maxPlayers/);
assert.match(schema,/check\(max_players between 2 and 4\)/);
assert.match(rest,/p_max_players\s+in\s+number default 2/);
assert.match(rest,/'SOLO NEUTRAL'/);
assert.match(rest,/l_solo_capability:=null/);
assert.doesNotMatch(index+mleIndex,/NEW_GAME|POLL_FRAME|SUBMIT_STEP/);
assert.match(worker,/if l_solo=1 then/);
assert.match(worker,/solo authority admission fence/);
assert.match(worker,/else\s+await_initial_standby\(p_match,l_generation\)/);
assert.match(worker,/Cold TeaVM initialization is intentionally outside the match-row/);
assert.match(worker,/doom_mle_match_runtime\.initialize_game[\s\S]+select max_players[\s\S]+for update/);

process.stdout.write('PASS MLE-SOLO-SOURCE /play uses one-player retained MLE match authority\n');
