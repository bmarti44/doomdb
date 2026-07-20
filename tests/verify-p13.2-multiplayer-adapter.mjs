import assert from 'node:assert/strict';
import fs from 'node:fs';

const adapter = fs.readFileSync(new URL(
  '../java/mochadoom-ojvm/src/doomdb/mocha/DoomDbMochaAdapter.java',
  import.meta.url), 'utf8');
const calls = fs.readFileSync(new URL(
  '../sql/accel/030_mochadoom_calls.sql', import.meta.url), 'utf8');

for (const entrypoint of [
  'multiplayerNewGamePayloadsSafe', 'multiplayerStepPayloadsSafe',
  'multiplayerReconstructPayloadsSafe'
]) {
  assert.match(adapter, new RegExp(`public static synchronized String ${entrypoint}\\(`));
  const body = adapter.slice(adapter.indexOf(entrypoint),
    adapter.indexOf('\n  }', adapter.indexOf(entrypoint)) + 4);
  assert.match(body, /catch \(Throwable failure\)/,
    `${entrypoint} must contain a catch-all`);
}
assert.match(adapter, /engine\.gametic != beforeTic \+ 1/);
assert.match(adapter, /engine\.leveltime != beforeLevelTime \+ 1/);
assert.match(adapter, /inactive player command/);
assert.match(adapter, /command\.consistancy = multiplayerConsistency\[player\]\[buffer\]/);
assert.match(adapter, /multiplayerConsistency\[player\]\[consistencyBuffer\] = consistencyBefore\[player\]/);
assert.match(adapter, /engine\.consoleplayer = savedConsole/);
assert.match(adapter, /engine\.displayplayer = savedDisplay/);
assert.match(adapter, /POV render mutated world/);
assert.match(adapter, /MULTI_INITIAL/);
assert.match(adapter, /previousStateSha \+ '\|' \+ membership/);
assert.match(calls, /create or replace function doom_mocha_multiplayer_new_game/i);
assert.match(calls, /create or replace function doom_mocha_multiplayer_step/i);
assert.match(calls, /create or replace function doom_mocha_multiplayer_reconstruct/i);

process.stdout.write(
  'PASS P13.2-MULTIPLAYER-ADAPTER-SOURCE one world tic, ordered vector, immutable POVs, catch-all\n');
