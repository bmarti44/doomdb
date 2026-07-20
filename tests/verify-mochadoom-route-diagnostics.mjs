import assert from 'node:assert/strict';
import fs from 'node:fs';

const source = fs.readFileSync(new URL(
  '../java/mochadoom-ojvm/src/doomdb/mocha/DoomDbMochaAdapter.java',
  import.meta.url), 'utf8');
const routeHelper = fs.readFileSync(new URL(
  '../scripts/mochadoom/public-session-route-tail.mjs', import.meta.url), 'utf8');
const clearanceHelper = fs.readFileSync(new URL(
  '../scripts/mochadoom/debug-clearance-route.mjs', import.meta.url), 'utf8');
const lineageExporter = fs.readFileSync(new URL(
  '../scripts/mochadoom/debug-export-lineage-route.sql', import.meta.url), 'utf8');

assert.match(source, /\|nearby=" \+ nearbyMobjs\(player\)/);
assert.match(source, /1024L \* 1024L/);
assert.match(source, /Math\.min\(24, nearby\.size\(\)\)/);
assert.match(source, /examined > 8192/);
assert.match(source, /MF_SPECIAL \| mobj_t\.MF_SHOOTABLE/);
assert.match(source, /mobj_t\.MF_MISSILE/);
assert.match(source, /Collections\.sort\(nearby/);
assert.match(source, /player\.ammo\[ammotype_t\.am_clip\.ordinal\(\)\]/);
assert.match(source, /player\.ammo\[ammotype_t\.am_shell\.ordinal\(\)\]/);
assert.match(routeHelper, /route\.startSequence \?\? 0/);
assert.match(routeHelper, /commands\[sequence - startSequence\]/);
assert.match(routeHelper, /cheat: command\.cheat \?\? ''/);
assert.match(routeHelper, /Never advance the local sequence without a correlated DMF3/);
assert.match(clearanceHelper, /input === '-' \? 0 : input/);
assert.match(lineageExporter, /r\.save_lineage='&&route_lineage'/);
assert.match(lineageExporter, /r\.expected_tic between &&route_from_tic and &&route_to_tic-1/);

process.stdout.write('PASS MOCHADOOM-ROUTE-DIAGNOSTICS bounded actors, clearance, lineage export, safe tails\n');
