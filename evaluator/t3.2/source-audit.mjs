import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';

const root = path.resolve(import.meta.dirname, '../..');
const spatial = path.join(root, 'sql/spatial');
assert.ok(fs.existsSync(spatial), 'T3.2 implementation directory missing: sql/spatial');
const files = fs.readdirSync(spatial).filter((name) => name.endsWith('.sql')).sort();
assert.ok(files.length > 0, 'no T3.2 production SQL discovered');
const source = files.map((name) => fs.readFileSync(path.join(spatial, name), 'utf8')).join('\n').toUpperCase();

for (const token of ['MIN(', 'MAX(', 'FAR_DISTANCE', 'PLAYER_RADIUS'])
  assert.ok(source.includes(token), `metadata derivation token absent: ${token}`);
for (const literal of ['-8912', '11456', '-9272', '10544'])
  assert.ok(!source.includes(literal), `calculated metadata bound embedded as literal: ${literal}`);

const filterStatements = source.split(/;\s*(?:\n|$)/).filter((statement) => statement.includes('SDO_FILTER'));
assert.ok(filterStatements.length > 0, 'no production SDO_FILTER/exact-predicate contract query discovered');
for (const statement of filterStatements) {
  assert.match(statement, /SDO_(?:RELATE|GEOM\.)/, 'SDO_FILTER statement lacks a following exact geometry predicate');
  assert.ok(statement.indexOf('SDO_FILTER') < Math.max(statement.indexOf('SDO_RELATE'), statement.indexOf('SDO_GEOM.')),
    'exact predicate must follow the MBR candidate filter');
}
process.stdout.write(`PASS T3.2-SOURCE-AUDIT (${files.length} SQL files)\n`);
