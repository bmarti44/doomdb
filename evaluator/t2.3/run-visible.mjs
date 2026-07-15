import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import { deriveRng, directory, loadJson, readPinnedWad, sha256, texturePatches, wadFacts } from './wad-oracle.mjs';

const root = path.resolve(import.meta.dirname, '../..');
const expected = loadJson(path.join(import.meta.dirname, 'expectations.json'));
const files = {
  defs: 'tools/wad/engine-defs.json',
  closure: 'tools/wad/asset-closure.json',
  animations: 'tools/wad/animation-groups.json',
  rng: 'tools/wad/rng-table.json',
  sources: 'reports/t2.3-behavior-sources.md',
};
for (const relative of Object.values(files)) assert.ok(fs.existsSync(path.join(root, relative)), `T2.3 implementation file missing: ${relative}`);

const defs = loadJson(path.join(root, files.defs));
const closure = loadJson(path.join(root, files.closure));
const animations = loadJson(path.join(root, files.animations));
const rng = loadJson(path.join(root, files.rng));
const sourceReport = fs.readFileSync(path.join(root, files.sources), 'utf8');
const wad = readPinnedWad(path.join(root, 'vendor/freedoom/0.13.0/freedoom-0.13.0.zip'));
const facts = wadFacts(wad);
const rows = directory(wad);
const lumpNames = new Set(rows.map((row) => row.name));
const textureMap = texturePatches(wad);

const sortedNumbers = (values) => [...values].map(Number).sort((a, b) => a - b);
const exactIds = (actual, expectedIds, label, key = 'id') => {
  assert.deepEqual(sortedNumbers(actual.map((row) => row[key])), sortedNumbers(expectedIds), `${label} id closure mismatch`);
  assert.equal(new Set(actual.map((row) => row[key])).size, actual.length, `${label} contains duplicate ids`);
};
const noPlaceholder = (value, label) => assert.doesNotMatch(String(value), /unknown|todo|tbd|placeholder|unimplemented/i, `${label} is a placeholder`);

assert.equal(sha256(wad), expected.wadSha256);
assert.deepEqual(facts.thingCounts, expected.placedThingCounts);
assert.deepEqual(facts.linedefSpecialCounts, expected.linedefSpecialCounts);
assert.deepEqual(facts.sectorSpecialCounts, expected.sectorSpecialCounts);
assert.deepEqual(facts.wallTextures, expected.wallTextures);
assert.deepEqual(facts.flats, expected.flats);
assert.equal(defs.wad.sha256, expected.wadSha256);
assert.equal(defs.wad.map, 'E1M1');

assert.equal(defs.schema, 1);
for (const key of ['sources','thingTypes','linedefSpecials','sectorSpecials','weapons','pickups','states']) assert.ok(Array.isArray(defs[key]), `engine-defs.${key} must be an array`);
exactIds(defs.thingTypes, Object.keys(expected.placedThingCounts), 'thing type');
const sources = new Map();
for (const source of defs.sources) {
  assert.ok(source.id && source.title && source.url && source.license && source.usage, 'source metadata is incomplete');
  assert.equal(source.copiedCodeOrData, false, `${source.id}: copied code/data is forbidden`);
  assert.equal(sources.has(source.id), false, `duplicate source id ${source.id}`);
  sources.set(source.id, source);
}
const validateSources = (row, label) => {
  assert.ok(Array.isArray(row.sourceIds) && row.sourceIds.length > 0, `${label}: sourceIds required`);
  for (const id of row.sourceIds) assert.ok(sources.has(id), `${label}: unknown source ${id}`);
};

const thingById = new Map(defs.thingTypes.map((row) => [row.id, row]));
for (const thing of defs.thingTypes) {
  assert.ok(Number.isInteger(thing.id) && thing.name && thing.category, `thing ${thing.id}: identity incomplete`);
  noPlaceholder(thing.name, `thing ${thing.id} name`);
  noPlaceholder(thing.category, `thing ${thing.id} category`);
  validateSources(thing, `thing ${thing.id}`);
  assert.deepEqual([thing.name, thing.category], expected.thingIdentities[thing.id], `thing ${thing.id}: identity/role mismatch`);
  if (thing.spawnState === null) assert.equal(thing.category, 'spawn_marker', `thing ${thing.id}: only spawn markers may omit state`);
  else assert.ok(typeof thing.spawnState === 'string' && thing.spawnState, `thing ${thing.id}: spawnState required`);
}

