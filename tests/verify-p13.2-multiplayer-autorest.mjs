import assert from 'node:assert/strict';
import fs from 'node:fs';

const root = process.env.DOOMDB_ORDS_BASE_URL ??
  'http://localhost:8080/ords/doom/doom_api/';

async function request(path, body, expected = true) {
  const response = await fetch(new URL(path, root), {
    method: 'POST', headers: {'content-type': 'application/json'},
    body: JSON.stringify(body)
  });
  assert.equal(response.ok, expected, `${path} returned HTTP ${response.status}`);
  // Never print response bodies: CREATE/JOIN contain bearer capabilities.
  return expected ? response.json() : null;
}

async function poll(match, capability, tic) {
  for (let attempt = 0; attempt < 5; attempt += 1) {
    const value = await request('POLL_MATCH_FRAME', {
      p_match: match, p_player_capability: capability,
      p_tic: tic, p_wait_ms: 1000
    });
    if (value.p_ready === 1) return value;
  }
  assert.fail(`tic ${tic} frame timed out`);
}

const created = await request('CREATE_MATCH', {
  p_game_mode: 'COOP', p_skill: 3, p_episode: 1, p_map: 1,
  p_display_name: 'HTTP STEP HOST'
});
assert.match(created.p_match, /^[0-9a-f]{32}$/);
if (process.env.DOOMDB_MATCH_ID_FILE) {
  fs.writeFileSync(process.env.DOOMDB_MATCH_ID_FILE, `${created.p_match}\n`,
    {encoding: 'ascii', mode: 0o600});
}
const joined = await request('JOIN_MATCH', {
  p_match: created.p_match, p_join_capability: created.p_join_capability,
  p_display_name: 'HTTP STEP GUEST', p_player_capability: null
});
await request('READY_MATCH', {
  p_match: created.p_match, p_player_capability: created.p_player_capability,
  p_ready: 1
});
const active = await request('READY_MATCH', {
  p_match: created.p_match, p_player_capability: joined.p_player_capability,
  p_ready: 1
});
assert.ok(['ACTIVE', 'STARTING'].includes(active.p_match_state));
if (active.p_match_state === 'STARTING') {
  let state = 'STARTING';
  for (let attempt = 0; attempt < 180 && state === 'STARTING'; attempt += 1) {
    await new Promise(resolve => setTimeout(resolve, 1000));
    const status = await request('MATCH_STATUS', {
      p_match: created.p_match,
      p_capability: created.p_player_capability
    });
    state = status.p_match_state;
  }
  assert.equal(state, 'ACTIVE', 'cold OJVM match worker did not become active');
}

const initial0 = await poll(created.p_match, created.p_player_capability, 0);
const initial1 = await poll(created.p_match, joined.p_player_capability, 0);
assert.equal(initial0.p_current_tic, 0);
assert.equal(Buffer.from(initial0.p_payload, 'base64').subarray(0, 4).toString(), 'DMF3');
assert.equal(initial0.p_payload, initial1.p_payload,
  'authentic tic-zero border payload is shared');

// Submit both independent keyboard-state commands concurrently, as the real
// two-browser client does. A sequential HTTP poll here can exceed the bounded
// 75 ms missing-peer deadline and correctly cause a neutral substitution.
const [guestSubmit, hostSubmit] = await Promise.all([
  request('SUBMIT_MATCH_STEP', {
    p_match: created.p_match, p_player_capability: joined.p_player_capability,
    p_tic: 1, p_command_seq: 1, p_ticcmd_hex: '00f8000000000000'
  }),
  request('SUBMIT_MATCH_STEP', {
    p_match: created.p_match, p_player_capability: created.p_player_capability,
    p_tic: 1, p_command_seq: 1, p_ticcmd_hex: '0800000000000000'
  })
]);
assert.equal(guestSubmit.p_accepted, 1);
assert.equal(hostSubmit.p_accepted, 1);
assert.equal(hostSubmit.p_membership_epoch, guestSubmit.p_membership_epoch);
assert.equal(hostSubmit.p_generation, guestSubmit.p_generation);
const frame0 = await poll(created.p_match, created.p_player_capability, 1);
const frame1 = await poll(created.p_match, joined.p_player_capability, 1);
const payload0 = Buffer.from(frame0.p_payload, 'base64');
const payload1 = Buffer.from(frame1.p_payload, 'base64');
assert.equal(payload0.subarray(0, 4).toString(), 'DMF3');
assert.equal(payload0.readUInt32BE(4), 1);
assert.equal(payload1.readUInt32BE(4), 1);
assert.notEqual(payload0.subarray(74, 138).toString('ascii'),
  payload1.subarray(74, 138).toString('ascii'));

const retry = await request('SUBMIT_MATCH_STEP', {
  p_match: created.p_match, p_player_capability: created.p_player_capability,
  p_tic: 1, p_command_seq: 1, p_ticcmd_hex: '0800000000000000'
});
assert.equal(retry.p_accepted, 1);
await request('SUBMIT_MATCH_STEP', {
  p_match: created.p_match, p_player_capability: 'f'.repeat(64),
  p_tic: 2, p_command_seq: 2, p_ticcmd_hex: '0000000000000000'
}, false);

process.stdout.write(
  'PASS P13.2-MULTIPLAYER-AUTOREST active/tic0/arbitrary-arrival/one-tic/two-POV/retry/auth (bearers redacted)\n');
