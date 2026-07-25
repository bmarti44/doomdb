import assert from 'node:assert/strict';

const root = new URL(process.env.DOOMDB_ORDS_BASE_URL ??
  'http://localhost:8080/ords/doom/doom_api/');
const skill = Number(process.env.DOOMDB_TEST_SKILL ?? 3);
const gameMode = process.env.DOOMDB_TEST_MODE ?? 'COOP';
const pollCadenceMs = Number(process.env.DOOMDB_ADMISSION_POLL_MS ?? 100);
assert.ok(Number.isInteger(skill) && skill >= 1 && skill <= 5);
assert.ok(['COOP', 'DEATHMATCH'].includes(gameMode));
assert.ok(Number.isInteger(pollCadenceMs) && pollCadenceMs >= 10 &&
  pollCadenceMs <= 5000);

async function post(path, body) {
  const response = await fetch(new URL(path, root), {
    method: 'POST',
    headers: {'content-type': 'application/json'},
    body: JSON.stringify(body),
  });
  assert.equal(response.ok, true, `${path} returned HTTP ${response.status}`);
  return response.json();
}

const started = performance.now();
const created = await post('CREATE_MATCH', {
  p_game_mode: gameMode,
  p_skill: skill,
  p_episode: 1,
  p_map: 1,
  p_display_name: 'SOLO ADMISSION GATE',
  p_max_players: 1,
});
const createdAt = performance.now();
assert.match(created.p_match, /^[0-9a-f]{32}$/);
assert.match(created.p_player_capability, /^[0-9a-f]{64}$/);

let left = false;
try {
  const readyStarted = performance.now();
  const ready = await post('READY_MATCH', {
    p_match: created.p_match,
    p_player_capability: created.p_player_capability,
    p_ready: 1,
  });
  const readyAt = performance.now();
  assert.ok(['STARTING', 'ACTIVE'].includes(ready.p_match_state));
  let status;
  let activeElapsedMs;
  let readyToActiveMs;
  let polls = 0;
  let statusRequestMs = 0;
  for (let attempt = 0; attempt < 2400; attempt += 1) {
    const statusStarted = performance.now();
    status = await post('MATCH_STATUS', {
      p_match: created.p_match,
      p_capability: created.p_player_capability,
    });
    statusRequestMs += performance.now()-statusStarted;
    polls += 1;
    if (status.p_match_state === 'ACTIVE') {
      activeElapsedMs = Math.round(performance.now()-started);
      readyToActiveMs = Math.round(performance.now()-readyStarted);
      break;
    }
    await new Promise(resolve => setTimeout(resolve, pollCadenceMs));
  }
  assert.equal(status?.p_match_state, 'ACTIVE');
  assert.ok(['WARMING', 'READY', 'DEGRADED'].includes(status.p_recovery_status),
    `unexpected recovery status ${status?.p_recovery_status}`);
  process.stdout.write(
    `PMLE_SOLO_ADMISSION|PASS|ready_to_active_ms=${readyToActiveMs}`
      + `|elapsed_ms=${activeElapsedMs}`
      + `|recovery_status=${status.p_recovery_status}`
      + `|mode=${gameMode}|skill=${skill}`
      + `|generation=${status.p_generation}|tic=${status.p_current_tic}`
      + `|create_ms=${Math.round(createdAt-started)}`
      + `|ready_ms=${Math.round(readyAt-readyStarted)}`
      + `|status_ms=${Math.round(statusRequestMs)}|status_polls=${polls}`
      + `|poll_cadence_ms=${pollCadenceMs}\n`,
  );
  const result = await post('LEAVE_MATCH', {
    p_match: created.p_match,
    p_player_capability: created.p_player_capability,
  });
  assert.ok(['FINISHED', 'CANCELLED', 'TERMINATED'].includes(result.p_match_state));
  left = true;
} finally {
  if (!left) {
    try {
      await post('LEAVE_MATCH', {
        p_match: created.p_match,
        p_player_capability: created.p_player_capability,
      });
    } catch {}
  }
}
