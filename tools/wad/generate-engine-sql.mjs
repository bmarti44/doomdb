#!/usr/bin/env node
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const here = path.dirname(fileURLToPath(import.meta.url));
const root = path.resolve(here, '../..');
const output = process.argv[2] ? path.resolve(process.argv[2]) : path.join(root, 'sql/engine/010_engine_defs.sql');
const defs = JSON.parse(fs.readFileSync(path.join(here, 'engine-defs.json'), 'utf8'));
const rng = JSON.parse(fs.readFileSync(path.join(here, 'rng-table.json'), 'utf8'));
const q = value => value == null ? 'NULL' : `'${String(value).replaceAll("'", "''")}'`;
const n = value => value == null ? 'NULL' : String(value);
const batches = (rows, render) => {
  const out = [];
  for (let i = 0; i < rows.length; i += 500) {
    out.push('INSERT ALL');
    for (const row of rows.slice(i, i + 500)) out.push(`  ${render(row)}`);
    out.push('SELECT 1 FROM DUAL;');
  }
  return out;
};

const lines = [
  '-- Generated deterministically from tools/wad/engine-defs.json and rng-table.json.',
  ...batches(defs.sources, s => `INTO DOOM_ENGINE_SOURCE (SOURCE_ID,TITLE,SOURCE_URL,LICENSE_NAME) VALUES (${q(s.id)},${q(s.title)},${q(s.url)},${q(s.license)})`),
  ...batches([{id: 0, semantics: ['NONE']}, ...defs.linedefSpecials], s => `INTO DOOM_LINEDEF_SPECIAL_DEF (SPECIAL_ID,SEMANTICS) VALUES (${n(s.id)},${q(s.semantics.join('|'))})`),
  ...batches([{id: 0, semantics: ['NONE']}, ...defs.sectorSpecials], s => `INTO DOOM_SECTOR_SPECIAL_DEF (SPECIAL_ID,SEMANTICS) VALUES (${n(s.id)},${q(s.semantics.join('|'))})`),
  ...batches(defs.states, s => `INTO DOOM_STATE_DEF (STATE_ID,TICS,NEXT_STATE_ID,ACTION_NAME,SPRITE_PREFIX,SPRITE_FRAME,ROTATIONS) VALUES (${q(s.id)},${n(s.tics)},${q(s.next)},${q(s.action)},${q(s.sprite?.prefix)},${q(s.sprite?.frame)},${q(s.sprite?.rotations)})`),
  ...batches(defs.thingTypes, t => `INTO DOOM_THING_TYPE_DEF (THING_TYPE,TYPE_NAME,CATEGORY,SPAWN_STATE_ID,RADIUS,HEIGHT,SPAWN_HEALTH,FLAGS) VALUES (${n(t.id)},${q(t.name)},${q(t.category)},${q(t.spawnState)},${n(t.radius)},${n(t.height)},${n(t.health)},0)`),
  ...batches(defs.weapons, (w, i) => `INTO DOOM_WEAPON_DEF (WEAPON_ID,SLOT_NUMBER,THING_TYPE,AMMO_TYPE,READY_STATE_ID,FIRE_STATE_ID,REFIRE_STATE_ID,FLASH_STATE_ID) VALUES (${q(w.id)},${n(defs.weapons.indexOf(w) + 1)},${n(w.thingType)},${q(w.ammoType)},${q(w.readyState)},${q(w.fireState)},${q(w.refireState)},${q(w.flashState)})`),
  ...batches(defs.pickups, p => `INTO DOOM_PICKUP_DEF (THING_TYPE,PICKUP_KIND,AMOUNT,CAP,GRANTS_WEAPON_ID,GRANTS_KEY) VALUES (${n(p.thingType)},${q(p.effect.id)},NULL,NULL,NULL,${p.effect.id.includes('BLUE_KEY') ? q('BLUE') : p.effect.id.includes('YELLOW_KEY') ? q('YELLOW') : p.effect.id.includes('RED_KEY') ? q('RED') : 'NULL'})`),
  ...batches(rng.values.map((value, index) => ({index, value})), r => `INTO DOOM_RNG_VALUE (RNG_INDEX,RNG_VALUE) VALUES (${r.index},${r.value})`),
  'COMMIT;',
  ''
];
fs.mkdirSync(path.dirname(output), { recursive: true });
fs.writeFileSync(output, lines.join('\n'), 'ascii');
