#!/usr/bin/env node

import {createHash} from 'node:crypto';
import {readFileSync, writeFileSync} from 'node:fs';

const [inputPath, outputPath] = process.argv.slice(2);
if (!inputPath || !outputPath) {
  throw new Error(
    'usage: patch-coordinator-native-temporal-synthesis.mjs INPUT OUTPUT');
}
const expectedInput =
  'a65fee9ec23e549dbe9c8b23944bb54e5468031b62488b97fe0c608a5bbaed92';
const sha = value => createHash('sha256').update(value).digest('hex');
let source = readFileSync(inputPath, 'utf8');
const inputSha = sha(source);
if (inputSha !== expectedInput) {
  throw new Error(
    `native temporal input SHA mismatch: ${inputSha} != ${expectedInput}`);
}
const replaceOnce = (before, after, label) => {
  const first = source.indexOf(before);
  if (first < 0 || source.indexOf(before, first + before.length) >= 0) {
    throw new Error(`native temporal ${label} marker is not unique`);
  }
  source = source.slice(0, first) + after
    + source.slice(first + before.length);
};

const helper = `
/**
 * Persist only the two exact MLE-rendered endpoints as EPT1, then invoke the
 * native UTL_RAW phase-mask materializer in the same database transaction.
 * The resulting DPV2 contains the identical uncompressed temporal pixels as
 * the former interpreted JS loop, but no intermediate frame leaves the DB.
 */
function persistNativeTemporalEndpoints(
    endpoints, matchId, playerMask, membershipEpoch, generation) {
  const previous = endpoints.previous;
  const current = endpoints.current;
  const previousTic = endpoints.previousTic;
  const currentTic = endpoints.currentTic;
  const players = playerMask === 3 ? 2 : 1;
  const frameBytes = players * FRAME_BYTES;
  const sourceBytes = MATCH_VIEW_HEADER_BYTES + frameBytes;
  if (!(previous instanceof Uint8Array)
      || !(current instanceof Uint8Array)
      || previous.byteLength !== sourceBytes
      || current.byteLength !== sourceBytes
      || currentTic !== previousTic + 3
      || previous[8] !== playerMask || current[8] !== playerMask) {
    throw new Error('invalid EPT1 temporal endpoint pair');
  }
  const bytes = new Uint8Array(24 + 2 * frameBytes);
  bytes.set([69, 80, 84, 49], 0); // EPT1.
  putU32Be(bytes, 4, previousTic >>> 0);
  putU32Be(bytes, 8, currentTic >>> 0);
  bytes[12] = playerMask;
  bytes[13] = 3;
  bytes.set(previous.subarray(9, 12), 16);
  bytes.set(previous.subarray(MATCH_VIEW_HEADER_BYTES), 20);
  const currentRecord = 20 + frameBytes;
  bytes.set(current.subarray(9, 12), currentRecord);
  bytes.set(current.subarray(MATCH_VIEW_HEADER_BYTES), currentRecord + 4);
  const result = oracledb.defaultConnection().execute(
    \`update doom_match_live_frame_views
        set tic=:currentTic,player_mask=:playerMask,
            payload_bytes=:payloadBytes,payload_blob=empty_blob(),
            published_at=systimestamp
      where match_id=:matchId
        and ring_slot=mod(:currentTic,64)
        and membership_epoch=:membershipEpoch
        and generation=:generation
      returning payload_blob into :payload\`,
    {
      currentTic,
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
    throw new Error('EPT1 temporal endpoint locator acquisition failed');
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
  oracledb.defaultConnection().execute(
    \`begin
       doom_mle_live_frame_transport.materialize_temporal_bundle(
         :matchId,:membershipEpoch,:generation,:currentTic);
     end;\`,
    {matchId, membershipEpoch, generation, currentTic},
  );
  return 16 + 3 * (8 + frameBytes);
}

`;
replaceOnce(
  'function persistTemporalMatchView(\n',
  helper + 'function persistTemporalMatchView(\n',
  'helper insertion');

const oldPrepare = `  if (playerMask === 1 || playerMask === 3) {
    const current = captureTemporalExact(outputOffset);
    const payloads = [];
    if (temporalSame && retainedTemporalPrevious instanceof Uint8Array
        && retainedTemporalDeferredTics.length
          === temporalInterval - 1
        && retainedTemporalPreviousTic
          === frameTic - temporalInterval) {
      for (let phase = 0;
          phase < retainedTemporalDeferredTics.length; phase++) {
        const deferredTic = retainedTemporalDeferredTics[phase];
        // Copy because the retained synthesis buffer is reused for the next
        // phase before publication begins.
        const synthesized = new Uint8Array(outputOffset);
        synthesized.set(synthesizeTemporalSoloFrame(
          retainedTemporalPrevious, current, deferredTic, outputOffset,
          phase + 1, temporalInterval));
        payloads.push({tic: deferredTic, payload: synthesized});
      }
    }
    payloads.push({tic: frameTic, payload: current});
    retainedTemporalIdentity = {
      matchId, membershipEpoch, generation, playerMask};
    retainedTemporalPrevious = current;
    retainedTemporalPreviousTic = frameTic;
    retainedTemporalDeferredTics = [];
    retainedPreparedMatchViews.temporalPayloads = payloads;
  }
`;
const newPrepare = `  if (playerMask === 1 || playerMask === 3) {
    const current = captureTemporalExact(outputOffset);
    if (temporalInterval === 3
        && temporalSame
        && retainedTemporalPrevious instanceof Uint8Array
        && retainedTemporalDeferredTics.length === 2
        && retainedTemporalPreviousTic === frameTic - 3) {
      retainedPreparedMatchViews.temporalEndpoints = {
        previous: retainedTemporalPrevious,
        current,
        previousTic: retainedTemporalPreviousTic,
        currentTic: frameTic,
      };
    } else {
      retainedPreparedMatchViews.temporalPayloads = [
        {tic: frameTic, payload: current},
      ];
    }
    retainedTemporalIdentity = {
      matchId, membershipEpoch, generation, playerMask};
    retainedTemporalPrevious = current;
    retainedTemporalPreviousTic = frameTic;
    retainedTemporalDeferredTics = [];
  }
`;
replaceOnce(oldPrepare, newPrepare, 'prepare');
replaceOnce(
  `  if (Array.isArray(prepared.temporalPayloads)) {
`,
  `  if (prepared.temporalEndpoints !== undefined) {
    persistNativeTemporalEndpoints(
      prepared.temporalEndpoints, matchId, playerMask,
      membershipEpoch, generation);
    retainedPreparedMatchViews = undefined;
    return outputOffset;
  }
  if (Array.isArray(prepared.temporalPayloads)) {
`,
  'publication');

const output = Buffer.from(source);
writeFileSync(outputPath, output);
process.stdout.write(
  'PMLE_NATIVE_TEMPORAL_COORDINATOR_PATCH|PASS'
    + `|input_sha256=${inputSha}`
    + `|output_bytes=${output.byteLength}`
    + `|output_sha256=${sha(output)}`
    + '|endpoints=EPT1|materialized=DPV2|interval=3\n');
