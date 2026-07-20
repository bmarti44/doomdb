import assert from 'node:assert/strict';

const root = process.env.DOOMDB_ORDS_BASE_URL ??
  'http://localhost:8080/ords/doom/doom_api/';

async function post(path, body) {
  const response = await fetch(new URL(path, root), {
    method: 'POST',
    headers: {'content-type': 'application/json'},
    body: JSON.stringify(body)
  });
  // Never include a response body in failures: generated ORDS responses for
  // CREATE/JOIN legitimately contain bearer values.
  assert.equal(response.ok, true, `${path} returned HTTP ${response.status}`);
  return response.json();
}

const created = await post('CREATE_MATCH', {
  p_game_mode: 'COOP', p_skill: 3, p_episode: 1, p_map: 1,
  p_display_name: 'AUTOREST HOST'
});
assert.match(created.p_match, /^[0-9a-f]{32}$/);
assert.match(created.p_host_capability, /^[0-9a-f]{64}$/);
assert.match(created.p_join_capability, /^[0-9a-f]{64}$/);
assert.match(created.p_player_capability, /^[0-9a-f]{64}$/);

let guestCapability;
try {
  const joined = await post('JOIN_MATCH', {
    p_match: created.p_match,
    p_join_capability: created.p_join_capability,
    p_display_name: 'AUTOREST JOINER',
    p_player_capability: null
  });
  assert.equal(joined.p_player_slot, 1);
  assert.match(joined.p_player_capability, /^[0-9a-f]{64}$/);
  guestCapability = joined.p_player_capability;

  const retried = await post('JOIN_MATCH', {
    p_match: created.p_match,
    p_join_capability: created.p_join_capability,
    p_display_name: 'AUTOREST JOINER',
    p_player_capability: guestCapability
  });
  assert.equal(retried.p_player_slot, 1);
  assert.equal(retried.p_player_capability, guestCapability);

  const hostReady = await post('READY_MATCH', {
    p_match: created.p_match,
    p_player_capability: created.p_player_capability,
    p_ready: 1
  });
  assert.equal(hostReady.p_match_state, 'LOBBY');
  const hostStatus = await post('MATCH_STATUS', {
    p_match: created.p_match, p_capability: created.p_host_capability
  });
  assert.equal(hostStatus.p_match_state, 'LOBBY');
  assert.equal(hostStatus.p_requester_slot, -1);
  assert.equal(hostStatus.p_member_count, 2);
  assert.equal(hostStatus.p_ready_count, 1);
  assert.equal(hostStatus.p_generation, 0);
  assert.equal(hostStatus.p_current_tic, 0);
  const guestStatus = await post('MATCH_STATUS', {
    p_match: created.p_match, p_capability: guestCapability
  });
  assert.equal(guestStatus.p_requester_slot, 1);

  const guestLeft = await post('LEAVE_MATCH', {
    p_match: created.p_match, p_player_capability: guestCapability
  });
  assert.equal(guestLeft.p_match_state, 'LOBBY');
  const leaveRetry = await post('LEAVE_MATCH', {
    p_match: created.p_match, p_player_capability: guestCapability
  });
  assert.equal(leaveRetry.p_match_state, 'LOBBY');
  const cancelled = await post('LEAVE_MATCH', {
    p_match: created.p_match,
    p_player_capability: created.p_player_capability
  });
  assert.equal(cancelled.p_match_state, 'CANCELLED');
} catch (failure) {
  try {
    await post('LEAVE_MATCH', {
      p_match: created.p_match,
      p_player_capability: created.p_player_capability
    });
  } catch {}
  throw failure;
}

process.stdout.write(
  'PASS P13.1-MULTIPLAYER-AUTOREST two clients create/join/retry/one-ready/status/leave (bearers redacted)\n');
