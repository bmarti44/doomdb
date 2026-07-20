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
assert.match(routeHelper, /routePath === '-' \? 0 : routePath/);
assert.match(routeHelper, /routeText\.startsWith\('BASE64:'\)/);
assert.match(routeHelper, /Never advance the local sequence without a correlated DMF3/);
assert.match(clearanceHelper, /input === '-' \? 0 : input/);
assert.match(lineageExporter, /join doom_worker_request r on r\.request_id=f\.request_id/);
assert.match(lineageExporter, /f\.save_lineage='&&route_lineage'/);
assert.match(lineageExporter, /f\.tic between &&route_from_tic\+1 and &&route_to_tic/);
assert.match(lineageExporter, /'cheat' value ''/);
assert.match(lineageExporter, /dbms_output\.put_line\('BASE64:'\)/);
assert.match(lineageExporter, /dbms_lob\.substr\(l_json,18000,l_offset\)/);

process.stdout.write('PASS MOCHADOOM-ROUTE-DIAGNOSTICS bounded actors, clearance, lineage export, safe tails\n');
