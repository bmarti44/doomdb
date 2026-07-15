import assert from 'node:assert/strict';
import crypto from 'node:crypto';
import fs from 'node:fs';
import path from 'node:path';
import { composedTexture, directory, last, mapRows, patchImage, readPinnedWad, sha256, texel } from './wad-seed-oracle.mjs';

const root = path.resolve(import.meta.dirname, '../..');
const readJson = (name) => JSON.parse(fs.readFileSync(path.join(import.meta.dirname, name), 'utf8'));
const expected = readJson('expectations.json');
const tests = readJson('test-ids.json');
const mutations = readJson('mutation-specs.json');
const wad = readPinnedWad(path.join(root, 'vendor/freedoom/0.13.0/freedoom-0.13.0.zip'));
const rows = directory(wad);
const confined = mapRows(rows);

assert.equal(sha256(wad), expected.wadSha256);
assert.deepEqual(confined.map((row) => row.name), ['E1M1','THINGS','LINEDEFS','SIDEDEFS','VERTEXES','SEGS','SSECTORS','NODES','SECTORS','REJECT','BLOCKMAP']);
for (const probe of expected.sourceProbes) {
  const pool = confined.some((row) => row.name === probe.name) && !['PLAYPAL','COLORMAP','PNAMES','TEXTURE1','TEXTURE2'].includes(probe.name) ? confined : rows;
  const actual = pool.filter((row) => row.name === probe.name).at(-1);
  assert.ok(actual, `missing source probe ${probe.name}`);
  assert.deepEqual({ name:actual.name, occurrence:actual.occurrence, offset:actual.offset, size:actual.size, sha256:actual.sha256 }, probe);
}

const mapByName = new Map(confined.map((row) => [row.name, row]));
assert.equal(mapByName.get('THINGS').size / 10, expected.planCounts.things);
assert.equal(mapByName.get('VERTEXES').size / 4, expected.planCounts.vertices);
assert.equal(mapByName.get('LINEDEFS').size / 14, expected.planCounts.linedefs);
assert.equal(mapByName.get('SIDEDEFS').size / 30, expected.planCounts.sidedefs);
assert.equal(mapByName.get('SECTORS').size / 26, expected.planCounts.sectors);
assert.equal(mapByName.get('SEGS').size / 12, expected.planCounts.segs);
assert.equal(mapByName.get('SSECTORS').size / 4, expected.planCounts.ssectors);
assert.equal(mapByName.get('NODES').size / 28, expected.planCounts.nodes);
assert.equal(mapByName.get('REJECT').size, expected.planCounts.rejectBytes);
assert.equal(mapByName.get('BLOCKMAP').size, expected.planCounts.blockmapBytes);
assert.equal(expected.planCounts.paletteTexels, 256);
assert.equal(expected.planCounts.colormapTexels, 32 * 256);

const playpal = last(rows, 'PLAYPAL').bytes;
const colormap = last(rows, 'COLORMAP').bytes;
const flat = (name, x, y) => last(rows, name).bytes[y * 64 + x];
for (const probe of expected.spotTexels) {
  let actual;
  if (probe.kind === 'palette') actual = [...playpal.subarray(probe.x * 3, probe.x * 3 + 3)];
  else if (probe.kind === 'colormap') actual = colormap[probe.y * 256 + probe.x];
  else if (probe.kind === 'flat') actual = flat(probe.name, probe.x, probe.y);
  else if (probe.kind === 'wall_texture') actual = texel(composedTexture(rows, probe.name), probe.x, probe.y);
  else actual = texel(patchImage(last(rows, probe.name).bytes), probe.x, probe.y);
  assert.deepEqual(actual, probe.value, `literal spot mismatch ${probe.kind}:${probe.name}:${probe.x}:${probe.y}`);
}
for (const probe of expected.assetHashProbes) assert.equal(last(rows, probe.name).sha256, probe.sourceSha256, `${probe.name}: literal source hash mismatch`);

assert.equal(tests.tests.length, 18);
assert.equal(new Set(tests.tests.map((test) => test.id)).size, tests.tests.length);
assert.equal(tests.tests.reduce((sum, test) => sum + test.assertions, 0), 168);
assert.equal(mutations.mutations.length, 14);
assert.equal(new Set(mutations.mutations.map((mutation) => mutation.id)).size, 14);
assert.ok(mutations.mutations.every((mutation) => tests.tests.some((test) => test.id === mutation.killedBy)));
assert.ok(mutations.mutations.every((mutation) => mutation.change.length > 20));
assert.equal(expected.format.maxRowsPerBatch, 500);
assert.equal(expected.format.encoding, 'ASCII');
assert.equal(expected.format.newline, 'LF');
assert.equal(fs.existsSync(path.join(root, 'evaluator/integrity.json')), true);
assert.equal(fs.existsSync(path.join(root, 'evaluator/integrity.pending-T2.2.json')), true);
assert.equal(fs.existsSync(path.join(root, 'evaluator/integrity.pending-T2.3.json')), true);
assert.equal(crypto.createHash('sha256').update(fs.readFileSync(path.join(root, 'evaluator/integrity.json'))).digest('hex'), '2699e0e0f6e93593d8172ea19a048d2ad6ebabb57aef2604a81782c25f2882a3');

process.stdout.write('PASS T2.4-EVAL-SELF-CHECK (65/65 fixture-contract assertions)\n');