const stateById = new Map();
for (const state of defs.states) {
  assert.ok(state.id && !stateById.has(state.id), `state id missing/duplicate: ${state.id}`);
  assert.ok(Number.isInteger(state.tics) && state.tics >= -1, `${state.id}: invalid tics`);
  assert.ok(state.action, `${state.id}: action required`);
  noPlaceholder(state.action, `${state.id} action`);
  validateSources(state, `state ${state.id}`);
  if (state.tics === -1) assert.equal(state.next, null, `${state.id}: terminal state next must be null`);
  else assert.ok(typeof state.next === 'string' && state.next, `${state.id}: timed state needs next`);
  assert.ok(state.sprite && /^[A-Z0-9]{4}$/.test(state.sprite.prefix), `${state.id}: invalid sprite prefix`);
  assert.match(state.sprite.frame, /^[A-Z]$/, `${state.id}: invalid sprite frame`);
  assert.ok(['0','ALL'].includes(state.sprite.rotations), `${state.id}: invalid rotation contract`);
  stateById.set(state.id, state);
}
for (const state of defs.states) if (state.next !== null) assert.ok(stateById.has(state.next), `${state.id}: unresolved next ${state.next}`);

for (const type of expected.interactiveMonsterTypes) {
  const monster = thingById.get(type);
  assert.equal(monster.category, 'monster', `thing ${type}: interactive monster category required`);
  assert.ok(Number.isInteger(monster.health) && monster.health > 0, `thing ${type}: positive health required`);
  for (const key of ['seeState','attackState','painState','deathState']) assert.ok(stateById.has(monster[key]), `thing ${type}: unresolved ${key}`);
  assert.ok(Array.isArray(monster.sounds) && monster.sounds.length > 0, `thing ${type}: sounds required`);
  const behavior = expected.monsterBehavior[type];
  assert.equal(monster.health, behavior.health, `thing ${type}: health mismatch`);
  assert.equal(monster.dropType ?? null, behavior.dropType, `thing ${type}: drop mismatch`);
  if (monster.dropType !== null && monster.dropType !== undefined) assert.ok(thingById.has(monster.dropType), `thing ${type}: unresolved drop type`);
  if (behavior.flags) for (const flag of behavior.flags) assert.ok(monster.flags?.includes(flag), `thing ${type}: missing ${flag}`);
}

exactIds(defs.linedefSpecials, Object.keys(expected.linedefSpecialCounts), 'linedef special');
exactIds(defs.sectorSpecials, Object.keys(expected.sectorSpecialCounts), 'sector special');
for (const row of defs.linedefSpecials) {
  assert.deepEqual(row.semantics, expected.linedefSemantics[row.id], `linedef special ${row.id}: semantics mismatch`);
  validateSources(row, `linedef special ${row.id}`);
}
for (const row of defs.sectorSpecials) {
  assert.deepEqual(row.semantics, expected.sectorSemantics[row.id], `sector special ${row.id}: semantics mismatch`);
  validateSources(row, `sector special ${row.id}`);
}

assert.deepEqual([...defs.weapons.map((row) => row.id)].sort(), [...expected.weapons].sort(), 'weapon closure mismatch');
assert.equal(new Set(defs.weapons.map((row) => row.id)).size, defs.weapons.length, 'duplicate weapon id');
for (const weapon of defs.weapons) {
  validateSources(weapon, `weapon ${weapon.id}`);
  for (const key of ['readyState','fireState','refireState','flashState']) assert.ok(stateById.has(weapon[key]), `${weapon.id}: unresolved ${key}`);
  assert.ok(typeof weapon.ammoType === 'string' && weapon.ammoType, `${weapon.id}: ammoType required (NONE is explicit)`);
  assert.ok(Array.isArray(weapon.sounds), `${weapon.id}: sounds array required`);
  assert.equal(weapon.ammoType, expected.weaponBehavior[weapon.id].ammoType, `${weapon.id}: ammo contract mismatch`);
}
for (const [thingType, weapon] of Object.entries(expected.weaponThingTypes)) {
  assert.equal(defs.weapons.find((row) => row.id === weapon)?.thingType, Number(thingType), `${weapon}: placed thing mapping mismatch`);
}

