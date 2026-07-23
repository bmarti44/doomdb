import {createHash} from 'node:crypto';
import fs from 'node:fs';
import path from 'node:path';
import {pathToFileURL} from 'node:url';

const artifactPath = process.argv[4]
  ?? './target/javascript/doom-mle-presentation-engine-headless.js';
const {
  allocateIwad,
  allocateTablePack,
  canonicalStateChunk,
  canonicalStateLength,
  canonicalOffsetDescription,
  initializeMultiplayerGame,
  loadIwadChunk,
  loadTablePackChunk,
  memoryDiagnostic,
  presentationDiagnostic,
  release,
  renderPlayerFrame,
  stepMultiplayerAuthoritative,
} = await import(pathToFileURL(path.resolve(
  import.meta.dirname, artifactPath)).href);

const iwadPath = process.argv[2];
const tablePackPath = process.argv[3];
if (!iwadPath || !tablePackPath) {
  throw new Error(
    'usage: node run-presentation-node.mjs IWAD CANONICAL_TABLE_PACK [ARTIFACT]',
  );
}
const iwad = fs.readFileSync(iwadPath);
const tablePack = fs.readFileSync(tablePackPath);
const chunkBytes = 1024 * 1024;
const sampleTics = 96;
const frameDumpDirectory = process.env.PMLE_PRESENTATION_FRAME_DIR;

function loadBytes(allocate, load, bytes, label) {
  if (allocate(bytes.length) !== bytes.length) {
    throw new Error(`${label} allocation failed`);
  }
  for (let offset = 0; offset < bytes.length; offset += chunkBytes) {
    const chunk = bytes.subarray(offset, Math.min(bytes.length, offset + chunkBytes));
    if (load(offset, chunk) !== offset + chunk.length) {
      throw new Error(`${label} short load at ${offset}`);
    }
  }
}

function initialize() {
  loadBytes(allocateIwad, loadIwadChunk, iwad, 'IWAD');
  loadBytes(allocateTablePack, loadTablePackChunk, tablePack, 'table pack');
  const state = initializeMultiplayerGame(2, 0, 3, 1, 1);
  if (!state.includes('state=multiplayer-initialized|gametic=0|')) {
    throw new Error(`presentation initialization failed: ${state}`);
  }
}

function commands(tic) {
  const result = new Uint8Array(32);
  result[0] = tic % 7 === 0 ? 25 : 0;
  result[1] = tic % 11 === 0 ? 0xe8 : 0;
  result[2] = tic % 5 === 0 ? 0xfd : 0;
  result[3] = tic % 5 === 0 ? 0x80 : 0;
  result[8] = tic % 9 === 0 ? 18 : 0;
  result[9] = tic % 13 === 0 ? 24 : 0;
  result[10] = tic % 6 === 0 ? 0x02 : 0;
  result[11] = tic % 6 === 0 ? 0x80 : 0;
  return result;
}

function canonicalBytes() {
  const length = canonicalStateLength();
  if (!Number.isInteger(length) || length < 1 || length > 16 * 1024 * 1024) {
    throw new Error(`invalid canonical length ${length}`);
  }
  const result = Buffer.alloc(length);
  for (let offset = 0; offset < length; offset += 32767) {
    const size = Math.min(32767, length - offset);
    const chunk = canonicalStateChunk(offset, size);
    if (chunk.length !== size) throw new Error(`short canonical chunk at ${offset}`);
    result.set(chunk, offset);
  }
  return result;
}

initialize();
const baseline = [];
for (let tic = 1; tic <= sampleTics; tic += 1) {
  if (stepMultiplayerAuthoritative(2, 3, commands(tic)) !== tic) {
    throw new Error(`baseline frontier mismatch at tic ${tic}`);
  }
  baseline.push(canonicalBytes());
}
release();

