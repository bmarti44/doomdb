import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
const root=path.resolve(import.meta.dirname,'../..'),dir=path.join(root,'sql/render/r1');
assert.ok(fs.existsSync(dir),'T4.2 implementation directory missing: sql/render/r1');
const files=fs.readdirSync(dir).filter(n=>n.endsWith('.sql')).sort(),selected=files.filter(n=>fs.readFileSync(path.join(dir,n),'utf8').toUpperCase().includes('DOOM_R1_PIXELS'));
assert.ok(selected.length>0,'DOOM_R1_PIXELS source absent');const source=selected.map(n=>fs.readFileSync(path.join(dir,n),'utf8')).join('\n').toUpperCase();
for(const token of ['DOOM_R1_PIXELS','SQL_MACRO','P_SESSION','GAME_SESSIONS','PLAYERS','DOOM_R1_NEAREST','DOOM_MAP_SIDEDEF','DOOM_MAP_SECTOR','DOOM_MAP_SEG','DOOM_MAP_LINEDEF','DOOM_ASSET','DOOM_COLORMAP_TEXEL','COLUMN_NO','ROW_NO','PALETTE_INDEX','LAYER_ORDINAL','CONNECT BY','LEVEL','320','200','FLOOR','TAN','VIEW_HEIGHT','X_OFFSET','Y_OFFSET','MIDDLE_TEXTURE','LIGHT_LEVEL'])assert.ok(source.includes(token),`required relational pixel token absent: ${token}`);
assert.ok(source.includes(' AT ')||source.includes('\nAT ')||source.includes('JOIN AT'),'dense relational texel table AT absent');
assert.ok(source.includes('0.5')||source.includes('.5'),'half-row pixel center absent');
assert.ok(source.includes('ORDER BY')&&source.includes('COLUMN_NO')&&source.includes('ROW_NO'),'canonical order contract absent');
assert.ok(!/\b(WHILE|FOR\s+[^\n]+\s+LOOP|LOOP\s*;)/.test(source),'procedural pixel loop is forbidden');
assert.ok(!/EXECUTE\s+IMMEDIATE|DBMS_SQL/.test(source),'dynamic SQL is forbidden');
assert.ok(!/WITH\s+[A-Z0-9_$]+\s*\([^)]*\)\s+AS[^;]+UNION\s+ALL/is.test(source),'recursive WITH render path is forbidden');
assert.ok(!/\bMOD\s*\(/.test(source),'Oracle MOD violates negative-safe floor_mod contract');
assert.ok(!/TO_CHAR\s*\([^,)]*\)/.test(source),'default numeric formatting is forbidden');
for(const bad of ['EVALUATOR/','GOLDENS/','SNAPSHOTS/','REPORTS/','PLAYWRIGHT','CALL_STACK','FORMAT_CALL_STACK','V$PROCESS','TEST_NAME','CI=','EXPECTED FRAME','REFERENCE OUTPUT','47302A67B53EF176','46C8A2CA36446249','B920598F8363B347','1F58A067638547D8'])assert.ok(!source.includes(bad),`anti-reward-hacking token in pixel source: ${bad}`);
for(const pose of ['-416','SPAWN-EAST','SPAWN-NORTH','SPAWN-SOUTH'])assert.ok(!source.includes(pose),`fixture-specific pose in production: ${pose}`);
assert.ok(/P_SESSION/.test(source),'session bind absent'); // SESSION BIND guard
assert.ok(/DOOM_R1_NEAREST/.test(source),'nearest sector dependency absent'); // NEAREST SECTOR guard
process.stdout.write(`PASS T4.2-SOURCE-AUDIT (${selected.length} SQL files; canonical order; no procedural pixel loop or dynamic SQL; no expected frame)\n`);
