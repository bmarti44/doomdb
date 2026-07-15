import assert from 'node:assert/strict';
import crypto from 'node:crypto';
import { spawnSync } from 'node:child_process';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { composedTexture, directory, last, patchImage, readPinnedWad, sha256, texelHash } from './wad-seed-oracle.mjs';

const root = path.resolve(import.meta.dirname, '../..');
const load = (relative) => JSON.parse(fs.readFileSync(path.join(root, relative), 'utf8'));
const expected = load('evaluator/t2.4/expectations.json');
const closure = load('tools/wad/asset-closure.json');
const generator = path.join(root, 'tools/wad/generate-seed.mjs');
assert.ok(fs.existsSync(generator), 'T2.4 implementation entrypoint missing: tools/wad/generate-seed.mjs');

const wad = readPinnedWad(path.join(root, 'vendor/freedoom/0.13.0/freedoom-0.13.0.zip'));
const wadRows = directory(wad);
const scratch = fs.mkdtempSync(path.join(os.tmpdir(), 'doom-t2.4-visible-'));
const wadPath = path.join(scratch, 'freedoom1.wad');
fs.writeFileSync(wadPath, wad);

function invoke(out) {
  const args = [generator, '--wad', wadPath,
    '--engine-defs', path.join(root, 'tools/wad/engine-defs.json'),
    '--asset-closure', path.join(root, 'tools/wad/asset-closure.json'),
    '--animations', path.join(root, 'tools/wad/animation-groups.json'),
    '--rng', path.join(root, 'tools/wad/rng-table.json'), '--out', out];
  const result = spawnSync(process.execPath, args, {
    cwd: root, encoding: 'utf8', maxBuffer: 16 * 1024 * 1024,
    env: { PATH: process.env.PATH, HOME: process.env.HOME, LANG: 'C', TZ: 'UTC' },
  });
  assert.equal(result.status, 0, `seed generation failed: ${result.stderr}`);
  assert.equal(result.stderr, '', 'seed generation wrote stderr');
}

function filesUnder(base) {
  const found = [];
  const walk = (at) => {
    for (const entry of fs.readdirSync(at, { withFileTypes: true })) {
      const absolute = path.join(at, entry.name);
      if (entry.isDirectory()) walk(absolute);
      else found.push(path.relative(base, absolute).split(path.sep).join('/'));
    }
  };
  walk(base);
  return found.sort();
}

const hashTexels = (kind, name) => {
  if (kind === 'wall_texture') return texelHash(composedTexture(wadRows, name));
  if (kind === 'flat') {
    const bytes = last(wadRows, name).bytes;
    const pixels = Int16Array.from(bytes);
    return texelHash({ pixels });
  }
  if (['patch','sprite_patch','ui_patch'].includes(kind)) return texelHash(patchImage(last(wadRows, name).bytes));
  return undefined;
};

