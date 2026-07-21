import assert from 'node:assert/strict';
import fs from 'node:fs';

const adapter = fs.readFileSync(new URL(
  '../java/mochadoom-ojvm/src/doomdb/mocha/DoomDbMochaAdapter.java',
  import.meta.url), 'utf8');
const calls = fs.readFileSync(new URL(
  '../sql/accel/030_mochadoom_calls.sql', import.meta.url), 'utf8');
const consistencyPatch = fs.readFileSync(new URL(
  '../patches/mochadoom/0008-ojvm-consistency-ring.patch', import.meta.url), 'utf8');

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
assert.match(adapter, /engine\.gamestate != defines\.gamestate_t\.GS_INTERMISSION/);
assert.match(adapter, /inactive player command/);
assert.match(adapter, /decodeMultiplayerCommand\(command, requested, offset,/);
assert.match(adapter, /command\.consistancy = consistency/);
assert.match(adapter, /private static void decodeMultiplayerCommand/);
assert.match(adapter, /command\.angleturn = \(short\) \(\(\(source\[offset \+ 2\]/);
assert.doesNotMatch(adapter, /command\.unpack\(requested, offset\)/);
assert.doesNotMatch(adapter, /command\.unpack\(vectors, offset\)/);
assert.match(adapter, /engine\.doomdbConsistency\(player, consistencyBuffer\)/);
assert.match(consistencyPatch, /public short doomdbConsistency/);
assert.match(adapter, /\|routeDiag=/);
assert.match(adapter, /private static String multiplayerRouteDiagnostic/);
assert.match(adapter, /engine\.consoleplayer = savedConsole/);
assert.match(adapter, /engine\.displayplayer = savedDisplay/);
assert.match(adapter, /POV render mutated world/);
assert.match(adapter, /co-op pickup contention failed/);
assert.match(adapter, /co-op shared key failed/);
assert.match(adapter, /simultaneous player actions failed/);
assert.match(adapter, /MULTI_INITIAL/);
assert.match(adapter, /previousStateSha \+ '\|' \+ membership/);
assert.match(calls, /create or replace function doom_mocha_multiplayer_new_game/i);
assert.match(calls, /create or replace function doom_mocha_multiplayer_step/i);
assert.match(calls, /p_membership_bitmap in number/i);
assert.match(adapter, /applyMultiplayerMembership\(activePlayers, membershipMask\)/);
assert.match(adapter, /vectors\.length % 33/);
assert.match(calls, /create or replace function doom_mocha_multiplayer_reconstruct/i);

process.stdout.write(
  'PASS P13.2-MULTIPLAYER-ADAPTER-SOURCE one world tic, ordered vector, immutable POVs, catch-all\n');
