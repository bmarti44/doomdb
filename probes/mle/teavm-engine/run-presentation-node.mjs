import {createHash} from 'node:crypto';
import fs from 'node:fs';
import path from 'node:path';
import {pathToFileURL} from 'node:url';

const artifactPath = process.argv[4]
  ?? './target/javascript/doom-mle-presentation-engine-headless.js';
const presentationModule = await import(pathToFileURL(path.resolve(
  import.meta.dirname, artifactPath)).href);
const {
  allocateIwad,
  allocateTablePack,
  canonicalStateChunk,
  canonicalStateLength,
  canonicalOffsetDescription,
  capturedFrameCommandCount,
  enableFrameCommandMetrics,
  frameAssetCount,
  frameAssetPackChunk,
  frameAssetPackLength,
  frameCommandChunk,
  frameCommandLength,
  frameCommandMetrics,
  initializeMultiplayerGame,
  loadIwadChunk,
  loadTablePackChunk,
  memoryDiagnostic,
  presentationPlayerSnapshot,
  presentationWorldSnapshotChunk,
  presentationWorldSnapshotLength,
  presentationDiagnostic,
  release,
  renderCapturedPlayerFrameByRef,
  renderPlayerFrame,
  stepMultiplayerAuthoritative,
} = presentationModule;

let retainedDatabaseFrame;
function renderPlayerFrameDatabaseView(playerSlot) {
  retainedDatabaseFrame = renderPlayerFrame(playerSlot);
  return retainedDatabaseFrame;
}
function renderPlayerFrameLength(playerSlot) {
  return renderPlayerFrameDatabaseView(playerSlot).byteLength;
}
function renderPlayerFrameChunk(offset, length) {
  if (!(retainedDatabaseFrame instanceof Uint8Array)) {
    throw new Error('no rendered database frame is retained');
  }
  return retainedDatabaseFrame.subarray(offset, offset + length);
}

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
const commandMetricsEnabled =
  process.env.PMLE_PRESENTATION_COMMAND_METRICS === 'YES';
const liveCaptureEnabled =
  process.env.PMLE_PRESENTATION_LIVE_CAPTURE === 'YES';
const commandPackPath = process.env.PMLE_PRESENTATION_COMMAND_PACK;
const commandFrames = [];
let commandFrameCount = 0;
let liveCaptureExactFrames = 0;
let liveCaptureMinCommands = Number.POSITIVE_INFINITY;
let liveCaptureMaxCommands = 0;

