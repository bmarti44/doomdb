#!/usr/bin/env node
import assert from 'node:assert/strict';
import fs from 'node:fs';

const worker = fs.readFileSync(new URL(
  '../sql/sim/084_multiplayer_worker.sql', import.meta.url), 'utf8');

function constant(name) {
  const match = worker.match(new RegExp(
    `${name} constant pls_integer:=(\\d+);`));
  assert.ok(match, `missing ${name}`);
  return Number(match[1]);
}

const minimum = constant('c_checkpoint_min_tics');
const maximum = constant('c_checkpoint_max_tics');
const probe = constant('c_checkpoint_probe_tics');
const lowAwake = constant('c_checkpoint_low_awake');

assert.equal(minimum, 128);
assert.equal(maximum, 256);
assert.equal(probe, 16);
assert.equal(lowAwake, 16);

function nextCheckpoint(last, awake) {
  for (let tic = last + 1; tic <= last + maximum; tic++) {
    if (tic % probe !== 0) continue;
    const distance = tic - last;
    if (distance >= maximum - probe + 1
        || (distance >= minimum && awake <= lowAwake)) return tic;
  }
  throw new Error(`no checkpoint from offset ${last}`);
}

for (let last = 0; last < maximum; last++) {
  const forcedDistance = nextCheckpoint(last, lowAwake + 1) - last;
  assert.ok(forcedDistance >= maximum - probe + 1,
    `forced checkpoint too early from ${last}: ${forcedDistance}`);
  assert.ok(forcedDistance <= maximum,
    `hard bound exceeded from ${last}: ${forcedDistance}`);

  const quietDistance = nextCheckpoint(last, lowAwake) - last;
  assert.ok(quietDistance >= minimum,
    `quiet checkpoint before minimum from ${last}: ${quietDistance}`);
  assert.ok(quietDistance < minimum + probe,
    `quiet opportunity missed from ${last}: ${quietDistance}`);
}

assert.doesNotMatch(worker,
  /p_tic\s*=\s*32\s+or|or\s+p_tic\s*=\s*32/,
  'obsolete production tic-32 checkpoint remains');
assert.match(worker,
  /Test scaffold only: CHECKPOINT_TEST_HOOK may force a tic-64 checkpoint/,
  'diagnostic tic-64 checkpoint is not explicitly fenced');
assert.match(worker,
  /p_checkpoint_test_hook=1 and p_tic=64/,
  'diagnostic tic-64 checkpoint is not controlled by its dedicated hook');
assert.doesNotMatch(worker,
  /p_diagnostics=1 and p_tic=64/,
  'route diagnostics still alter checkpoint placement');

process.stdout.write(
  `PASS PMLE-CHECKPOINT-CADENCE offsets=${maximum}`
  + ` minimum=${minimum} maximum=${maximum} probe=${probe}`
  + ` low_awake=${lowAwake}\n`);
