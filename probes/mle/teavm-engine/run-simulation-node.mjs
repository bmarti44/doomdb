import fs from 'node:fs';
import {
  allocateTablePack,
  allocateIwad,
  allocateCheckpoint,
  canonicalState,
  canonicalStateChunk,
  canonicalStateLength,
  checkpointChunk,
  checkpointLength,
  currentState,
  fixedDivChecksum,
  fixedMulChecksum,
  initialize,
  initializeMultiplayer,
  initializeMultiplayerGame,
  loadIwadChunk,
  loadCheckpointChunk,
  loadTablePackChunk,
  memoryDiagnostic,
  release,
  restoreCheckpoint,
  step,
  stepBare,
  stepMultiplayerAuthoritative,
  stepMultiplayerBare,
} from './target/javascript/doom-mle-simulation-engine-headless.js';

const iwadPath = process.argv[2];
const tablePackPath = process.argv[3];
const expectedFixedMulChecksum = Number(process.argv[4]);
const expectedFixedDivChecksum = Number(process.argv[5]);
if (!iwadPath || !tablePackPath || !Number.isInteger(expectedFixedMulChecksum)
    || !Number.isInteger(expectedFixedDivChecksum)) {
  throw new Error(
    'usage: node run-simulation-node.mjs IWAD CANONICAL_TABLE_PACK'
      + ' FIXED_MUL_CHECKSUM FIXED_DIV_CHECKSUM',
  );
}
const iwad = fs.readFileSync(iwadPath);
const tablePack = fs.readFileSync(tablePackPath);
const chunkBytes = 1024 * 1024;

const actualFixedMulChecksum = fixedMulChecksum();
if (actualFixedMulChecksum !== expectedFixedMulChecksum) {
  throw new Error(`TeaVM FixedMul checksum mismatch: ${JSON.stringify({
    expected: expectedFixedMulChecksum,
    actual: actualFixedMulChecksum,
  })}`);
}
const actualFixedDivChecksum = fixedDivChecksum();
if (actualFixedDivChecksum !== expectedFixedDivChecksum) {
  throw new Error(`TeaVM FixedDiv checksum mismatch: ${JSON.stringify({
    expected: expectedFixedDivChecksum,
    actual: actualFixedDivChecksum,
  })}`);
}

function loadIwad() {
  allocateIwad(iwad.length);
  for (let offset = 0; offset < iwad.length; offset += chunkBytes) {
    const chunk = iwad.subarray(offset, Math.min(iwad.length, offset + chunkBytes));
    const loaded = loadIwadChunk(offset, chunk);
    if (loaded !== offset + chunk.length) {
      throw new Error(`short IWAD load at ${offset}: ${loaded}`);
    }
  }
}

function loadCanonicalTables(pack = tablePack) {
  allocateTablePack(pack.length);
  for (let offset = 0; offset < pack.length; offset += chunkBytes) {
    const chunk = pack.subarray(
      offset,
      Math.min(pack.length, offset + chunkBytes),
    );
    const loaded = loadTablePackChunk(offset, chunk);
    if (loaded !== offset + chunk.length) {
      throw new Error(`short canonical-table load at ${offset}: ${loaded}`);
    }
  }
}

loadIwad();
const invalidTablePack = Buffer.from(tablePack);
invalidTablePack[0] ^= 0xff;
loadCanonicalTables(invalidTablePack);
let rejectedInvalidPack = false;
try {
  initialize();
} catch {
  rejectedInvalidPack = true;
}
release();
if (!rejectedInvalidPack) {
  throw new Error('canonical-table pack with invalid magic was accepted');
}

function run() {
  loadIwad();
  loadCanonicalTables();
  const initial = initialize();
  const first = step(25, 0, -640, 0);
  const second = step(0, -24, 0, 0);
  const current = currentState();
  const canonical = canonicalState();
  return {initial, first, second, current, canonical};
}