function decodeCapturedFrame(encoded) {
  if (!ArrayBuffer.isView(encoded) || encoded.length !== 320 * 200) {
    throw new Error(`invalid live captured frame length ${encoded?.length}`);
  }
  const decoded = Buffer.alloc(320 * 200);
  for (let x = 0; x < 320; x += 1) {
    for (let y = 0; y < 168; y += 1) {
      decoded[y * 320 + x] = encoded[x * 168 + y];
    }
  }
  decoded.set(encoded.subarray(320 * 168), 320 * 168);
  return decoded;
}

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
if (commandMetricsEnabled) {
  if (typeof enableFrameCommandMetrics !== 'function'
      || typeof frameCommandMetrics !== 'function') {
    throw new Error('presentation command metrics exports are unavailable');
  }
  enableFrameCommandMetrics();
}
const frameHashes = [new Set(), new Set()];
const playerSnapshotHashes = [new Set(), new Set()];
const worldSnapshotHashes = [new Set(), new Set()];
const worldSnapshotStats = [null, null];
const firstFrameStats = [];
const retainedBrowserFrames = [];
const retainedBrowserFrameHashes = [];
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
    const playerSnapshot = presentationPlayerSnapshot(player);
    if (!(playerSnapshot instanceof Uint8Array)
        || playerSnapshot.byteLength !== 32) {
      throw new Error(
        `invalid player ${player} presentation snapshot at tic ${tic}`,
      );
    }
    const playerX = new DataView(
      playerSnapshot.buffer,
      playerSnapshot.byteOffset,
      playerSnapshot.byteLength,
    ).getInt32(0, true);
    const playerY = new DataView(
      playerSnapshot.buffer,
      playerSnapshot.byteOffset,
      playerSnapshot.byteLength,
    ).getInt32(4, true);
    if (playerX === 0 && playerY === 0) {
      throw new Error(`empty player ${player} presentation pose at tic ${tic}`);
    }
    playerSnapshotHashes[player].add(
      createHash('sha256').update(playerSnapshot).digest('hex'),
    );
    const worldLength = presentationWorldSnapshotLength(player);
    if (!Number.isInteger(worldLength)
        || worldLength < 128 || worldLength > 32767) {
      throw new Error(
        `invalid player ${player} world snapshot length ${worldLength}`,
      );
    }
    const worldSnapshot = Buffer.alloc(worldLength);
    for (let offset = 0; offset < worldLength; offset += 4096) {
      const size = Math.min(4096, worldLength - offset);
      const chunk = presentationWorldSnapshotChunk(offset, size);
      if (!(chunk instanceof Uint8Array) || chunk.length !== size) {
        throw new Error(
          `short player ${player} world snapshot chunk at ${tic}/${offset}`,
        );
      }
      worldSnapshot.set(chunk, offset);
    }
    const world = new DataView(
      worldSnapshot.buffer,
      worldSnapshot.byteOffset,
      worldSnapshot.byteLength,
    );
    const sectorCount = world.getInt32(16, true);
    const mobjCount = world.getInt32(20, true);
    const sectorOffset = world.getInt32(24, true);
    const mobjOffset = world.getInt32(28, true);
    const sideCount = world.getInt32(192, true);
    const sideOffset = world.getInt32(196, true);
    if (world.getUint32(0, true) !== 0x324c5644
        || world.getInt32(4, true) !== 2
        || world.getInt32(8, true) !== tic
        || world.getInt32(12, true) !== player
        || sectorCount < 1 || mobjCount < 2
        || sectorOffset !== 208
        || sideCount < 1
        || sideOffset !== sectorOffset + sectorCount * 16
        || world.getInt32(200, true) !== 8
        || world.getInt32(204, true) !== sectorOffset
        || mobjOffset !== sideOffset + sideCount * 8
        || world.getInt32(32, true) !== worldLength
        || worldLength !== mobjOffset + mobjCount * 32) {
      throw new Error(
          `invalid player ${player} DVL2 snapshot at tic ${tic}: `
          + JSON.stringify({
            magic: world.getUint32(0, true).toString(16),
            version: world.getInt32(4, true),
            tic: world.getInt32(8, true),
            slot: world.getInt32(12, true),
            sectorCount,
            mobjCount,
            sectorOffset,
            sideCount,
            sideOffset,
            mobjOffset,
            worldLength,
          }),
      );
    }
    if (world.getInt32(36, true) !== playerX
        || world.getInt32(40, true) !== playerY) {
      throw new Error(
        `player ${player} compact/world presentation pose mismatch at tic ${tic}`,
      );
    }
    if (tic === 1) {
      worldSnapshotStats[player] = {worldLength, sectorCount, mobjCount};
      let rejected = false;
      try {
        presentationWorldSnapshotChunk(worldLength, 1);
      } catch {
        rejected = true;
      }
      if (!rejected) {
        throw new Error('world snapshot accepted an out-of-range chunk');
      }
    }
    worldSnapshotHashes[player].add(
      createHash('sha256').update(worldSnapshot).digest('hex'),
    );
    let capturedCommands;
    if (commandMetricsEnabled) frameCommandMetrics(1);
    const frameLength = renderPlayerFrameLength(player);
    if (commandMetricsEnabled) {
      const metrics = frameCommandMetrics(0);
      if (commandPackPath) {
        const commandBytes = frameCommandLength();
        if (!Number.isInteger(commandBytes) || commandBytes < 1
            || commandBytes > 1024 * 1024 || commandBytes % 28 !== 0) {
          throw new Error(`invalid command bytes ${commandBytes}`);
        }
        const commands = Buffer.alloc(commandBytes);
        for (let offset = 0; offset < commandBytes; offset += 32767) {
          const size = Math.min(32767, commandBytes - offset);
          const chunk = frameCommandChunk(offset, size);
          if (!ArrayBuffer.isView(chunk) || chunk.length !== size) {
            throw new Error(
              `short command chunk at ${tic}/${player}/${offset}`,
            );
          }
          commands.set(chunk, offset);
        }
        capturedCommands = commands;
      }
      process.stdout.write(
        `PMLE_PRESENTATION_COMMANDS|PASS|tic=${tic}|player=${player}|`
        + `${metrics}\n`,
      );
      frameCommandMetrics(1);
    }
    if (frameLength !== 320 * 200) {
      throw new Error(`invalid player ${player} retained frame length at tic ${tic}`);
    }
    const frame = Buffer.alloc(frameLength);
    for (let offset = 0; offset < frameLength; offset += 32767) {
      const size = Math.min(32767, frameLength - offset);
      const chunk = renderPlayerFrameChunk(offset, size);
      if (!(chunk instanceof Uint8Array) || chunk.length !== size) {
        throw new Error(
          `invalid player ${player} retained frame chunk at tic ${tic}/${offset}`,
        );
      }
      frame.set(chunk, offset);
    }
    if (capturedCommands) {
      const header = Buffer.alloc(16);
      header.writeUInt32LE(tic, 0);
      header.writeUInt32LE(player, 4);
      header.writeUInt32LE(capturedCommands.length, 8);
      header.writeUInt32LE(frame.length, 12);
      const fullDigest = createHash('sha256').update(frame).digest();
      const viewportDigest = createHash('sha256')
        .update(frame.subarray(0, 320 * 168)).digest();
      commandFrames.push(
        header, capturedCommands, fullDigest, viewportDigest,
        Buffer.from(frame.subarray(320 * 168)));
      commandFrameCount += 1;
    }
    if (liveCaptureEnabled) {
      if (typeof renderCapturedPlayerFrameByRef !== 'function'
          || typeof capturedFrameCommandCount !== 'function') {
        throw new Error('live command raster exports are unavailable');
      }
      const encoded = renderCapturedPlayerFrameByRef(player);
      const capturedFrame = decodeCapturedFrame(encoded);
      const count = capturedFrameCommandCount();
      if (!Number.isInteger(count) || count < 1 || count > 100_000) {
        throw new Error(`invalid live command count ${count}`);
      }
      liveCaptureMinCommands = Math.min(liveCaptureMinCommands, count);
      liveCaptureMaxCommands = Math.max(liveCaptureMaxCommands, count);
      if (!capturedFrame.equals(frame)) {
        let first = -1;
        let mismatches = 0;
        for (let index = 0; index < frame.length; index += 1) {
          if (frame[index] !== capturedFrame[index]) {
            if (first < 0) first = index;
            mismatches += 1;
          }
        }
        throw new Error(
          `live command raster mismatch at tic ${tic}/player ${player}: `
          + `first=${first}|expected=${frame[first]}`
          + `|actual=${capturedFrame[first]}|mismatches=${mismatches}`,
        );
      }
      liveCaptureExactFrames += 1;
    }
    if (tic === 1) {
      const databaseView = renderPlayerFrameDatabaseView(player);
      if (!(databaseView instanceof Uint8Array)
          || !Buffer.from(databaseView).equals(frame)) {
        throw new Error(`database-view/chunked frame mismatch for player ${player}`);
      }
      const directFrame = renderPlayerFrame(player);
      if (!(directFrame instanceof Uint8Array)
          || !Buffer.from(directFrame).equals(frame)) {
        throw new Error(`direct/chunked frame mismatch for player ${player}`);
      }
      retainedBrowserFrames[player] = directFrame;
      retainedBrowserFrameHashes[player] =
        createHash('sha256').update(directFrame).digest('hex');
    }
    if (frame.length !== 320 * 200) {
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
if (worldSnapshotHashes[0].size < 2 || worldSnapshotHashes[1].size < 2) {
  throw new Error(
    `presentation world snapshots are not moving: ${
      worldSnapshotHashes[0].size}/${worldSnapshotHashes[1].size}`,
  );
}
for (let player = 0; player < retainedBrowserFrames.length; player += 1) {
  const finalHash = createHash('sha256')
    .update(retainedBrowserFrames[player]).digest('hex');
  if (finalHash !== retainedBrowserFrameHashes[player]) {
    throw new Error(
      `browser frame mutated after later renders for player ${player}`,
    );
  }
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
  + `|pov0_snapshot_unique=${playerSnapshotHashes[0].size}`
  + `|pov1_snapshot_unique=${playerSnapshotHashes[1].size}`
  + `|pov0_world_unique=${worldSnapshotHashes[0].size}`
  + `|pov1_world_unique=${worldSnapshotHashes[1].size}`
  + `|world_bytes=${worldSnapshotStats[0].worldLength}`
  + `|world_sectors=${worldSnapshotStats[0].sectorCount}`
  + `|world_mobjs=${worldSnapshotStats[0].mobjCount}`
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
if (liveCaptureEnabled) {
  console.log(
    `PMLE_PRESENTATION_LIVE_CAPTURE|PASS|frames=${liveCaptureExactFrames}`
    + `|full_frame_exact=${liveCaptureExactFrames}`
    + `|command_min=${liveCaptureMinCommands}`
    + `|command_max=${liveCaptureMaxCommands}`
    + '|layout=COLUMN_MAJOR_VIEWPORT_ROW_MAJOR_HUD'
    + '|authority=UNCHANGED|client=PIXEL_COPY_ONLY',
  );
}
if (commandPackPath) {
  if (!commandMetricsEnabled) {
    throw new Error('command pack requires command metrics');
  }
  if (fs.existsSync(commandPackPath)) {
    throw new Error(`command pack already exists: ${commandPackPath}`);
  }
  const assetBytes = frameAssetPackLength();
  const assets = Buffer.alloc(assetBytes);
  for (let offset = 0; offset < assetBytes; offset += 32767) {
    const size = Math.min(32767, assetBytes - offset);
    const chunk = frameAssetPackChunk(offset, size);
    if (!ArrayBuffer.isView(chunk) || chunk.length !== size) {
      throw new Error(`short asset chunk at ${offset}`);
    }
    assets.set(chunk, offset);
  }
  const header = Buffer.alloc(16);
  header.write('FCP1', 0, 'ascii');
  header.writeUInt32LE(4, 4);
  header.writeUInt32LE(commandFrameCount, 8);
  header.writeUInt32LE(assetBytes, 12);
  const pack = Buffer.concat([header, ...commandFrames, assets]);
  fs.mkdirSync(path.dirname(commandPackPath), {recursive: true});
  fs.writeFileSync(commandPackPath, pack, {flag: 'wx'});
  console.log(
    `PMLE_PRESENTATION_COMMAND_PACK|PASS|version=4|frames=${commandFrameCount}`
    + `|assets=${frameAssetCount()}|asset_bytes=${assetBytes}`
    + `|pack_bytes=${pack.length}`
    + `|sha256=${createHash('sha256').update(pack).digest('hex')}`,
  );
}
release();
