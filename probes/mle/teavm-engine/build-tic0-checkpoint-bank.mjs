import crypto from 'node:crypto';
import fs from 'node:fs';
import path from 'node:path';
import {
  allocateIwad,
  allocateTablePack,
  canonicalState,
  checkpointChunk,
  checkpointLength,
  initializeMultiplayerGame,
  loadIwadChunk,
  loadTablePackChunk,
  release,
} from '../../../client/dist/play/doom-mle-authority-06ac33331d9a.js';

const [iwadPath, tablePackPath, outputDirectory] = process.argv.slice(2);
if (!iwadPath || !tablePackPath || !outputDirectory) {
  throw new Error(
    'usage: node build-tic0-checkpoint-bank.mjs IWAD TABLE_PACK OUTPUT_DIRECTORY',
  );
}

const iwad = fs.readFileSync(iwadPath);
const tables = fs.readFileSync(tablePackPath);
const chunkBytes = 1024 * 1024;
fs.mkdirSync(outputDirectory, {recursive: true, mode: 0o700});

function transfer(bytes, allocate, load, label) {
  if (allocate(bytes.length) !== bytes.length) {
    throw new Error(`${label} allocation mismatch`);
  }
  for (let offset = 0; offset < bytes.length; offset += chunkBytes) {
    const chunk = bytes.subarray(offset, Math.min(bytes.length, offset + chunkBytes));
    if (load(offset, chunk) !== offset + chunk.length) {
      throw new Error(`${label} transfer mismatch at ${offset}`);
    }
  }
}

function checkpointBytes() {
  const result = new Uint8Array(checkpointLength());
  for (let offset = 0; offset < result.length; offset += 32767) {
    result.set(
      checkpointChunk(offset, Math.min(32767, result.length - offset)),
      offset,
    );
  }
  return result;
}

const rows = [];
for (const deathmatch of [0, 1]) {
  for (let skill = 1; skill <= 5; skill += 1) {
    transfer(iwad, allocateIwad, loadIwadChunk, 'IWAD');
    transfer(tables, allocateTablePack, loadTablePackChunk, 'table pack');
    initializeMultiplayerGame(2, deathmatch, skill, 1, 1);
    const canonical = canonicalState();
    const bytes = checkpointBytes();
    const mode = deathmatch === 0 ? 'COOP' : 'DEATHMATCH';
    const filename = `${mode.toLowerCase()}-skill-${skill}-e1m1.dmc1`;
    fs.writeFileSync(path.join(outputDirectory, filename), bytes, {mode: 0o600});
    rows.push([
      mode,
      skill,
      1,
      1,
      2,
      bytes.length,
      crypto.createHash('sha256').update(bytes).digest('hex'),
      crypto.createHash('sha256').update(canonical, 'utf8').digest('hex'),
      filename,
    ].join('\t'));
    release();
  }
}
fs.writeFileSync(path.join(outputDirectory, 'manifest.tsv'), `${rows.join('\n')}\n`,
  {encoding: 'ascii', mode: 0o600});
process.stdout.write(`PMLE_TIC0_BANK_BUILD|PASS|entries=${rows.length}\n`);
