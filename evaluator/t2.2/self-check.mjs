import assert from 'node:assert/strict';
import crypto from 'node:crypto';
import fs from 'node:fs';
import path from 'node:path';
import { wad } from './fixture-kit.mjs';
import { completeLumps, malformedCases } from './visible-fixtures.mjs';

const root = path.resolve(import.meta.dirname, '../..');
const expected = JSON.parse(fs.readFileSync(path.join(import.meta.dirname, 'expectations.json'), 'utf8'));
const tests = JSON.parse(fs.readFileSync(path.join(import.meta.dirname, 'test-ids.json'), 'utf8'));
const mutations = JSON.parse(fs.readFileSync(path.join(import.meta.dirname, 'mutation-specs.json'), 'utf8'));
const directory = JSON.parse(fs.readFileSync(path.join(import.meta.dirname, 'directory-expectations.json'), 'utf8'));
const fixture = wad(completeLumps);

assert.equal(fixture.length, expected.fixtureBytes);
assert.equal(crypto.createHash('sha256').update(fixture).digest('hex'), expected.fixtureSha256);
assert.equal(new TextDecoder().decode(fixture.slice(0, 4)), 'PWAD');
assert.equal(new DataView(fixture.buffer, fixture.byteOffset).getUint32(4, true), 29);
assert.equal(completeLumps.filter((l) => l.name === 'DUPLUMP').length, 2);
assert.equal(completeLumps.findIndex((l) => l.name === 'E1M2'), 27);
assert.equal(completeLumps.slice(3, 13).map((l) => l.name).join(','), 'THINGS,LINEDEFS,SIDEDEFS,VERTEXES,SEGS,SSECTORS,NODES,SECTORS,REJECT,BLOCKMAP');
assert.equal(malformedCases.length, 15);
assert.equal(new Set(malformedCases.map((c) => c.error)).size, 15);
assert.equal(tests.tests.length, 19);
assert.equal(new Set(tests.tests.map((t) => t.id)).size, tests.tests.length);
assert.ok(tests.tests.every((t) => t.assertions > 0));
assert.equal(mutations.mutations.length, 10);
assert.ok(mutations.mutations.every((m) => tests.tests.some((t) => t.id === m.killedBy)));
assert.equal(directory.length, completeLumps.length);
assert.equal(directory.at(-1).offset + directory.at(-1).size + directory.length * 16, fixture.length);
assert.equal(fs.existsSync(path.join(root, 'evaluator/integrity.json')), true);

process.stdout.write('PASS T2.2-EVAL-SELF-CHECK (17/17 fixture-contract assertions)\n');
