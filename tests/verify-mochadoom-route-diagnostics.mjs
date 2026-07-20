import assert from 'node:assert/strict';
import fs from 'node:fs';

const source = fs.readFileSync(new URL(
  '../java/mochadoom-ojvm/src/doomdb/mocha/DoomDbMochaAdapter.java',
  import.meta.url), 'utf8');

assert.match(source, /\|nearby=" \+ nearbyMobjs\(player\)/);
assert.match(source, /1024L \* 1024L/);
assert.match(source, /Math\.min\(24, nearby\.size\(\)\)/);
assert.match(source, /examined > 8192/);
assert.match(source, /MF_SPECIAL \| mobj_t\.MF_SHOOTABLE/);
assert.match(source, /mobj_t\.MF_MISSILE/);
assert.match(source, /Collections\.sort\(nearby/);

process.stdout.write('PASS MOCHADOOM-ROUTE-DIAGNOSTICS bounded filtered distance ordering\n');