initialize();
const frameHashes = [new Set(), new Set()];
const firstFrameStats = [];
let renderCanonicalMutations = 0;
let firstRenderMismatches = [];
let mappedResidueBytes = 0;
let mappedResidueMax = 0;
for (let tic = 1; tic <= sampleTics; tic += 1) {
  if (stepMultiplayerAuthoritative(2, 3, commands(tic)) !== tic) {
    throw new Error(`presentation frontier mismatch at tic ${tic}`);
  }
  const beforeRender = canonicalBytes();
  if (!beforeRender.equals(baseline[tic - 1])) {
    const expected = baseline[tic - 1];
    const mismatches = [];
    let mismatchCount = 0;
    let unexpected = false;
    for (let index = 0; index < expected.length; index += 1) {
      if (expected[index] !== beforeRender[index]) {
        mismatchCount += 1;
        const location = canonicalOffsetDescription(index);
        if (!/^save\.line\[\d+\]\.flags\+byte1$/.test(location)
            || ((expected[index] ^ beforeRender[index]) & ~1) !== 0) {
          unexpected = true;
        }
        if (mismatches.length < 32) {
          mismatches.push([index, expected[index], beforeRender[index], location]);
        }
      }
    }
    if (unexpected || expected.length !== beforeRender.length) {
      throw new Error(
        `render residue changed authoritative world state at tic ${tic}: `
        + JSON.stringify({expectedBytes: expected.length,
          actualBytes: beforeRender.length, mismatches, firstRenderMismatches}),
      );
    }
    mappedResidueBytes += mismatchCount;
    mappedResidueMax = Math.max(mappedResidueMax, mismatchCount);
  }
  for (let player = 0; player < 2; player += 1) {
    const frame = renderPlayerFrame(player);
    if (!(frame instanceof Uint8Array) || frame.length !== 320 * 200) {
      throw new Error(`invalid player ${player} frame at tic ${tic}`);
    }
    frameHashes[player].add(createHash('sha256').update(frame).digest('hex'));
    if (tic === 1) {
      const hud = frame.subarray(320 * 168);
      firstFrameStats[player] = {
        sha256: createHash('sha256').update(frame).digest('hex'),
        distinct: new Set(frame).size,
        nonzero: frame.reduce((count, value) => count + (value === 0 ? 0 : 1), 0),
        hudSha256: createHash('sha256').update(hud).digest('hex'),
        hudDistinct: new Set(hud).size,
        hudNonzero: hud.reduce(
          (count, value) => count + (value === 0 ? 0 : 1), 0),
      };
      if (frameDumpDirectory) {
        fs.mkdirSync(frameDumpDirectory, {recursive: true});
        fs.writeFileSync(`${frameDumpDirectory}/player-${player}-tic-1.pgm`,
          Buffer.concat([
            Buffer.from('P5\n320 200\n255\n', 'ascii'),
            Buffer.from(frame),
          ]));
      }
    }
  }
  const afterRender = canonicalBytes();
  if (!afterRender.equals(beforeRender)) {
    renderCanonicalMutations += 1;
    if (firstRenderMismatches.length === 0) {
      for (let index = 0;
        index < beforeRender.length && firstRenderMismatches.length < 32;
        index += 1) {
        if (beforeRender[index] !== afterRender[index]) {
          firstRenderMismatches.push(
            [tic, index, beforeRender[index], afterRender[index]]);
        }
      }
    }
  }
}
if (frameHashes[0].size < 2 || frameHashes[1].size < 2) {
  throw new Error(`presentation frames are not moving: ${
    frameHashes[0].size}/${frameHashes[1].size} ${JSON.stringify(firstFrameStats)}`);
}
for (let player = 0; player < 2; player += 1) {
  if (firstFrameStats[player].hudDistinct < 16
      || firstFrameStats[player].hudNonzero < 8000) {
    throw new Error(`presentation HUD is incomplete: ${
      JSON.stringify(firstFrameStats)} ${presentationDiagnostic()}`);
  }
}
const expectedHudSha256 = [
  // These include the animated face patch. The earlier presentation root
  // painted that 24x29 region with one flat palette index and therefore
  // passed density checks while visibly omitting Doomguy.
  'dd2e30a5ca3d0ecdfbce78bf82bdc03898bffc19d201e571fee769eea50bf032',
  '96882b5d2d1fceed8d83437b13f3976eec2c140ee2b3d8c2cbaada0af665a0af',
];
for (let player = 0; player < expectedHudSha256.length; player += 1) {
  if (firstFrameStats[player].hudSha256 !== expectedHudSha256[player]) {
    throw new Error(`presentation HUD semantic golden mismatch for player ${
      player}: ${firstFrameStats[player].hudSha256} expected ${
      expectedHudSha256[player]}`);
  }
}
console.log(
  `PMLE_TEAVM_PRESENTATION|PASS|tics=${sampleTics}`
  + `|pov0_unique=${frameHashes[0].size}|pov1_unique=${frameHashes[1].size}`
  + `|pov0_hud_sha256=${firstFrameStats[0].hudSha256}`
  + `|pov0_hud_distinct=${firstFrameStats[0].hudDistinct}`
  + `|pov0_hud_nonzero=${firstFrameStats[0].hudNonzero}`
  + `|pov1_hud_sha256=${firstFrameStats[1].hudSha256}`
  + `|pov1_hud_distinct=${firstFrameStats[1].hudDistinct}`
  + `|pov1_hud_nonzero=${firstFrameStats[1].hudNonzero}`
  + `|render_canonical_mutations=${renderCanonicalMutations}`
  + `|mapped_line_residue_bytes=${mappedResidueBytes}`
  + `|mapped_line_residue_max=${mappedResidueMax}`
  + `|next_tic_world_residue=0|presentation=${presentationDiagnostic()}`
  + `|memory=${memoryDiagnostic()}`,
);
release();
