import assert from 'node:assert/strict';
import fs from 'node:fs';

const api = fs.readFileSync(new URL('../sql/rest/010_doom_api.sql', import.meta.url), 'utf8');
const cleanup = fs.readFileSync(new URL('../sql/sim/085_session_cleanup.sql', import.meta.url), 'utf8');
const liveGate = fs.readFileSync(
  new URL('./verify-session-cleanup-live.sql', import.meta.url), 'utf8');
const liveRunner = fs.readFileSync(
  new URL('./run-session-cleanup-live.sh', import.meta.url), 'utf8');
const body = api.indexOf('create or replace package body doom_api');
const start = api.indexOf('  procedure new_game(', body);
const newGame = api.slice(start, api.indexOf('  procedure step(', start));

assert.doesNotMatch(newGame,
  /delete from game_sessions where session_token in\s*\(\s*select session_token[\s\S]*expires_at/i,
  'NEW_GAME must never cascade previously expired lineage storage');
assert.match(cleanup, /create or replace package doom_session_cleanup/i);
assert.match(cleanup, /fetch first l_limit rows only/i);
assert.match(cleanup, /doom_unified_worker\.request_stop/);
assert.match(cleanup, /user_scheduler_running_jobs/);
assert.match(cleanup, /doom_worker_lifecycle\.stop_job\(/);
assert.doesNotMatch(cleanup, /dbms_scheduler\.stop_job\(/);
assert.match(cleanup, /expired owner reclaimed/);
assert.match(cleanup, /procedure purge_expired_matches/);
assert.match(cleanup, /procedure reap_abandoned_matches/);
assert.match(cleanup,
  /host_\.last_seen_at<\s*l_now-numtodsinterval\(15,'SECOND'\)/);
assert.match(cleanup,
  /host_\.member_state='LEFT' or host_\.last_seen_at</,
  'already-LEFT host must remain an abandoned-match cleanup candidate');
assert.match(cleanup,
  /update doom_match_worker_control set stop_requested=1,heartbeat=l_now/);
assert.match(cleanup,
  /update doom_match_standby_control set stop_requested=1,heartbeat=l_now/);
assert.match(cleanup, /delete from doom_match where match_id=expired_\.match_id/);
assert.match(cleanup, /doom_match_worker\.stop_match/);
assert.match(cleanup, /l_job like 'DOOM_MLE_WARM\\_%' escape '\\'/);
assert.match(cleanup,
  /select count\(\*\) into l_assigned from doom_mle_warm_slot[\s\S]+assigned_match=expired_\.match_id/);
assert.match(cleanup, /if l_assigned<>0 then[\s\S]+rollback;[\s\S]+continue;/);
assert.match(cleanup, /else[\s\S]+dbms_scheduler\.drop_job\(l_job,true\)/);
assert.match(cleanup, /DOOM_EXPIRED_SESSION_PURGE/);
assert.match(cleanup,
  /doom_session_cleanup\.reap_abandoned_matches\(4\)/);
assert.match(cleanup, /FREQ=MINUTELY;INTERVAL=1/);
assert.match(api,
  /doom_session_cleanup\.reap_abandoned_matches\(4\)/);
assert.match(api,
  /expires_at=l_now\+numtodsinterval\(5,'MINUTE'\)/,
  'host leave must retain terminal evidence without retaining its slot');
assert.match(api,
  /if l_member_state='LEFT' then[\s\S]+if l_slot=0 and l_state='ACTIVE' then[\s\S]+doom_match_worker\.stop_match\(p_match,l_generation\)/,
  'idempotent host leave must repair LEFT/ACTIVE retained-slot orphans');
assert.match(api,
  /case when l_state in\('FINISHED','CANCELLED','TERMINATED'\)[\s\S]+then 1 else 0 end/,
  'terminal MATCH_STATUS must accept the retained leaving capability');
assert.match(api,
  /return player_capability_slot\(p_match,p_capability,p_include_left\)/,
  'terminal status authentication must flow through the explicit LEFT fence');
assert.match(liveGate,
  /ABANDONED ACTIVE[\s\S]+member_state='LEFT'[\s\S]+doom_session_cleanup\.reap_abandoned_matches\(1\)/);
assert.match(liveGate,
  /where assigned_match=l_match[\s\S]+if l_assigned<>0 then[\s\S]+retained slot/);
assert.match(liveGate,
  /slot_status='READY' and assigned_match is null[\s\S]+slot was not reusable/);
assert.match(liveGate,
  /PASS SESSION-CLEANUP-LIVE left-host active orphan releases retained slot/);
assert.match(liveRunner,/refusing to overwrite session-cleanup evidence/);
assert.match(liveRunner,
  /PASS SESSION-CLEANUP-LIVE left-host active orphan releases retained slot/);

process.stdout.write('PASS SESSION-CLEANUP-STATIC cascade purge is bounded and off request path\n');