exactIds(defs.pickups, expected.pickupThingTypes, 'pickup', 'thingType');
for (const pickup of defs.pickups) {
  validateSources(pickup, `pickup ${pickup.thingType}`);
  assert.equal(pickup.consume, true, `pickup ${pickup.thingType}: must consume on successful pickup`);
  assert.ok(pickup.effect && typeof pickup.effect === 'object' && Object.keys(pickup.effect).length > 0, `pickup ${pickup.thingType}: concrete effect required`);
  assert.equal(pickup.effect.id, expected.pickupEffects[pickup.thingType], `pickup ${pickup.thingType}: effect mismatch`);
  assert.match(pickup.sound, /^DS[A-Z0-9]+$/, `pickup ${pickup.thingType}: sound required`);
}

const assetByKey = new Map();
assert.equal(closure.schema, 1);
assert.equal(closure.wadSha256, expected.wadSha256);
assert.equal(closure.map, 'E1M1');
assert.ok(Array.isArray(closure.assets) && closure.assets.length > 0, 'closure assets required');
for (const asset of closure.assets) {
  const key = `${asset.kind}:${asset.name}`;
  assert.equal(assetByKey.has(key), false, `duplicate closure asset ${key}`);
  assert.ok(['wall_texture','flat','patch','sprite_patch','sound','music','ui_patch'].includes(asset.kind), `${key}: invalid kind`);
  assert.ok(Array.isArray(asset.reasons) && asset.reasons.length > 0, `${key}: closure reason required`);
  assert.ok(Array.isArray(asset.sourceLumps) && asset.sourceLumps.length > 0, `${key}: sourceLumps required`);
  assert.ok(asset.sourceLumps.every((name) => lumpNames.has(name)), `${key}: source lump is absent from pinned WAD`);
  assetByKey.set(key, asset);
}
for (const name of expected.wallTextures) {
  const asset = assetByKey.get(`wall_texture:${name}`);
  assert.ok(asset, `map wall texture absent from closure: ${name}`);
  assert.deepEqual(asset.sourceLumps, textureMap.get(name), `${name}: exact patch dependency mismatch`);
  for (const patch of textureMap.get(name)) assert.ok(assetByKey.has(`patch:${patch}`), `${name}: unresolved patch node ${patch}`);
}
for (const name of expected.flats) assert.ok(assetByKey.has(`flat:${name}`), `map flat absent from closure: ${name}`);

const spriteLumps = (sprite) => {
  if (sprite.rotations === '0') return [`${sprite.prefix}${sprite.frame}0`];
  const matches = [...lumpNames].filter((name) => name.startsWith(sprite.prefix) && [...name.slice(4).matchAll(/([A-Z])([0-8])/g)].some((pair) => pair[1] === sprite.frame));
  const covered = new Set();
  for (const name of matches) for (const pair of name.slice(4).matchAll(/([A-Z])([0-8])/g)) if (pair[1] === sprite.frame) covered.add(pair[2]);
  assert.deepEqual([...covered].sort(), ['1','2','3','4','5','6','7','8'], `${sprite.prefix}${sprite.frame}: rotations 1-8 incomplete`);
  return matches.sort();
};
for (const state of defs.states) {
  for (const lump of spriteLumps(state.sprite)) assert.ok(assetByKey.has(`sprite_patch:${lump}`), `${state.id}: sprite closure missing ${lump}`);
  if (state.sound) assert.ok(assetByKey.has(`sound:${state.sound}`), `${state.id}: sound closure missing ${state.sound}`);
}
for (const [type, prefix] of Object.entries(expected.requiredSpritePrefixes)) {
  const roots = [thingById.get(Number(type)).spawnState, thingById.get(Number(type)).seeState].filter(Boolean);
  assert.ok(roots.some((id) => stateById.get(id)?.sprite.prefix === prefix), `thing ${type}: required sprite prefix ${prefix} not rooted`);
}

