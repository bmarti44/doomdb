#!/usr/bin/env node

import assert from 'node:assert/strict';

const root = new URL(process.env.DOOMDB_ORDS_BASE_URL
  ?? 'http://localhost:8080/ords/doom/doom_api/');
const frames = Number.parseInt(
  process.env.DOOMDB_TWO_POV_PRODUCER_FRAMES ?? '300', 10);
assert.ok(Number.isInteger(frames) && frames >= 100 && frames <= 10_000);
const observeOnlySeconds = Number.parseInt(
  process.env.DOOMDB_TWO_POV_OBSERVE_ONLY_SECONDS ?? '0', 10);
const observeWarmupSeconds = Number.parseInt(
  process.env.DOOMDB_TWO_POV_OBSERVE_WARMUP_SECONDS ?? '0', 10);
const producerMode =
  (process.env.DOOMDB_FRAME_PRODUCER_MODE ?? 'COOP').toUpperCase();
assert.ok(Number.isInteger(observeOnlySeconds)
  && observeOnlySeconds >= 0 && observeOnlySeconds <= 300);
assert.ok(Number.isInteger(observeWarmupSeconds)
  && observeWarmupSeconds >= 0 && observeWarmupSeconds <= 300);
assert.ok(producerMode === 'COOP' || producerMode === 'SOLO');

async function post(path, body, expected = true) {
  const response = await fetch(new URL(path, root), {
    method: 'POST',
    headers: {'content-type': 'application/json'},
    body: JSON.stringify(body),
  });
  assert.equal(
    response.ok, expected, `${path} returned HTTP ${response.status}`);
  return expected ? response.json() : null;
}

async function waitActive(match, capability) {
  const deadline = performance.now() + 120_000;
  while (performance.now() < deadline) {
    const status = await post('MATCH_STATUS', {
      p_match: match, p_capability: capability,
    });
    if (status.p_match_state === 'ACTIVE') return status;
    assert.ok(!['FAILED','CANCELLED','TERMINATED'].includes(
      status.p_match_state), `match became ${status.p_match_state}`);
    await new Promise(resolve => setTimeout(resolve, 100));
  }
  assert.fail('two-POV producer match did not become active');
}

const created = await post('CREATE_MATCH', {
  p_game_mode: producerMode === 'SOLO' ? 'COOP' : producerMode,
  p_skill: 3,
  p_episode: 1,
  p_map: 1,
  p_display_name: 'PRODUCER HOST',
  p_max_players: producerMode === 'SOLO' ? 1 : 2,
});
const joined = producerMode === 'COOP'
  ? await post('JOIN_MATCH', {
    p_match: created.p_match,
    p_join_capability: created.p_join_capability,
    p_display_name: 'PRODUCER GUEST',
    p_player_capability: null,
  })
  : null;
let hostLeft = false;
let guestLeft = joined === null;
const touchPlayers = async () => {
  const touches = [
    post('TOUCH_MATCH_PRESENCE', {
      p_match: created.p_match,
      p_player_capability: created.p_player_capability,
    }),
  ];
  if (joined !== null) {
    touches.push(post('TOUCH_MATCH_PRESENCE', {
      p_match: created.p_match,
      p_player_capability: joined.p_player_capability,
    }));
  }
  await Promise.all(touches);
};
try {
  await post('READY_MATCH', {
    p_match: created.p_match,
    p_player_capability: created.p_player_capability,
    p_ready: 1,
  });
  if (joined !== null) {
    await post('READY_MATCH', {
      p_match: created.p_match,
      p_player_capability: joined.p_player_capability,
      p_ready: 1,
    });
  }
  const active = await waitActive(
    created.p_match, created.p_player_capability);
  if (observeOnlySeconds > 0) {
    let status = active;
    const warmupDeadline = performance.now() + observeWarmupSeconds * 1_000;
    while (performance.now() < warmupDeadline) {
      await touchPlayers();
      await new Promise(resolve => setTimeout(resolve, 1_000));
      status = await post('MATCH_STATUS', {
        p_match: created.p_match,
        p_capability: created.p_player_capability,
      });
    }
    const firstTic = status.p_current_tic;
    const started = performance.now();
    let ended = started;
    while (ended - started < observeOnlySeconds * 1_000) {
      await touchPlayers();
      await new Promise(resolve => setTimeout(resolve, 1_000));
      status = await post('MATCH_STATUS', {
        p_match: created.p_match,
        p_capability: created.p_player_capability,
      });
      ended = performance.now();
    }
    const lastTic = status.p_current_tic;
    const elapsedMs = ended - started;
    const fps = (lastTic - firstTic) * 1_000 / elapsedMs;
    process.stdout.write(
      `PMLE_TWO_POV_PRODUCER|DIAGNOSTIC_NOT_GATE|mode=OBSERVE_ONLY`
      + `|first_tic=${firstTic}|last_tic=${lastTic}`
      + `|elapsed_ms=${elapsedMs.toFixed(3)}|fps=${fps.toFixed(3)}`
      + `|warmup_seconds=${observeWarmupSeconds}`
      + `|generation=${active.p_generation}|game_mode=${producerMode}\n`);
  } else {
    let afterTic = -1;
    let firstTic = -1;
    let lastTic = -1;
    let received = 0;
    let firstAt = 0;
    let lastAt = 0;
    let nextPresenceAt = 0;
    while (received < frames) {
    const now = performance.now();
    if (now >= nextPresenceAt) {
      await touchPlayers();
      nextPresenceAt = performance.now() + 1_000;
    }
    const batch = await post('POLL_MATCH_PIXEL_BATCH', {
      p_match: created.p_match,
      p_player_capability: created.p_player_capability,
      p_after_tic: afterTic,
      p_max_frames: Math.min(8, frames - received),
    });
    if (batch.p_frame_count === 0) {
      await new Promise(resolve => setTimeout(resolve, 2));
      continue;
    }
    assert.equal(
      batch.p_first_tic, afterTic < 0 ? batch.p_first_tic : afterTic + 1,
      'producer stream skipped a tic');
    if (firstTic < 0) {
      firstTic = batch.p_first_tic;
      firstAt = performance.now();
    }
    received += batch.p_frame_count;
    lastTic = batch.p_last_tic;
    lastAt = performance.now();
    afterTic = lastTic;
    }
    const elapsedMs = lastAt - firstAt;
    const intervals = lastTic - firstTic;
    const fps = intervals * 1_000 / elapsedMs;
    process.stdout.write(
      `PMLE_TWO_POV_PRODUCER|DIAGNOSTIC_NOT_GATE|frames=${received}`
      + `|first_tic=${firstTic}|last_tic=${lastTic}`
      + `|elapsed_ms=${elapsedMs.toFixed(3)}|fps=${fps.toFixed(3)}`
      + `|generation=${active.p_generation}|mode=${producerMode}\n`);
  }
} finally {
  try {
    if (joined !== null) {
      await post('LEAVE_MATCH', {
        p_match: created.p_match,
        p_player_capability: joined.p_player_capability,
      });
      guestLeft = true;
    }
  } catch {}
  try {
    await post('LEAVE_MATCH', {
      p_match: created.p_match,
      p_player_capability: created.p_player_capability,
    });
    hostLeft = true;
  } catch {}
  if (!hostLeft || !guestLeft) {
    process.stderr.write(
      `producer cleanup incomplete host=${hostLeft} guest=${guestLeft}\n`);
  }
}
