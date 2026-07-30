#!/usr/bin/env node

import {createHash} from 'node:crypto';
import {readFileSync, writeFileSync} from 'node:fs';

const [inputPath, outputPath] = process.argv.slice(2);
if (!inputPath || !outputPath) {
  throw new Error(
    'usage: patch-coordinator-temporal-view-bundle.mjs INPUT OUTPUT');
}
const sha = value => createHash('sha256').update(value).digest('hex');
let source = readFileSync(inputPath, 'utf8');
const inputSha = sha(source);
const replaceOnce = (before, after, label) => {
  const first = source.indexOf(before);
  if (first < 0 || source.indexOf(before, first + before.length) >= 0) {
    throw new Error(`temporal view bundle ${label} marker is not unique`);
  }
  source = source.slice(0, first) + after
    + source.slice(first + before.length);
};

const helper = `
/**
 * DPV2 persists one consecutive temporal bundle containing every authorized
 * POV through one locator. SQL authenticates the requested player and
 * extracts a DPB2 suffix on read; no combined-POV payload reaches the client.
 *
 * Header: "DPV2", first tic u32be, frame count u32be, player mask, 3 zeros.
 * Record: tic u32be, palette0, palette1/255, layout, zero, then active
 * 64,000-byte POVs in slot order.
 */
function persistTemporalCombinedViews(
    payloads, matchId, playerMask, membershipEpoch, generation) {
  if (!Array.isArray(payloads) || payloads.length < 1 || payloads.length > 6
      || (playerMask !== 1 && playerMask !== 3)) {
    throw new Error('invalid DPV2 temporal match-view bundle');
  }
  const firstTic = payloads[0].tic;
  const lastTic = payloads[payloads.length - 1].tic;
  const activePlayers = playerMask === 3 ? 2 : 1;
  const sourceBytes = MATCH_VIEW_HEADER_BYTES + activePlayers * FRAME_BYTES;
  const recordBytes = 8 + activePlayers * FRAME_BYTES;
  for (let index = 0; index < payloads.length; index++) {
    const entry = payloads[index];
    if (entry.tic !== firstTic + index
        || !(entry.payload instanceof Uint8Array)
        || entry.payload.byteLength !== sourceBytes
        || entry.payload[0] !== 68 || entry.payload[1] !== 80
        || entry.payload[2] !== 68 || entry.payload[3] !== 49
        || entry.payload[8] !== playerMask) {
      throw new Error('invalid DPV2 temporal match-view sequence');
    }
  }
  const bytes = new Uint8Array(16 + payloads.length * recordBytes);
  bytes.set([68, 80, 86, 50], 0); // DPV2.
  putU32Be(bytes, 4, firstTic >>> 0);
  putU32Be(bytes, 8, payloads.length);
  bytes[12] = playerMask;
  for (let index = 0; index < payloads.length; index++) {
    const entry = payloads[index];
    const record = 16 + index * recordBytes;
    putU32Be(bytes, record, entry.tic >>> 0);
    bytes[record + 4] = entry.payload[9];
    bytes[record + 5] = playerMask === 3 ? entry.payload[10] : 255;
    bytes[record + 6] = entry.payload[11];
    bytes.set(
      entry.payload.subarray(MATCH_VIEW_HEADER_BYTES, sourceBytes),
      record + 8);
  }
  const result = oracledb.defaultConnection().execute(
    \`update doom_match_live_frame_views
        set tic=:lastTic,player_mask=:playerMask,
            payload_bytes=:payloadBytes,payload_blob=empty_blob(),
            published_at=systimestamp
      where match_id=:matchId
        and ring_slot=mod(:lastTic,64)
        and membership_epoch=:membershipEpoch
        and generation=:generation
      returning payload_blob into :payload\`,
    {
      lastTic,
      playerMask,
      payloadBytes: bytes.byteLength,
      matchId,
      membershipEpoch,
      generation,
      payload: {
        dir: oracledb.BIND_OUT,
        type: oracledb.ORACLE_BLOB,
      },
    },
  );
  if (result.rowsAffected !== 1
      || !Array.isArray(result.outBinds.payload)
      || result.outBinds.payload.length !== 1
      || !(result.outBinds.payload[0] instanceof OracleBlob)) {
    throw new Error('DPV2 temporal match-view locator acquisition failed');
  }
  const payload = result.outBinds.payload[0];
  let opened = false;
  try {
    payload.open(OracleBlob.LOB_READWRITE);
    opened = true;
    payload.write(1, bytes);
  } catch (failure) {
    if (opened) {
      try {
        payload.close();
      } catch {
        // Preserve the write failure; the enclosing SQL call rolls back.
      }
    }
    throw failure;
  }
  payload.close();
  return bytes.byteLength;
}

`;
replaceOnce(
  'function persistTemporalMatchView(\n',
  helper + 'function persistTemporalMatchView(\n',
  'helper insertion');
replaceOnce(
  `    for (const entry of prepared.temporalPayloads) {
      persistTemporalMatchView(
        entry.payload, matchId, playerMask,
        membershipEpoch, generation, entry.tic);
    }
`,
  `    persistTemporalCombinedViews(
      prepared.temporalPayloads, matchId, playerMask,
      membershipEpoch, generation);
`,
  'publication');

const output = Buffer.from(source);
writeFileSync(outputPath, output);
process.stdout.write(
  'PMLE_TEMPORAL_VIEW_BUNDLE_PATCH|PASS'
    + `|input_sha256=${inputSha}`
    + `|output_bytes=${output.byteLength}`
    + `|output_sha256=${sha(output)}`
    + '|persistence=DPV2_COMBINED_TEMPORAL_AND_POV\n');
