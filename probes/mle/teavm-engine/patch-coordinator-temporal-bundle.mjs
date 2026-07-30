#!/usr/bin/env node

import {createHash} from 'node:crypto';
import {readFileSync,writeFileSync} from 'node:fs';

const [inputPath,outputPath]=process.argv.slice(2);
if(!inputPath||!outputPath) {
  throw new Error(
    'usage: patch-coordinator-temporal-bundle.mjs INPUT OUTPUT');
}
const sha=value=>createHash('sha256').update(value).digest('hex');
let source=readFileSync(inputPath,'utf8');
const inputSha=sha(source);
const replaceOnce=(before,after,label)=>{
  const first=source.indexOf(before);
  if(first<0||source.indexOf(before,first+before.length)>=0) {
    throw new Error(`temporal bundle ${label} marker is not unique`);
  }
  source=source.slice(0,first)+after+source.slice(first+before.length);
};

const helper=`
function persistTemporalMatchViewBatch(
    payloads, matchId, playerMask, membershipEpoch, generation) {
  if (!Array.isArray(payloads) || payloads.length < 1 || payloads.length > 6
      || (playerMask !== 1 && playerMask !== 3)) {
    throw new Error('invalid temporal match-view batch');
  }
  const firstTic = payloads[0].tic;
  const lastTic = payloads[payloads.length - 1].tic;
  for (let index = 0; index < payloads.length; index++) {
    if (payloads[index].tic !== firstTic + index
        || !(payloads[index].payload instanceof Uint8Array)
        || payloads[index].payload.byteLength
          !== MATCH_VIEW_HEADER_BYTES
            + (playerMask === 3 ? 2 : 1) * FRAME_BYTES) {
      throw new Error('invalid temporal match-view batch sequence');
    }
  }
  let persistedBytes = 0;
  for (let playerSlot = 0; playerSlot < 2; playerSlot++) {
    if ((playerMask & (1 << playerSlot)) === 0) continue;
    const bytes = new Uint8Array(
      LIVE_BATCH_HEADER_BYTES
        + payloads.length * (LIVE_BATCH_RECORD_BYTES + FRAME_BYTES));
    bytes.set([68, 80, 66, 50], 0); // DPB2.
    putU32Be(bytes, 4, payloads.length);
    for (let index = 0; index < payloads.length; index++) {
      const entry = payloads[index];
      const record = LIVE_BATCH_HEADER_BYTES
        + index * (LIVE_BATCH_RECORD_BYTES + FRAME_BYTES);
      putU32Be(bytes, record, entry.tic >>> 0);
      bytes[record + 4] = entry.payload[9 + playerSlot];
      bytes[record + 5] = entry.payload[11];
      bytes.set(entry.payload.subarray(
        MATCH_VIEW_HEADER_BYTES + playerSlot * FRAME_BYTES,
        MATCH_VIEW_HEADER_BYTES + (playerSlot + 1) * FRAME_BYTES),
      record + LIVE_BATCH_RECORD_BYTES);
    }
    const result = oracledb.defaultConnection().execute(
      \`update doom_match_live_frame_batch
          set first_tic=:firstTic,last_tic=:lastTic,
              frame_count=:frameCount,payload_bytes=:payloadBytes,
              payload_blob=empty_blob(),published_at=systimestamp
        where match_id=:matchId
          and player_slot=:playerSlot
          and ring_slot=:ringSlot
          and membership_epoch=:membershipEpoch
          and generation=:generation
        returning payload_blob into :payload\`,
      {
        firstTic,
        lastTic,
        frameCount: payloads.length,
        payloadBytes: bytes.byteLength,
        matchId,
        playerSlot,
        ringSlot: lastTic % 64,
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
      throw new Error('temporal match-view batch locator acquisition failed');
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
    persistedBytes += bytes.byteLength;
  }
  return persistedBytes;
}

`;
replaceOnce(
  'function persistTemporalMatchView(\n',
  helper+'function persistTemporalMatchView(\n',
  'helper insertion');
replaceOnce(
  `    for (const entry of prepared.temporalPayloads) {
      persistTemporalMatchView(
        entry.payload, matchId, playerMask,
        membershipEpoch, generation, entry.tic);
    }
`,
  `    persistTemporalMatchViewBatch(
      prepared.temporalPayloads, matchId, playerMask,
      membershipEpoch, generation);
`,
  'publication');

const output=Buffer.from(source);
writeFileSync(outputPath,output);
process.stdout.write(
  'PMLE_TEMPORAL_BUNDLE_PATCH|PASS'
    +`|input_sha256=${inputSha}`
    +`|output_bytes=${output.byteLength}`
    +`|output_sha256=${sha(output)}`
    +'|persistence=DPB2_PER_PLAYER_PER_TEMPORAL_BUNDLE\n');
