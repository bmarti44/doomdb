import {readFileSync, writeFileSync} from 'node:fs';
import {createHash} from 'node:crypto';

const [inputPath, outputPath, intervalText = '2'] = process.argv.slice(2);
if (!inputPath || !outputPath) {
  throw new Error(
    'usage: patch-coordinator-temporal-solo.mjs INPUT OUTPUT [INTERVAL]');
}
const keyframeInterval = Number.parseInt(intervalText, 10);
if (![2, 3].includes(keyframeInterval)) {
  throw new Error('temporal solo keyframe interval must be 2 or 3');
}
const expectedInput =
  'a987e6ac95b4f06886b0a73f5f4925cc2f60872221f9a8ca048350fa25317aa0';
const sha = value => createHash('sha256').update(value).digest('hex');
const input = readFileSync(inputPath);
const inputSha = sha(input);
if (inputSha !== expectedInput) {
  throw new Error(
    `coordinator input SHA mismatch: ${inputSha} != ${expectedInput}`);
}
let source = input.toString('utf8');
const replaceOnce = (before, after, label) => {
  const first = source.indexOf(before);
  if (first < 0 || source.indexOf(before, first + before.length) >= 0) {
    throw new Error(`temporal coordinator ${label} marker is not unique`);
  }
  source = source.slice(0, first) + after
    + source.slice(first + before.length);
};

replaceOnce(
  'let retainedPreparedMatchViews;\n',
  `let retainedPreparedMatchViews;
let retainedTemporalIdentity;
let retainedTemporalPreviousTic = -1;
let retainedTemporalDeferredTics = [];
let retainedTemporalPrevious;
let retainedTemporalExactBuffers = [undefined, undefined];
let retainedTemporalExactBufferIndex = 0;
let retainedTemporalSynthesis;
const TEMPORAL_SOLO_KEYFRAME_INTERVAL = ${keyframeInterval};
`,
  'globals');

