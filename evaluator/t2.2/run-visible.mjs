import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { bytes, le32, name8, wad } from './fixture-kit.mjs';
import { completeLumps, malformedCases } from './visible-fixtures.mjs';

const repoRoot = path.resolve(import.meta.dirname, '../..');
const parser = path.join(repoRoot, 'tools/wad/parse.mjs');
const expected = JSON.parse(fs.readFileSync(path.join(import.meta.dirname, 'expectations.json'), 'utf8'));
const expectedDirectory = JSON.parse(fs.readFileSync(path.join(import.meta.dirname, 'directory-expectations.json'), 'utf8'));
const selectedKeys = ['wad','things','counts','spotChecks','reject','blockmap','playpal','colormap','pnames','textures','patches','flat','sound','music'];

function invoke(file) {
  return spawnSync(process.execPath, [parser, '--wad', file, '--map', 'E1M1'], {
    cwd: repoRoot, encoding: 'utf8', env: { PATH: process.env.PATH, HOME: process.env.HOME, LANG: 'C', TZ: 'UTC' },
  });
}

function changedLumps(testCase) {
  const lumps = completeLumps.map((l) => ({ name: l.name, data: Uint8Array.from(l.data) }));
  if (testCase.lump) return [{ name: testCase.lump.name, data: Uint8Array.from(testCase.lump.data) }];
  if (testCase.mutate) {
    const lump = lumps.find((l) => l.name === testCase.mutate.lump);
    lump.data[testCase.mutate.byte] = testCase.mutate.value;
  }
  if (testCase.replace) lumps.find((l) => l.name === testCase.replace.lump).data = Uint8Array.from(testCase.replace.data);
  return lumps;
}

function malformedBytes(testCase) {
  if (testCase.bytes) return testCase.bytes;
  if (testCase.rawDirectory) {
    return bytes(new TextEncoder().encode('PWAD'), le32(1), le32(12), le32(testCase.rawDirectory.offset),
      le32(testCase.rawDirectory.size), name8(testCase.rawDirectory.name));
  }
  return wad(changedLumps(testCase));
}

assert.ok(fs.existsSync(parser), 'T2.2 implementation entrypoint missing: tools/wad/parse.mjs');
const scratch = fs.mkdtempSync(path.join(os.tmpdir(), 'doom-t2.2-visible-'));
try {
  const good = path.join(scratch, 'visible-complete.wad');
  fs.writeFileSync(good, wad(completeLumps));
  const first = invoke(good);
  const second = invoke(good);
  assert.equal(first.status, 0, `clean fixture failed: ${first.stderr}`);
  assert.equal(second.status, 0, `second clean parse failed: ${second.stderr}`);
  assert.equal(first.stdout, second.stdout, 'clean-process parse output is not byte-identical');
  assert.equal(first.stderr, '');
  assert.match(first.stdout, /^\{.*\}\n$/s, 'stdout must be one compact JSON object plus LF');
  const actual = JSON.parse(first.stdout);
  assert.deepEqual(actual.directory, expectedDirectory, 'directory provenance mismatch');
  for (const key of selectedKeys) assert.deepEqual(actual[key], expected[key], `visible expectation mismatch at ${key}`);
  assert.equal(JSON.stringify(actual).includes('timestamp'), false, 'volatile timestamp field is forbidden');

  for (const testCase of malformedCases) {
    const file = path.join(scratch, `${testCase.id}.wad`);
    fs.writeFileSync(file, malformedBytes(testCase));
    for (let attempt = 0; attempt < 2; attempt += 1) {
      const result = invoke(file);
      assert.equal(result.status, 2, `${testCase.id}: expected parser rejection exit 2`);
      assert.equal(result.stdout, '', `${testCase.id}: rejection wrote success output`);
      assert.equal(result.stderr, `ERROR ${testCase.error}\n`, `${testCase.id}: unstable/wrong diagnostic`);
    }
  }
  process.stdout.write('PASS T2.2-VISIBLE (19/19 test ids)\n');
} finally {
  fs.rmSync(scratch, { recursive: true, force: true });
}
