import {createHash} from 'node:crypto';
import fs from 'node:fs';
import path from 'node:path';
import {pathToFileURL} from 'node:url';

const [
  iwadPath, tablePackPath, artifactPath,
  sampleArgument = '100', warmupArgument = '10',
] = process.argv.slice(2);
if (!iwadPath || !tablePackPath || !artifactPath) {
  throw new Error(
    'usage: node rank-presentation-frame-node.mjs IWAD TABLE_PACK ARTIFACT'
    + ' [SAMPLES WARMUP]',
  );
}
const presentationModule = await import(pathToFileURL(path.resolve(artifactPath)).href);
const {
  allocateIwad,
  allocateTablePack,
  initializeMultiplayerGame,
  loadIwadChunk,
  loadTablePackChunk,
  release,
  renderPlayerFrame,
  renderPlayerFrameChunk,
  renderPlayerFrameLength,
  stepMultiplayerAuthoritative,
} = presentationModule;
const chunkedFramePath = typeof renderPlayerFrameLength === 'function'
  && typeof renderPlayerFrameChunk === 'function';
if (!chunkedFramePath && typeof renderPlayerFrame !== 'function') {
  throw new Error('presentation artifact has no frame export');
}

const samples = Number(sampleArgument);
const warmup = Number(warmupArgument);
if (!Number.isInteger(samples) || ![100, 300].includes(samples)
    || !Number.isInteger(warmup) || warmup !== samples / 10) {
  throw new Error(`invalid frame corpus shape ${sampleArgument}/${warmupArgument}`);
}
const frameBytes = 320 * 200;
const chunkBytes = 32767;
const commands = Uint8Array.from(Buffer.from(
  '1900000000000000'
  + '1200000000000000'
  + '0000000000000000'
  + '0000000000000000',
  'hex',
));

function load(allocate, append, bytes, label) {
  if (allocate(bytes.length) !== bytes.length) {
    throw new Error(`${label} allocation failed`);
  }
  for (let offset = 0; offset < bytes.length; offset += 1024 * 1024) {
    const chunk = bytes.subarray(offset, Math.min(bytes.length, offset + 1024 * 1024));
    if (append(offset, chunk) !== offset + chunk.length) {
      throw new Error(`${label} short load at ${offset}`);
    }
  }
}

load(allocateIwad, loadIwadChunk, fs.readFileSync(iwadPath), 'IWAD');
load(allocateTablePack, loadTablePackChunk, fs.readFileSync(tablePackPath),
  'table pack');
const initialized = initializeMultiplayerGame(2, 0, 3, 1, 1);
if (!initialized.includes('state=multiplayer-initialized|gametic=0|')) {
  throw new Error(`presentation initialization failed: ${initialized}`);
}

let chain = Buffer.alloc(32);
const unique = new Set();
let frontier = 0;
for (let sample = 1; sample <= warmup + samples; sample += 1) {
  frontier = stepMultiplayerAuthoritative(2, 3, commands);
  if (frontier !== sample) {
    throw new Error(`presentation frontier mismatch at sample ${sample}`);
  }
  let frame;
  if (chunkedFramePath) {
    const length = renderPlayerFrameLength(0);
    if (length !== frameBytes) {
      throw new Error(`presentation frame length mismatch: ${length}`);
    }
    frame = Buffer.alloc(length);
    for (let offset = 0; offset < length; offset += chunkBytes) {
      const size = Math.min(chunkBytes, length - offset);
      const chunk = renderPlayerFrameChunk(offset, size);
      if (!(chunk instanceof Uint8Array) || chunk.length !== size) {
        throw new Error(`presentation short frame chunk at ${offset}`);
      }
      frame.set(chunk, offset);
    }
  } else {
    const direct = renderPlayerFrame(0);
    if (!(direct instanceof Uint8Array) || direct.length !== frameBytes) {
      throw new Error(`presentation direct frame length mismatch: ${direct?.length}`);
    }
    frame = Buffer.from(direct);
  }
  if (sample > warmup) {
    const frameSha = createHash('sha256').update(frame).digest();
    const hex = frameSha.toString('hex');
    if (unique.has(hex)) {
      throw new Error(`presentation frame is not unique at sample ${sample}`);
    }
    unique.add(hex);
    chain = createHash('sha256').update(chain).update(frameSha).digest();
  }
}

console.log(
  `PMLE_PRESENTATION_FRAME_ORACLE|PASS|samples=${samples}|warmup=${warmup}`
  + `|frame_bytes=${frameBytes}|unique=${unique.size}`
  + `|path=${chunkedFramePath ? 'chunked' : 'direct'}`
  + `|chain_sha256=${chain.toString('hex')}|frontier=${frontier}`,
);
release();