const helpers = `
function resetTemporalSoloState() {
  retainedTemporalIdentity = undefined;
  retainedTemporalPreviousTic = -1;
  retainedTemporalDeferredTics = [];
  retainedTemporalPrevious = undefined;
}

function temporalSoloIdentityMatches(
    matchId, membershipEpoch, generation, playerMask) {
  return playerMask === 1 && retainedTemporalIdentity !== undefined
    && retainedTemporalIdentity.matchId === matchId
    && retainedTemporalIdentity.membershipEpoch === membershipEpoch
    && retainedTemporalIdentity.generation === generation;
}

function captureTemporalExact(payloadBytes) {
  retainedTemporalExactBufferIndex ^= 1;
  let target = retainedTemporalExactBuffers[retainedTemporalExactBufferIndex];
  if (!(target instanceof Uint8Array) || target.byteLength !== payloadBytes) {
    target = new Uint8Array(payloadBytes);
    retainedTemporalExactBuffers[retainedTemporalExactBufferIndex] = target;
  }
  target.set(retainedMatchViews.subarray(0, payloadBytes));
  return target;
}

function synthesizeTemporalSoloFrame(
    previous, current, frameTic, payloadBytes, numerator, denominator) {
  if (!(retainedTemporalSynthesis instanceof Uint8Array)
      || retainedTemporalSynthesis.byteLength !== payloadBytes) {
    retainedTemporalSynthesis = new Uint8Array(payloadBytes);
  }
  const output = retainedTemporalSynthesis;
  output.set(current.subarray(0, MATCH_VIEW_HEADER_BYTES), 0);
  putU32Be(output, 4, frameTic >>> 0);
  const samePalette = previous[9] === current[9];
  const sameLayout = previous[11] === current[11];
  if (!samePalette || !sameLayout) {
    // Palette flashes are rare and fidelity wins over an invalid cross-palette
    // dither. Reuse the newer confirmed pixels for this one intermediate tic.
    output.set(current.subarray(MATCH_VIEW_HEADER_BYTES),
      MATCH_VIEW_HEADER_BYTES);
    return output;
  }
  const words = FRAME_BYTES >>> 2;
  const previous32 = new Uint32Array(
    previous.buffer, previous.byteOffset + MATCH_VIEW_HEADER_BYTES, words);
  const current32 = new Uint32Array(
    current.buffer, current.byteOffset + MATCH_VIEW_HEADER_BYTES, words);
  const output32 = new Uint32Array(
    output.buffer, output.byteOffset + MATCH_VIEW_HEADER_BYTES, words);
  if (denominator === 2) {
    for (let row = 0; row < FRAME_HEIGHT; row++) {
      const mask = ((row + frameTic) & 1) === 0
        ? 0x00ff00ff : 0xff00ff00;
      const inverse = ~mask;
      const start = row * (FRAME_WIDTH >>> 2);
      const end = start + (FRAME_WIDTH >>> 2);
      for (let index = start; index < end; index++) {
        output32[index] =
          (previous32[index] & mask) | (current32[index] & inverse);
      }
    }
  } else if (denominator === 3 && (numerator === 1 || numerator === 2)) {
    const masks = new Int32Array(3);
    for (let startMod = 0; startMod < 3; startMod++) {
      let mask = 0;
      for (let byte = 0; byte < 4; byte++) {
        if (((startMod + byte + frameTic) % 3) < numerator) {
          mask |= 255 << (byte * 8);
        }
      }
      masks[startMod] = mask;
    }
    for (let row = 0; row < FRAME_HEIGHT; row++) {
      let index = row * (FRAME_WIDTH >>> 2);
      const end = index + (FRAME_WIDTH >>> 2);
      let phase = (row * FRAME_WIDTH) % 3;
      while (index + 2 < end) {
        let mask = masks[phase];
        output32[index] =
          (previous32[index] & ~mask) | (current32[index] & mask);
        mask = masks[(phase + 1) % 3];
        output32[index + 1] =
          (previous32[index + 1] & ~mask)
            | (current32[index + 1] & mask);
        mask = masks[(phase + 2) % 3];
        output32[index + 2] =
          (previous32[index + 2] & ~mask)
            | (current32[index + 2] & mask);
        index += 3;
      }
      while (index < end) {
        const mask = masks[phase];
        output32[index] =
          (previous32[index] & ~mask) | (current32[index] & mask);
        phase = (phase + 1) % 3;
        index++;
      }
    }
  } else {
    throw new Error(
      \`invalid temporal phase: \${numerator}/\${denominator}\`);
  }
  return output;
}

function persistTemporalMatchView(
    payloadBytes, matchId, membershipEpoch, generation, frameTic) {
  const result = oracledb.defaultConnection().execute(
    \`update doom_match_live_frame_views
        set tic=:frameTic,player_mask=1,
            payload_bytes=:payloadBytes,payload_blob=empty_blob(),
            published_at=systimestamp
      where match_id=:matchId
        and ring_slot=mod(:frameTic,64)
        and membership_epoch=:membershipEpoch
        and generation=:generation
      returning payload_blob into :payload\`,
    {
      frameTic,
      payloadBytes: payloadBytes.byteLength,
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
    throw new Error('temporal match-view locator acquisition failed');
  }
  const payload = result.outBinds.payload[0];
  let opened = false;
  try {
    payload.open(OracleBlob.LOB_READWRITE);
    opened = true;
    payload.write(1, payloadBytes);
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
  return payloadBytes.byteLength;
}

`;
replaceOnce(
  '/**\n * Immediate shared-view path.',
  helpers + '/**\n * Immediate shared-view path.',
  'helper insertion');

