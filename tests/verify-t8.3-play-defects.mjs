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
const worker = read('scripts/performance/DoomUnifiedActorStateBench.java');
const renderer = read('scripts/performance/DoomBspKernelBench.java');

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
assert.match(combat, /m\.mobj_id<>projectile\.owner_mobj_id/i,
  'SQL projectile collision must exclude its owner');
assert.match(worker, /o\.world\.id\[candidate\]==o\.world\.owner\[slot\]/,
  'retained projectile collision must exclude its owner');
assert.match(combat, /damage_player\(p_session,p_tic,l_player,d\.damage,projectile\.mobj_id\)/i);
assert.match(worker, /damagePlayer\(o,o\.projectileDamage\[def\],projectileId,events\)/);
assert.doesNotMatch(combat, /owner is the exact depth-zero winner/i);

process.stdout.write('PASS T8.3-PLAY-DEFECT-SOURCE (reproductions, actor/weapon presentation, nonblocking audio, projectile ownership)\n');
