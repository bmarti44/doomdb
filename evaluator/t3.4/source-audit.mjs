import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';

const root=path.resolve(import.meta.dirname,'../..'), directory=path.join(root,'sql/accel');
assert.ok(fs.existsSync(directory),'T3.4 implementation directory missing: sql/accel');
const files=fs.readdirSync(directory).filter(n=>n.endsWith('.sql')).sort();
assert.ok(files.length>0,'no T3.4 SQL discovered');
const source=files.map(n=>fs.readFileSync(path.join(directory,n),'utf8')).join('\n').toUpperCase();
for(const token of ['DOOM_BLOCK_CELL','DOOM_BLOCK_LINE','DOOM_SECTOR_REJECT','DOOM_SECTOR_EDGE','CREATE PROPERTY GRAPH','DOOM_SECTOR_GRAPH','GRAPH_TABLE','DOOM_BLOCKMAP_BYTE','DOOM_REJECT_BYTE','DOOM_MAP_LINEDEF','DOOM_MAP_SIDEDEF','DOOM_MAP_SECTOR','BITAND','FLOOR','POWER']) assert.ok(source.includes(token),`required relational source token absent: ${token}`);
for(const token of ['PRIMARY KEY','FOREIGN KEY','CHECK','LINE_ORDINAL','LIST_WORD_OFFSET','SOUND_BLOCK','OPENING']) assert.ok(source.includes(token),`fixed-interface constraint/column absent: ${token}`);
assert.ok(source.includes('65535')||source.includes('FFFF'),'BLOCKMAP terminator handling absent');
assert.ok(source.includes('128'),'128-unit BLOCKMAP cell size absent');
assert.ok(!/\b(WHILE|LOOP)\b/.test(source),'procedural byte/graph traversal is forbidden');
assert.ok(!/EXECUTE\s+IMMEDIATE|DBMS_SQL/.test(source),'dynamic SQL is forbidden');
assert.ok(!/CREATE\s+(OR\s+REPLACE\s+)?(FUNCTION|PROCEDURE|PACKAGE)/.test(source),'procedural shadow decoder is forbidden');
for(const forbidden of ['EVALUATOR/','GOLDENS/','REPORTS/','5F24718D6471411D','10E7C2BCC1A2E71C','66AAD841726F62B0D','PLAYWRIGHT','CALL_STACK','FORMAT_CALL_STACK','V$PROCESS','TEST_NAME','CI=']) assert.ok(!source.includes(forbidden),`anti-reward-hacking token in acceleration source: ${forbidden}`);
for(const fixture of ['-712','-1072','23490','1166','2064']) assert.ok(!source.includes(fixture),`pinned expected literal embedded in acceleration source: ${fixture}`);
process.stdout.write(`PASS T3.4-SOURCE-AUDIT (${files.length} SQL files)\n`);
