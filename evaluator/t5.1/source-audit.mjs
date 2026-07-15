import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
const root=path.resolve(import.meta.dirname,'../..'),dir=path.join(root,'sql/render/r2');
assert.ok(fs.existsSync(dir),'T5.1 implementation directory missing: sql/render/r2');
const files=fs.readdirSync(dir).filter(n=>n.endsWith('.sql')).sort();
assert.ok(files.length>0,'no T5.1 SQL discovered');
const selected=files.filter(n=>{const s=fs.readFileSync(path.join(dir,n),'utf8').toUpperCase();return /CREATE\s+(?:OR\s+REPLACE\s+)?FUNCTION\s+DOOM_R2_(?:PORTAL_HITS|SECTOR_INTERVALS)\b/.test(s);});
assert.ok(selected.length>0,'reviewed T5.1 macro source absent');
const source=selected.map(n=>fs.readFileSync(path.join(dir,n),'utf8')).join('\n').toUpperCase();
for(const token of ['DOOM_R2_PORTAL_HITS','DOOM_R2_SECTOR_INTERVALS','SQL_MACRO','P_SESSION','DOOM_R1_HITS','SECTOR_STATE','DOOM_MAP_SECTOR','HIT_T','LINEDEF_ID','SEG_ID','FACING_SIDE','HIT_ORDINAL','ROW_NUMBER','ORDER BY','PARTITION BY','MAX','MIN','OPENING_BOTTOM','OPENING_TOP','LOWER_BOTTOM','LOWER_TOP','UPPER_BOTTOM','UPPER_TOP','IS_CLOSED','IS_TRANSITION','IS_TERMINATION','INTERVAL_ORDINAL','T_START','T_END','SECTOR_ID'])assert.ok(source.includes(token),`required portal-timeline token absent: ${token}`);
assert.ok(/SECTOR_STATE[\s\S]*(FLOOR_HEIGHT|CURRENT_FLOOR)/.test(source)&&/SECTOR_STATE[\s\S]*(CEILING_HEIGHT|CURRENT_CEILING)/.test(source),'dynamic sector heights absent'); // DYNAMIC SECTOR HEIGHTS guard
assert.ok(!/\b(WHILE|FOR\s+[^\n]+\s+LOOP|LOOP\s*;)/.test(source),'procedural portal loop is forbidden'); // PROCEDURAL PORTAL LOOP guard
assert.ok(!/EXECUTE\s+IMMEDIATE|DBMS_SQL/.test(source),'dynamic SQL is forbidden');
assert.ok(!/\bROUND\s*\(\s*(HIT_T|[^)]*HIT_T)/.test(source),'hit depth rounded before ordering');
assert.ok(!/WITH\s+[A-Z0-9_$]+\s*\([^)]*\)\s+AS[^;]+UNION\s+ALL/is.test(source),'recursive WITH render path forbidden');
assert.ok(/P_SESSION/.test(source)&&/DOOM_R1_HITS/.test(source),'session-bound complete hit source absent');
for(const bad of ['EVALUATOR/','GOLDENS/','SNAPSHOTS/','REPORTS/','PLAYWRIGHT','CALL_STACK','FORMAT_CALL_STACK','V$PROCESS','TEST_NAME','CI=','EXPECTED TIMELINE','REFERENCE OUTPUT','F2CEF61746374E2D','992657351FFD0EAC',"'WINDOW'","'VERTEX-TIE'","'OPEN-RANGE'"])assert.ok(!source.includes(bad),`embedded fixture answers or evaluator coupling: ${bad}`); // EMBEDDED FIXTURE ANSWERS guard
process.stdout.write(`PASS T5.1-SOURCE-AUDIT (${selected.length} SQL files; complete hits, dynamic heights, analytic ordering)\n`);
