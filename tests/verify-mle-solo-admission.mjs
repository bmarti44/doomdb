import assert from 'node:assert/strict';

const root = new URL(process.env.DOOMDB_ORDS_BASE_URL ??
  'http://localhost:8080/ords/doom/doom_api/');

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
  p_game_mode: 'COOP',
  p_skill: 3,
  p_episode: 1,
  p_map: 1,
  p_display_name: 'SOLO ADMISSION GATE',
  p_max_players: 1,
});
assert.match(created.p_match, /^[0-9a-f]{32}$/);
assert.match(created.p_player_capability, /^[0-9a-f]{64}$/);

let left = false;
try {
  const ready = await post('READY_MATCH', {
    p_match: created.p_match,
    p_player_capability: created.p_player_capability,
    p_ready: 1,
  });
  assert.ok(['STARTING', 'ACTIVE'].includes(ready.p_match_state));
  let status;
  for (let attempt = 0; attempt < 240; attempt += 1) {
    status = await post('MATCH_STATUS', {
      p_match: created.p_match,
      p_capability: created.p_player_capability,
    });
    if (status.p_match_state === 'ACTIVE') break;
    await new Promise(resolve => setTimeout(resolve, 1000));
  }
  assert.equal(status?.p_match_state, 'ACTIVE');
  assert.ok(['WARMING', 'READY'].includes(status.p_recovery_status),
    `unexpected recovery status ${status?.p_recovery_status}`);
  process.stdout.write(
    `PMLE_SOLO_ADMISSION|PASS|elapsed_ms=${Math.round(performance.now()-started)}`
      + `|recovery_status=${status.p_recovery_status}`
      + `|generation=${status.p_generation}|tic=${status.p_current_tic}\n`,
  );
  const result = await post('LEAVE_MATCH', {
    p_match: created.p_match,
    p_player_capability: created.p_player_capability,
  });
  assert.ok(['FINISHED', 'TERMINATED'].includes(result.p_match_state));
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
