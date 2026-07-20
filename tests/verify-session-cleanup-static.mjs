import assert from 'node:assert/strict';
import fs from 'node:fs';

const api = fs.readFileSync(new URL('../sql/rest/010_doom_api.sql', import.meta.url), 'utf8');
const cleanup = fs.readFileSync(new URL('../sql/sim/085_session_cleanup.sql', import.meta.url), 'utf8');
const body = api.indexOf('create or replace package body doom_api');
const start = api.indexOf('  procedure new_game(', body);
const newGame = api.slice(start, api.indexOf('  procedure step(', start));

assert.doesNotMatch(newGame,
  /delete from game_sessions where session_token in\s*\(\s*select session_token[\s\S]*expires_at/i,
  'NEW_GAME must never cascade previously expired lineage storage');
assert.match(cleanup, /create or replace package doom_session_cleanup/i);
assert.match(cleanup, /fetch first l_limit rows only/i);
assert.match(cleanup, /doom_unified_worker\.request_stop/);
assert.match(cleanup, /procedure purge_expired_matches/);
assert.match(cleanup, /delete from doom_match where match_id=expired_\.match_id/);
assert.match(cleanup, /doom_match_worker\.stop_match/);
assert.match(cleanup, /DOOM_EXPIRED_SESSION_PURGE/);
assert.match(cleanup, /FREQ=MINUTELY;INTERVAL=1/);

process.stdout.write('PASS SESSION-CLEANUP-STATIC cascade purge is bounded and off request path\n');