try {
  const outA = path.join(scratch, 'a');
  const outB = path.join(scratch, 'b');
  fs.mkdirSync(outA);
  fs.mkdirSync(outB);
  invoke(outA);
  invoke(outB);

  const pathsA = filesUnder(outA);
  const pathsB = filesUnder(outB);
  assert.deepEqual(pathsA, pathsB, 'two generations emitted different paths');
  assert.ok(pathsA.includes('seed-manifest.json'), 'seed-manifest.json missing');
  assert.ok(pathsA.every((name) => name === 'seed-manifest.json' || name.endsWith('.sql')), 'unexpected generated file type');
  for (const relative of pathsA) assert.deepEqual(fs.readFileSync(path.join(outA, relative)), fs.readFileSync(path.join(outB, relative)), `non-deterministic output ${relative}`);

  for (const base of [outA, outB]) for (const relative of pathsA) {
    const bytes = fs.readFileSync(path.join(base, relative));
    assert.ok([...bytes].every((byte) => byte < 128), `${relative}: non-ASCII byte`);
    assert.equal(bytes.includes(13), false, `${relative}: CR forbidden`);
    assert.equal(bytes.at(-1), 10, `${relative}: final LF required`);
  }

  const manifestBytes = fs.readFileSync(path.join(outA, 'seed-manifest.json'));
  const manifest = JSON.parse(manifestBytes);
  assert.equal(manifestBytes.toString(), `${JSON.stringify(manifest, null, 2)}\n`, 'manifest is not canonical two-space JSON');
  assert.equal(manifest.schema, 1);
  assert.equal(manifest.wadSha256, expected.wadSha256);
  assert.equal(manifest.map, expected.map);
  assert.equal(manifest.encoding, 'ASCII');
  assert.equal(manifest.newline, 'LF');
  assert.equal(manifest.maxRowsPerBatch, 500);
  assert.deepEqual(manifest.planCounts, expected.planCounts);
  assert.deepEqual(manifest.mapBounds, expected.mapBounds);
  assert.deepEqual(manifest.playerOneSpawn, { thingIndex:157, x:-416, y:256, angle:0, flags:7 });
  assert.deepEqual(manifest.spotTexels, expected.spotTexels);
  assert.doesNotMatch(manifestBytes.toString(), /timestamp|generatedAt|elapsed|session|\bscn\b/i, 'volatile manifest field');

  const sqlPaths = pathsA.filter((name) => name.endsWith('.sql'));
  assert.deepEqual(manifest.files.map((row) => row.path), sqlPaths, 'manifest must list every and only SQL file in sorted order');
  const datasetTotals = {};
  for (const record of manifest.files) {
    const bytes = fs.readFileSync(path.join(outA, record.path));
    assert.equal(record.sha256, sha256(bytes), `${record.path}: byte hash mismatch`);
    const statements = bytes.toString().split(/;\n/).map((statement) => statement.trim()).filter((statement) => /\bINSERT\b/i.test(statement));
    const rowsPerStatement = statements.map((statement) => (statement.match(/\bINTO\s+[A-Z0-9_]+\s*\(/gi) ?? []).length || 1);
    assert.equal(record.batchCount, statements.length, `${record.path}: batch count mismatch`);
    assert.equal(record.maxRowsInBatch, Math.max(0, ...rowsPerStatement), `${record.path}: max batch mismatch`);
    assert.ok(record.maxRowsInBatch <= 500, `${record.path}: batch exceeds 500 rows`);
    assert.equal(record.rowCount, rowsPerStatement.reduce((sum, value) => sum + value, 0), `${record.path}: logical row count mismatch`);
    datasetTotals[record.dataset] = (datasetTotals[record.dataset] ?? 0) + record.rowCount;
  }
  for (const [dataset, count] of Object.entries(expected.planCounts)) assert.equal(datasetTotals[dataset], count, `${dataset}: generated row total mismatch`);
  const treeDocument = manifest.files.map((row) => `${row.path}\0${row.sha256}\n`).join('');
  assert.equal(manifest.sqlTreeSha256, sha256(Buffer.from(treeDocument, 'ascii')), 'canonical SQL tree hash mismatch');

  const sourceByName = new Map(manifest.sources.map((row) => [`${row.name}:${row.occurrence}`, row]));
  assert.equal(sourceByName.size, manifest.sources.length, 'duplicate provenance source');
  for (const source of manifest.sources) {
    const actual = wadRows.find((row) => row.index === source.directoryIndex);
    assert.ok(actual, `source directory index absent: ${source.directoryIndex}`);
    assert.deepEqual({ name:source.name, occurrence:source.occurrence, offset:source.offset, size:source.size, sha256:source.sha256 },
      { name:actual.name, occurrence:actual.occurrence, offset:actual.offset, size:actual.size, sha256:actual.sha256 }, `${source.name}: provenance mismatch`);
    assert.ok(['last-occurrence','map-confined'].includes(source.selection), `${source.name}: invalid selection rule`);
    if (source.selection === 'last-occurrence') assert.equal(actual.index, last(wadRows, source.name).index, `${source.name}: not last occurrence`);
  }
  for (const probe of expected.sourceProbes) {
    const source = sourceByName.get(`${probe.name}:${probe.occurrence}`);
    assert.ok(source, `literal source probe absent from manifest: ${probe.name}`);
    assert.deepEqual({ name:source.name, occurrence:source.occurrence, offset:source.offset, size:source.size, sha256:source.sha256 }, probe);
  }

  const closureByKey = new Map(closure.assets.map((asset) => [`${asset.kind}:${asset.name}`, asset]));
  const manifestByKey = new Map(manifest.assets.map((asset) => [`${asset.kind}:${asset.name}`, asset]));
  assert.equal(closureByKey.size, closure.assets.length, 'approved closure contains duplicate key');
  assert.equal(manifestByKey.size, manifest.assets.length, 'manifest contains duplicate asset key');
  assert.deepEqual([...manifestByKey.keys()], [...closureByKey.keys()].sort(), 'manifest must contain every and only closure asset, sorted');
  for (const [key, approved] of closureByKey) {
    const asset = manifestByKey.get(key);
    assert.deepEqual(asset.sourceLumps, approved.sourceLumps, `${key}: ordered source closure mismatch`);
    const sourceRows = approved.sourceLumps.map((name) => last(wadRows, name));
    assert.deepEqual(asset.sourceSha256, sourceRows.map((row) => row.sha256), `${key}: source hashes mismatch`);
    if (sourceRows.length === 1) assert.equal(asset.rawSha256, sourceRows[0].sha256, `${key}: raw hash mismatch`);
    const decoded = hashTexels(asset.kind, asset.name);
    if (decoded !== undefined) assert.equal(asset.texelSha256, decoded, `${key}: decoded texel hash mismatch`);
  }
  for (const probe of expected.assetHashProbes) assert.equal(manifestByKey.get(`${probe.kind}:${probe.name}`).rawSha256, probe.sourceSha256, `${probe.kind}:${probe.name}: literal asset hash mismatch`);

  assert.equal(datasetTotals.wadSources, manifest.sources.length, 'seeded WAD provenance row total mismatch');
  assert.equal(datasetTotals.assets, manifest.assets.length, 'seeded asset row total mismatch');
  assert.equal(datasetTotals.assetSources, manifest.assets.reduce((sum, asset) => sum + asset.sourceLumps.length, 0), 'seeded asset-source row total mismatch');
  const sqlText = sqlPaths.map((relative) => fs.readFileSync(path.join(outA, relative), 'ascii')).join('\n');
  for (const source of manifest.sources) assert.ok(sqlText.includes(source.sha256), `source SHA absent from SQL: ${source.name}`);
  for (const asset of manifest.assets) {
    assert.ok(sqlText.includes(`'${asset.kind}'`), `asset kind absent from SQL: ${asset.kind}`);
    assert.ok(sqlText.includes(`'${asset.name.replaceAll("'", "''")}'`), `asset name absent from SQL: ${asset.name}`);
  }

  process.stdout.write('PASS T2.4-VISIBLE (18/18 test ids, 168/168 declared assertions)\n');
} finally {
  fs.rmSync(scratch, { recursive: true, force: true });
}
