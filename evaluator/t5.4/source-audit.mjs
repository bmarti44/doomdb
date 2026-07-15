import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
const root=path.resolve(import.meta.dirname,'../..'),dir=path.join(root,'sql/render/r2');
assert.ok(fs.existsSync(dir),'T5.4 implementation directory missing: sql/render/r2');
const files=fs.readdirSync(dir).filter(n=>n.endsWith('.sql')).sort();
const selected=files.filter(n=>fs.readFileSync(path.join(dir,n),'utf8').toUpperCase().includes('DOOM_R2_PRESENTATION'));
assert.ok(selected.length>0,'reviewed T5.4 presentation macro source absent');
const source=selected.map(n=>fs.readFileSync(path.join(dir,n),'utf8')).join('\n').toUpperCase();
for(const token of ['DOOM_R2_PRESENTATION','SQL_MACRO','P_SESSION','GAME_SESSIONS','PLAYERS','GAME_MODE','PAUSED','MENU_STATE','AUTOMAP_STATE','SELECTED_WEAPON','DOOM_ASSET',' AT ','COLUMN_NO','ROW_NO','PALETTE_INDEX','LAYER_ORDINAL','SOURCE_KIND','SOURCE_ID','ROW_NUMBER','ORDER BY'])assert.ok(source.includes(token),`required presentation token absent: ${token}`);
assert.ok(source.includes('DOOM_LINEDEF')&&source.includes('DOOM_VERTEX'),'database automap ownership absent'); // DATABASE AUTOMAP OWNERSHIP GUARD
assert.ok(/ASSET_KIND[\s\S]*(UI_PATCH|SPRITE_PATCH)/.test(source),'reviewed WAD asset kinds absent'); // RELATIONAL WAD ASSET GUARD
assert.ok(/PARTITION\s+BY[\s\S]*COLUMN_NO[\s\S]*ROW_NO/.test(source)&&/ORDER\s+BY[\s\S]*LAYER_ORDINAL/.test(source),'stable layer winner absent'); // STABLE LAYER ORDER GUARD
assert.ok(source.includes('TRANSPARENT')||/\bC\s*>=\s*0/.test(source),'transparent patch hole predicate absent');
assert.ok(source.includes('320')&&source.includes('200')&&source.includes('168'),'reviewed canvas and HUD bounds absent');
assert.ok(!/\b(WHILE|FOR\s+[^\n]+\s+LOOP|LOOP\s*;)/.test(source),'procedural presentation loop forbidden'); // PROCEDURAL PRESENTATION LOOP GUARD
assert.ok(!/EXECUTE\s+IMMEDIATE|DBMS_SQL/.test(source),'dynamic SQL forbidden');
assert.ok(!/WITH\s+[A-Z0-9_$]+\s*\([^)]*\)\s+AS[^;]+UNION\s+ALL/is.test(source),'recursive WITH render path forbidden');
assert.ok(!/(P_|BROWSER_|CLIENT_)(LINE_X|LINE_Y|X1|Y1|X2|Y2)/.test(source),'browser projected automap coordinates forbidden');
assert.ok(/LAYER_ORDINAL[\s\S]*(HUD|STATUS)/.test(source),'HUD layer precedence absent'); // LAYER PRECEDENCE GUARD
for(const bad of ['EVALUATOR/','GOLDENS/','SNAPSHOTS/','REPORTS/','PLAYWRIGHT','CALL_STACK','FORMAT_CALL_STACK','V$PROCESS','TEST_NAME','EXPECTED FRAME','REFERENCE OUTPUT','A3780F4CA8CC9348','EA767582E2DD8DEC','HUD-VARIATION','AUTOMAP-FULL','MENU-2'])assert.ok(!source.includes(bad),`embedded fixture answers or evaluator coupling: ${bad}`); // EMBEDDED PRESENTATION ANSWERS GUARD
process.stdout.write(`PASS T5.4-SOURCE-AUDIT (${selected.length} SQL files; relational assets, state, geometry, stable set-based layers)\n`);