const firstRun = run();
release();
const secondRun = run();
if (JSON.stringify(firstRun) !== JSON.stringify(secondRun)) {
  throw new Error(`non-deterministic resident simulation: ${JSON.stringify({firstRun, secondRun})}`);
}
if (!firstRun.initial.includes('|gamestate=GS_LEVEL|')) {
  throw new Error(`E1M1 initialization failed: ${firstRun.initial}`);
}
if (!firstRun.second.includes('|gametic=2|leveltime=2|')) {
  throw new Error(`tic advancement failed: ${firstRun.second}`);
}

release();
loadIwad();
loadCanonicalTables();
initialize();
if (stepBare(25, 0, -640, 0) !== 1 || stepBare(0, -24, 0, 0) !== 2) {
  throw new Error('bare-step gametic advancement failed');
}
const bareState = currentState();
if (bareState !== firstRun.current) {
  throw new Error(`bare-step semantic divergence: ${JSON.stringify({
    expected: firstRun.current,
    actual: bareState,
  })}`);
}
const bareCanonical = canonicalState();
if (bareCanonical !== firstRun.canonical) {
  throw new Error(`bare-step canonical-state divergence: ${JSON.stringify({
    expected: firstRun.canonical,
    actual: bareCanonical,
  })}`);
}

const checkpointState = currentState();
const checkpointCanonical = canonicalState();
function canonicalBytes() {
  const length = canonicalStateLength();
  const result = new Uint8Array(length);
  for (let offset = 0; offset < length; offset += 32767) {
    const size = Math.min(32767, length - offset);
    result.set(canonicalStateChunk(offset, size), offset);
  }
  return result;
}
function checkpointBytes() {
  const length = checkpointLength();
  const result = new Uint8Array(length);
  for (let offset = 0; offset < length; offset += 32767) {
    const size = Math.min(32767, length - offset);
    result.set(checkpointChunk(offset, size), offset);
  }
  return result;
}
function loadCheckpoint(checkpoint) {
  allocateCheckpoint(checkpoint.length);
  for (let offset = 0; offset < checkpoint.length; offset += 32767) {
    const chunk = checkpoint.subarray(offset, Math.min(checkpoint.length, offset + 32767));
    if (loadCheckpointChunk(offset, chunk) !== offset + chunk.length) {
      throw new Error(`short checkpoint load at ${offset}`);
    }
  }
}
const expectedCanonicalBytes = canonicalBytes();
const checkpoint = checkpointBytes();
stepBare(25, 0, -640, 0);
loadCheckpoint(checkpoint);
const restored = restoreCheckpoint(2);
if (!restored.includes('|gametic=2|leveltime=2|')
    || currentState().replace('state=current', 'state=restored') !== restored) {
  throw new Error(`checkpoint restore state mismatch: ${restored}`);
}
if (currentState() !== checkpointState || canonicalState() !== checkpointCanonical) {
  const actualCanonicalBytes = canonicalBytes();
  const mismatch = expectedCanonicalBytes.findIndex(
    (value, index) => value !== actualCanonicalBytes[index]);
  throw new Error(`checkpoint restore semantic divergence: ${JSON.stringify({
    expected: checkpointState,
    actual: currentState(),
    expectedCanonical: checkpointCanonical,
    actualCanonical: canonicalState(),
    mismatch,
    expectedBytes: Array.from(expectedCanonicalBytes.slice(mismatch, mismatch + 24)),
    actualBytes: Array.from(actualCanonicalBytes.slice(mismatch, mismatch + 24)),
  })}`);
}

function multiplayerCommands(tic) {
  const result = new Uint8Array(32);
  result[0] = tic % 5 === 0 ? 0x19 : 0;
  result[7] = tic % 23 === 0 ? 1 : 0;
  result[9] = tic % 7 === 0 ? 0xe8 : 0;
  if (tic % 11 === 0) {
    result[18] = 0xfd;
    result[19] = 0x80;
  }
  result[24] = tic % 13 === 0 ? 0xf0 : 0;
  return result;
}

