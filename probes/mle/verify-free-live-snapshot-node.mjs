#!/usr/bin/env node
import fs from 'node:fs';
import path from 'node:path';
import {pathToFileURL} from 'node:url';

const root = path.resolve(import.meta.dirname, '../..');
const artifactPath = process.argv[2]
  ?? path.join(root,
    'probes/mle/free-live-teavm/target/javascript/doom-mle-free-live-renderer.js');
const packPath = process.argv[3]
  ?? path.join(root, 'probes/mle/target/free-live-renderer/free-live-render.pack');
const posePath = process.argv[4]
  ?? path.join(root, 'probes/mle/target/free-live-renderer/live-dm.state-v3.bin');

for (const input of [artifactPath, packPath, posePath]) {
  if (!fs.statSync(input).isFile()) throw new Error(`missing input ${input}`);
}

const renderer = await import(pathToFileURL(artifactPath).href);
const pack = fs.readFileSync(packPath);
const poses = fs.readFileSync(posePath);
if (poses.length !== 5250 * 32) {
  throw new Error(`unexpected pose bytes ${poses.length}`);
}

renderer.allocatePack(pack.length);
for (let offset = 0; offset < pack.length; offset += 16_000) {
  renderer.loadPackChunk(offset, pack.subarray(offset, offset + 16_000));
}
if (renderer.finalizePack() !== pack.length) {
  throw new Error('renderer pack finalize mismatch');
}

const samples = [0, 1, 31, 32, 63, 127, 255, 511, 1023, 2047,
  3071, 4095, 4999, 5249];
for (const pose of samples) {
  const recorded = renderer.renderGeometry(pose);
  const snapshot = poses.subarray(pose * 32, pose * 32 + 32);
  const live = renderer.renderPlayerSnapshotGeometry(snapshot);
  if (recorded !== live) {
    throw new Error(
      `snapshot geometry mismatch pose=${pose} recorded=${recorded} live=${live}`,
    );
  }
}

let malformedRejected = false;
try {
  renderer.renderPlayerSnapshotGeometry(new Uint8Array(31));
} catch {
  malformedRejected = true;
}
if (!malformedRejected) throw new Error('malformed snapshot was accepted');

process.stdout.write(
  'PMLE_FREE_LIVE_SNAPSHOT_NODE|PASS'
  + `|records=${samples.length}|pose_bytes=${poses.length}`
  + '|snapshot_bytes=32|geometry_checksums_exact=YES'
  + '|malformed_rejected=YES|authority_boundary=LIVE_PLAYER_STATE\n',
);
