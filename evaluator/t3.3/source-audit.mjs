import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';

const root = path.resolve(import.meta.dirname, '../..');
const directory = path.join(root, 'sql/bsp');
assert.ok(fs.existsSync(directory), 'T3.3 implementation directory missing: sql/bsp');
const files = fs.readdirSync(directory).filter((name) => name.endsWith('.sql')).sort();
assert.ok(files.length > 0, 'no T3.3 SQL discovered');
const source = files.map((name) => fs.readFileSync(path.join(directory, name), 'utf8')).join('\n').toUpperCase();

for (const token of ['DOOM_BSP_LOCATE', 'DOOM_BSP_SIDE', 'P_X', 'P_Y', 'SQL_MACRO', 'CONNECT BY', 'DOOM_MAP_NODE',
  'DOOM_MAP_SSECTOR', 'DOOM_MAP_SEG', 'DOOM_MAP_LINEDEF', 'DOOM_MAP_SIDEDEF'])
  assert.ok(source.includes(token), `required BSP source token absent: ${token}`);
assert.match(source, /MAX\s*\(\s*NODE_ID\s*\)/, 'root is not derived as the last node');
assert.ok(source.includes('DX = 0') && source.includes('DY = 0'), 'explicit axis branches absent');
assert.ok(source.includes('CROSS') || (source.includes('P_X -') && source.includes('P_Y -')), 'non-axis cross predicate absent');
assert.ok(source.includes('> 0'), 'strict positive non-axis comparison absent');
assert.ok(source.includes('32768') || source.includes('8000'), 'subsector child-bit handling absent');
assert.ok((source.match(/DOOM_BSP_SIDE/g)??[]).length >= 2, 'location macro does not reuse the scalar side predicate');
assert.ok(!/WITH\s+\w+\s*\([^)]*\)\s+AS\s*\([^)]*UNION\s+ALL/is.test(source), 'recursive WITH is forbidden');
assert.ok(!/\b(WHILE|LOOP)\b/.test(source), 'procedural BSP traversal is forbidden');
assert.ok(!/EXECUTE\s+IMMEDIATE|DBMS_SQL/.test(source), 'dynamic SQL is forbidden');

for (const forbidden of ['EVALUATOR/', 'GOLDENS/', 'REPORTS/', '73D1F2D1C7CDC967', 'THING_ID = 157',
  'PLAYWRIGHT', 'CALL_STACK', 'FORMAT_CALL_STACK', 'V$PROCESS', 'TEST_NAME'])
  assert.ok(!source.includes(forbidden), `anti-reward-hacking token in BSP source: ${forbidden}`);
for (const coordinate of ['-416', '256', '-10000', '10000'])
  assert.ok(!source.includes(coordinate), `fixture coordinate embedded in BSP source: ${coordinate}`);

const connectAt = source.indexOf('CONNECT BY');
assert.ok(connectAt >= 0 && source.slice(connectAt).includes('ORDER'), 'path/result source lacks explicit ordering after traversal');
process.stdout.write(`PASS T3.3-SOURCE-AUDIT (${files.length} SQL files)\n`);
