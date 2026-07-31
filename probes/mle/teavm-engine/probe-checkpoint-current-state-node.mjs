import fs from 'node:fs';

const root = new URL('../../../', import.meta.url);
const modulePath = process.argv[2]
  ?? '../../../artifacts/performance/pmle-live-frame-hud/'
    + 'authority-candidate-66dd235cde82.js';
const engine = await import(new URL(modulePath, import.meta.url));
const iwad = fs.readFileSync(new URL(
  'client/dist/play/freedoom1-7323bcc168c5.bin', root));
const tables = fs.readFileSync(new URL(
  'client/dist/play/canonical-runtime-v2-058cd0df9444.bin', root));

function transfer(bytes, allocate, write) {
  if (allocate(bytes.length) !== bytes.length) {
    throw new Error('allocation mismatch');
  }
  for (let offset = 0; offset < bytes.length; offset += 32767) {
    const chunk = bytes.subarray(offset, Math.min(bytes.length, offset + 32767));
    if (write(offset, chunk) !== offset + chunk.length) {
      throw new Error(`transfer mismatch at ${offset}`);
    }
  }
}

transfer(iwad, engine.allocateIwad, engine.loadIwadChunk);
transfer(tables, engine.allocateTablePack, engine.loadTablePackChunk);
const initialized = engine.initializeMultiplayerGame(2, 0, 3, 1, 1);
if (!initialized.startsWith('state=multiplayer-initialized|gametic=0|')) {
  throw new Error(`initialization failed: ${initialized}`);
}
const command = new Uint8Array(32);
command[0] = 25;
for (let tic = 1; tic <= 512; tic += 1) {
  if (engine.stepMultiplayerAuthoritative(2, 1, command) !== tic) {
    throw new Error(`step mismatch at ${tic}`);
  }
}
const before = engine.currentState();
const bytes = engine.checkpointLength();
const after = engine.currentState();
process.stdout.write(
  `PMLE_CHECKPOINT_CURRENT_STATE|PASS|before=${before}|checkpoint_bytes=${bytes}`
    + `|after=${after}\n`);