replaceOnce(
  '  const changed = retainedMatchViewIdentity === undefined\n',
  `  const temporalSame = temporalSoloIdentityMatches(
    matchId, membershipEpoch, generation, playerMask);
  if (temporalSame
      && retainedTemporalDeferredTics.length
        < TEMPORAL_SOLO_KEYFRAME_INTERVAL - 1
      && frameTic === retainedTemporalPreviousTic
        + retainedTemporalDeferredTics.length + 1) {
    retainedTemporalDeferredTics.push(frameTic);
    retainedPreparedMatchViews = {
      matchId,
      playerMask,
      membershipEpoch,
      generation,
      frameTic,
      outputOffset: MATCH_VIEW_HEADER_BYTES + FRAME_BYTES,
      temporalDeferred: true,
    };
    return MATCH_VIEW_HEADER_BYTES + FRAME_BYTES;
  }
  if (playerMask !== 1 || !temporalSame) resetTemporalSoloState();
  const changed = retainedMatchViewIdentity === undefined
`,
  'defer branch');

replaceOnce(
  `  retainedPreparedMatchViews = {
    matchId,
    playerMask,
    membershipEpoch,
    generation,
    frameTic,
    outputOffset,
  };
  return outputOffset;
}`,
  `  retainedPreparedMatchViews = {
    matchId,
    playerMask,
    membershipEpoch,
    generation,
    frameTic,
    outputOffset,
  };
  if (playerMask === 1) {
    const current = captureTemporalExact(outputOffset);
    const payloads = [];
    if (temporalSame && retainedTemporalPrevious instanceof Uint8Array
        && retainedTemporalDeferredTics.length
          === TEMPORAL_SOLO_KEYFRAME_INTERVAL - 1
        && retainedTemporalPreviousTic
          === frameTic - TEMPORAL_SOLO_KEYFRAME_INTERVAL) {
      for (let phase = 0;
          phase < retainedTemporalDeferredTics.length; phase++) {
        const deferredTic = retainedTemporalDeferredTics[phase];
        // Copy because the retained synthesis buffer is reused for the next
        // phase before publication begins.
        const synthesized = new Uint8Array(outputOffset);
        synthesized.set(synthesizeTemporalSoloFrame(
          retainedTemporalPrevious, current, deferredTic, outputOffset,
          phase + 1, TEMPORAL_SOLO_KEYFRAME_INTERVAL));
        payloads.push({tic: deferredTic, payload: synthesized});
      }
    }
    payloads.push({tic: frameTic, payload: current});
    retainedTemporalIdentity = {matchId, membershipEpoch, generation};
    retainedTemporalPrevious = current;
    retainedTemporalPreviousTic = frameTic;
    retainedTemporalDeferredTics = [];
    retainedPreparedMatchViews.temporalPayloads = payloads;
  }
  return outputOffset;
}`,
  'prepared payloads');

replaceOnce(
  '  const outputOffset = prepared.outputOffset;\n',
  `  const outputOffset = prepared.outputOffset;
  if (prepared.temporalDeferred === true) {
    retainedPreparedMatchViews = undefined;
    return outputOffset;
  }
  if (Array.isArray(prepared.temporalPayloads)) {
    for (const entry of prepared.temporalPayloads) {
      persistTemporalMatchView(
        entry.payload, matchId, membershipEpoch, generation, entry.tic);
    }
    retainedPreparedMatchViews = undefined;
    return outputOffset;
  }
`,
  'publication branch');

replaceOnce(
  '  retainedPreparedMatchViews = undefined;\n  discardedAssets.clear();',
  `  retainedPreparedMatchViews = undefined;
  resetTemporalSoloState();
  retainedTemporalExactBuffers = [undefined, undefined];
  retainedTemporalSynthesis = undefined;
  discardedAssets.clear();`,
  'release reset');

const output = Buffer.from(source);
writeFileSync(outputPath, output);
console.log(
  'PMLE_TEMPORAL_COORDINATOR_PATCH|PASS'
  + `|input_sha256=${inputSha}`
  + `|output_bytes=${output.byteLength}`
  + `|output_sha256=${sha(output)}`
  + `|solo_keyframe_interval=${keyframeInterval}`
  + '|synthesis=PIXEL_PHASE_DITHER_U32');