const timings = [];
for (let tic = 0; tic < 300; tic++) {
  const started = performance.now();
  stepBare(
    tic % 7 === 0 ? 25 : 0,
    tic % 11 === 0 ? -24 : 0,
    tic % 5 === 0 ? -640 : 0,
    0,
  );
  timings.push(performance.now() - started);
}
const lastState = currentState();
if (!lastState.includes('|gametic=302|leveltime=302|')) {
  throw new Error(`300-tic advancement failed: ${lastState}`);
}
const sorted = timings.toSorted((a, b) => a - b);
const percentile = value => sorted[Math.ceil(sorted.length * value) - 1];
const timing = {
  p50Ms: percentile(0.50),
  p95Ms: percentile(0.95),
  maxMs: sorted.at(-1),
};
release();

loadIwad();
loadCanonicalTables();
initializeMultiplayer(4);
for (let tic = 1; tic <= 100; tic++) {
  if (stepMultiplayerBare(4, multiplayerCommands(tic)) !== tic) {
    throw new Error(`multiplayer checkpoint setup failed at tic ${tic}`);
  }
}
const multiplayerCanonical = canonicalBytes();
const multiplayerCheckpoint = checkpointBytes();
for (let tic = 101; tic <= 430; tic++) {
  if (stepMultiplayerBare(4, multiplayerCommands(tic)) !== tic) {
    throw new Error(`multiplayer expected continuation failed at tic ${tic}`);
  }
}
const expectedMultiplayerContinuation = canonicalBytes();
release();
loadIwad();
loadCanonicalTables();
initializeMultiplayer(4);
loadCheckpoint(multiplayerCheckpoint);
const multiplayerRestore = restoreCheckpoint(100);
const restoredMultiplayerCanonical = canonicalBytes();
const multiplayerMismatch = multiplayerCanonical.findIndex(
  (value, index) => value !== restoredMultiplayerCanonical[index]);
if (!multiplayerRestore.includes('|gametic=100|') || multiplayerMismatch !== -1) {
  throw new Error(`multiplayer checkpoint restore divergence: ${JSON.stringify({
    restored: multiplayerRestore,
    expectedLength: multiplayerCanonical.length,
    actualLength: restoredMultiplayerCanonical.length,
    memory: memoryDiagnostic(),
    saveLength: new DataView(multiplayerCanonical.buffer).getUint32(4),
    mismatch: multiplayerMismatch,
    expectedBytes: Array.from(multiplayerCanonical.slice(
      multiplayerMismatch, multiplayerMismatch + 32)),
    actualBytes: Array.from(restoredMultiplayerCanonical.slice(
      multiplayerMismatch, multiplayerMismatch + 32)),
  })}`);
}
for (let tic = 101; tic <= 430; tic++) {
  if (stepMultiplayerBare(4, multiplayerCommands(tic)) !== tic) {
    throw new Error(`multiplayer restored continuation failed at tic ${tic}`);
  }
}
const actualMultiplayerContinuation = canonicalBytes();
const continuationMismatch = expectedMultiplayerContinuation.findIndex(
  (value, index) => value !== actualMultiplayerContinuation[index]);
if (continuationMismatch !== -1) {
  throw new Error(`multiplayer checkpoint continuation divergence: ${JSON.stringify({
    expectedLength: expectedMultiplayerContinuation.length,
    actualLength: actualMultiplayerContinuation.length,
    mismatch: continuationMismatch,
    expectedBytes: Array.from(expectedMultiplayerContinuation.slice(
      continuationMismatch, continuationMismatch + 32)),
    actualBytes: Array.from(actualMultiplayerContinuation.slice(
      continuationMismatch, continuationMismatch + 32)),
  })}`);
}
release();