for (const name of expected.requiredSounds) assert.ok(assetByKey.has(`sound:${name}`), `required sound absent: ${name}`);
for (const name of expected.requiredMusic) assert.ok(assetByKey.has(`music:${name}`), `required music absent: ${name}`);
for (const name of expected.requiredUi) assert.ok(assetByKey.has(`ui_patch:${name}`), `required UI patch absent: ${name}`);

assert.equal(animations.schema, 1);
assert.deepEqual(animations.groups, expected.animationGroups);
for (const group of animations.groups) for (const frame of group.frames) assert.ok(assetByKey.has(`${group.kind}:${frame}`), `${group.id}: frame absent from closure ${frame}`);

assert.equal(rng.schema, 1);
assert.equal(rng.algorithm, 'PROJECT_TABLE_V1');
assert.equal(rng.derivation, expected.rng.derivation);
assert.equal(rng.cursorRule, 'read values[cursor], then persist (cursor + 1) modulo 256 for every gameplay random read');
assert.deepEqual(rng.values, deriveRng());
assert.equal(sha256(Buffer.from(rng.values)), expected.rng.sha256);
assert.equal(new Set(rng.values).size, expected.rng.uniqueValues);
assert.equal(rng.values.reduce((sum, value) => sum + value, 0), expected.rng.sum);

const walk = (rootState, label) => {
  const visited = new Set();
  let stateId = rootState;
  while (stateId !== null && !visited.has(stateId)) {
    const state = stateById.get(stateId);
    assert.ok(state, `${label}: unresolved state ${stateId}`);
    visited.add(stateId);
    stateId = state.next;
  }
  assert.ok(visited.size > 0, `${label}: empty state graph`);
};
const actionsReachable = (rootState) => {
  const actions = new Set();
  const visited = new Set();
  let stateId = rootState;
  while (stateId !== null && !visited.has(stateId)) {
    const state = stateById.get(stateId);
    assert.ok(state, `unresolved action graph state ${stateId}`);
    visited.add(stateId);
    actions.add(state.action);
    stateId = state.next;
  }
  return actions;
};
for (const thing of defs.thingTypes) if (thing.spawnState !== null) walk(thing.spawnState, `thing ${thing.id}`);
for (const weapon of defs.weapons) for (const key of ['readyState','fireState','refireState','flashState']) walk(weapon[key], `weapon ${weapon.id}.${key}`);
for (const type of expected.interactiveMonsterTypes) {
  const actions = actionsReachable(thingById.get(type).attackState);
  for (const action of expected.monsterBehavior[type].attackActions) assert.ok(actions.has(action), `thing ${type}: attack action ${action} unreachable`);
}
for (const weapon of defs.weapons) {
  const actions = actionsReachable(weapon.fireState);
  for (const action of expected.weaponBehavior[weapon.id].fireActions) assert.ok(actions.has(action), `${weapon.id}: fire action ${action} unreachable`);
}

for (const relative of [files.defs, files.closure, files.animations, files.rng]) {
  const bytes = fs.readFileSync(path.join(root, relative), 'utf8');
  assert.equal(bytes, `${JSON.stringify(JSON.parse(bytes), null, 2)}\n`, `${relative}: noncanonical JSON bytes`);
  noPlaceholder(bytes, relative);
  assert.doesNotMatch(bytes, /timestamp|generatedAt|sequenceValue|\bSCN\b/i, `${relative}: volatile field forbidden`);
}
assert.match(sourceReport, /Freedoom.*BSD-3-Clause/is, 'source report must document Freedoom BSD-3-Clause provenance');
assert.match(sourceReport, /independent|hand-authored/is, 'source report must document independent authorship');
assert.doesNotMatch(sourceReport, /copied|translated|transpiled|mechanically generated from (?:id|doom)/i, 'source report claims forbidden reuse');

process.stdout.write('PASS T2.3-VISIBLE (16/16 test ids)\n');
