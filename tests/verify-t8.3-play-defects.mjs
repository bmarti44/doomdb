import assert from 'node:assert/strict';
import fs from 'node:fs';

const read = name => fs.readFileSync(new URL(`../${name}`, import.meta.url), 'utf8');
const plan = read('PLAN.md');
const client = read('client/src/main.ts');
const audio = read('client/src/audio.ts');
const masked = read('sql/render/r2/030_masked.sql');
const presentation = read('sql/render/r2/040_presentation.sql');
const fireball = read('sql/accel/014_imp_fireball_asset.sql');
const combat = read('sql/sim/050_combat_inventory.sql');
const ticTransaction = read('sql/sim/tic/010_tic_transaction.sql');
const worker = read('scripts/performance/DoomUnifiedActorStateBench.java');
const renderer = read('scripts/performance/DoomBspKernelBench.java');
const exitRoute = read('artifacts/t8.1-live/route-exit-completion.sql');

for (const phrase of ['monsters blinking', 'missing gun animation',
  'key event to submitted ticcmd', 'correlate every health decrement']) {
  assert.ok(plan.includes(phrase), `missing reproduction task: ${phrase}`);
}
assert.match(masked, /substr\(asset\.asset_name,1,4\)=state_rotations\.sprite_prefix/i,
  'state transitions require a same-sprite authored fallback');
assert.match(fireball, /'sprite_patch','BAL1A0'/i,
  'the live imp projectile must use its real Freedoom patch');
assert.match(presentation, /player\.weapon_state/i);
assert.match(presentation, /d\.sprite_prefix\|\|d\.sprite_frame\|\|'0'/i);
assert.match(renderer, /weaponStateAsset\(selectedWeapon,weaponState\)/,
  'retained frames must render the database-authored weapon state');
assert.match(audio, /enqueue\(events: AudioTuple\[\]/);
assert.equal((client.match(/await audio\.consume\(frame\.audio\)/g) ?? []).length, 1,
  'only the one-time boot frame may await audio initialization');
assert.match(client, /audio\.enqueue\(frame\.audio/,
  'steady-state asset fetch/decode must not block canvas presentation');
assert.match(client, /const submitDepth = 4;/,
  'live input must use the reviewed depth-4 scheduler');
assert.match(client, /Press R or click this message to restart/,
  'a stopped pipeline must not look like dead keyboard input');
assert.match(combat, /m\.mobj_id<>projectile\.owner_mobj_id/i,
  'SQL projectile collision must exclude its owner');
assert.match(worker, /o\.world\.id\[candidate\]==o\.world\.owner\[slot\]/,
  'retained projectile collision must exclude its owner');
assert.match(combat, /damage_player\(p_session,p_tic,l_player,d\.damage,projectile\.mobj_id\)/i);
assert.match(worker, /damagePlayer\(o,o\.projectileDamage\[def\],projectileId,events\)/);
assert.doesNotMatch(combat, /owner is the exact depth-zero winner/i);
assert.match(combat,
  /function first_blocking_depth\(\s*p_session varchar2[\s\S]*?left join sector_state srs on srs\.session_token=p_session[\s\S]*?left join sector_state sls on sls\.session_token=p_session/i,
  'player hitscan/projectile blockers must use the same live door heights as monster LOS');
assert.match(combat,
  /first_blocking_depth\(p_session,l_x,l_y,[\s\S]*?first_blocking_depth\(p_session,projectile\.x/i,
  'both hitscan and projectile paths must carry the active session into live geometry');
assert.match(exitRoute, /linedef_id = 407[\s\S]*?completion_events = 1[\s\S]*?exit_triggers = 1/i,
  'the public route must prove the real E1M1 exit switch fired exactly once');
assert.match(exitRoute,
  /k_state_sha constant varchar2\(64\)[\s\S]*?ac5d82cba9ab641192e91e02dc6856dd9210dc57b4b7fad156bab0b40373b7e6/i,
  'the live-door combat route must retain its exact completion state identity');
assert.match(ticTransaction,
  /set game_mode='INTERMISSION',map_status='DONE'[\s\S]*?doom_canonical_state\.build_into_locator/i,
  'the exit-causing command must enter intermission before canonical capture');
assert.match(ticTransaction,
  /set game_mode='DEAD'[\s\S]*?if sql%rowcount=0 then[\s\S]*?set game_mode='INTERMISSION'/i,
  'death must take precedence over exit on a simultaneous terminal tic');

process.stdout.write('PASS T8.3-PLAY-DEFECT-SOURCE (reproductions, actor/weapon presentation, nonblocking audio, projectile ownership, live door fire geometry, E1M1 intermission route)\n');