function multiplayerRun() {
  loadIwad();
  loadCanonicalTables();
  const initial = initializeMultiplayer(2);
  for (let tic = 1; tic <= 60; tic += 1) {
    const vector = new Uint8Array(16);
    vector[0] = tic % 5 === 0 ? 25 : 0;
    vector[7] = tic % 23 === 0 ? 1 : 0;
    vector[9] = tic % 7 === 0 ? 232 : 0;
    vector[10] = tic % 11 === 0 ? 0xfd : 0;
    vector[11] = tic % 11 === 0 ? 0x80 : 0;
    if (stepMultiplayerBare(2, vector) !== tic) {
      throw new Error(`multiplayer advancement failed at ${tic}`);
    }
  }
  return {initial, state: currentState(), canonical: canonicalState()};
}
const multiplayerFirst = multiplayerRun();
release();
const multiplayerSecond = multiplayerRun();
if (JSON.stringify(multiplayerFirst) !== JSON.stringify(multiplayerSecond)) {
  throw new Error(`non-deterministic multiplayer simulation: ${JSON.stringify({
    multiplayerFirst,
    multiplayerSecond,
  })}`);
}
const multiplayerMemory = memoryDiagnostic();
release();
loadIwad();
loadCanonicalTables();
const deathmatchInitial = initializeMultiplayerGame(2, 1, 3, 1, 1);
if (!deathmatchInitial.includes('|gametic=0|')
    || stepMultiplayerAuthoritative(2, 1, new Uint8Array(32)) !== 1) {
  throw new Error(`generalized multiplayer initialization failed: ${deathmatchInitial}`);
}
const inactiveVector = new Uint8Array(32);
inactiveVector[8] = 1;
let rejectedInactiveCommand = false;
try {
  stepMultiplayerAuthoritative(2, 1, inactiveVector);
} catch (error) {
  rejectedInactiveCommand = String(error).includes('inactive player command 1');
}
if (!rejectedInactiveCommand) {
  throw new Error('authoritative step accepted an inactive-player command');
}
release();
function membershipVector(tic, membership) {
  const vector = new Uint8Array(32);
  vector[0] = tic % 5 === 0 ? 25 : 0;
  vector[7] = tic % 23 === 0 ? 1 : 0;
  if ((membership & 2) !== 0) vector[9] = tic % 7 === 0 ? 232 : 0;
  return vector;
}
function initializeMembershipScenario() {
  loadIwad();
  loadCanonicalTables();
  initializeMultiplayerGame(2, 0, 3, 1, 1);
}
initializeMembershipScenario();
for (let tic = 1; tic <= 61; tic += 1) {
  stepMultiplayerAuthoritative(2, tic < 41 ? 3 : tic <= 60 ? 1 : 3,
    membershipVector(tic, tic < 41 ? 3 : tic <= 60 ? 1 : 3));
}
const uninterruptedRejoin = canonicalBytes();
release();
initializeMembershipScenario();
for (let tic = 1; tic <= 60; tic += 1) {
  const membership = tic < 41 ? 3 : 1;
  stepMultiplayerAuthoritative(2, membership, membershipVector(tic, membership));
}
const inactiveCheckpoint = checkpointBytes();
release();
initializeMembershipScenario();
loadCheckpoint(inactiveCheckpoint);
const inactiveRestore = restoreCheckpoint(60);
stepMultiplayerAuthoritative(2, 3, membershipVector(61, 3));
const recoveredRejoin = canonicalBytes();
if (uninterruptedRejoin.length !== recoveredRejoin.length
    || uninterruptedRejoin.some((value, index) => value !== recoveredRejoin[index])) {
  throw new Error(`membership checkpoint rejoin divergence: ${JSON.stringify({
    restore: inactiveRestore,
    uninterruptedLength: uninterruptedRejoin.length,
    recoveredLength: recoveredRejoin.length,
  })}`);
}
release();
loadIwad();
loadCanonicalTables();
let rejectedInvalidGame = false;
try {
  initializeMultiplayerGame(2, 2, 3, 1, 1);
} catch (error) {
  rejectedInvalidGame = String(error).includes('deathmatch 2');
}
if (!rejectedInvalidGame) {
  throw new Error('generalized multiplayer initializer accepted invalid deathmatch mode');
}
console.log(`PASS PMLE-TEAVM-SIMULATION ${JSON.stringify({
  firstRun,
  timing,
  lastState,
  multiplayer: multiplayerFirst,
  generalizedMultiplayer:
    'deathmatch=pass|membership=pass|membershipCheckpointRejoin=pass|invalid=reject',
  memory: multiplayerMemory,
})}`);
release();
