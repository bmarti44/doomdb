import {readFileSync, writeFileSync} from 'node:fs';
import {createHash} from 'node:crypto';

const [inputPath, outputPath, intervalText = '2',
  multiplayerIntervalText = '2'] = process.argv.slice(2);
if (!inputPath || !outputPath) {
  throw new Error(
    'usage: patch-coordinator-temporal-solo.mjs INPUT OUTPUT ' +
    '[SOLO_INTERVAL] [MULTIPLAYER_INTERVAL]');
}
const keyframeInterval = Number.parseInt(intervalText, 10);
const multiplayerKeyframeInterval =
  Number.parseInt(multiplayerIntervalText, 10);
if (![2, 3, 4].includes(keyframeInterval)
    || ![2, 3, 4].includes(multiplayerKeyframeInterval)) {
  throw new Error('temporal keyframe intervals must be 2, 3, or 4');
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
const TEMPORAL_MULTIPLAYER_KEYFRAME_INTERVAL = ${multiplayerKeyframeInterval};
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
  return retainedTemporalIdentity !== undefined
    && retainedTemporalIdentity.matchId === matchId
    && retainedTemporalIdentity.membershipEpoch === membershipEpoch
    && retainedTemporalIdentity.generation === generation
    && retainedTemporalIdentity.playerMask === playerMask;
}

function temporalKeyframeInterval(playerMask) {
  return playerMask === 1
    ? TEMPORAL_SOLO_KEYFRAME_INTERVAL
    : TEMPORAL_MULTIPLAYER_KEYFRAME_INTERVAL;
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
  const playerMask = current[8];
  const samePalette = previous[9] === current[9]
    && (playerMask !== 3 || previous[10] === current[10]);
  const sameLayout = previous[11] === current[11];
  if (!samePalette || !sameLayout) {
    // Palette flashes are rare and fidelity wins over an invalid cross-palette
    // dither. Reuse the newer confirmed pixels for this one intermediate tic.
    output.set(current.subarray(MATCH_VIEW_HEADER_BYTES),
      MATCH_VIEW_HEADER_BYTES);
    return output;
  }
  const words = (payloadBytes - MATCH_VIEW_HEADER_BYTES) >>> 2;
  const totalRows = FRAME_HEIGHT * (playerMask === 3 ? 2 : 1);
  const previous32 = new Uint32Array(
    previous.buffer, previous.byteOffset + MATCH_VIEW_HEADER_BYTES, words);
  const current32 = new Uint32Array(
    current.buffer, current.byteOffset + MATCH_VIEW_HEADER_BYTES, words);
  const output32 = new Uint32Array(
    output.buffer, output.byteOffset + MATCH_VIEW_HEADER_BYTES, words);
  if (denominator === 2) {
    for (let row = 0; row < totalRows; row++) {
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
  } else if ((denominator === 3 || denominator === 4)
      && numerator >= 1 && numerator < denominator) {
    const masks = new Int32Array(denominator);
    for (let startMod = 0; startMod < denominator; startMod++) {
      let mask = 0;
      for (let byte = 0; byte < 4; byte++) {
        if (((startMod + byte + frameTic) % denominator) < numerator) {
          mask |= 255 << (byte * 8);
        }
      }
      masks[startMod] = mask;
    }
    for (let row = 0; row < totalRows; row++) {
      let index = row * (FRAME_WIDTH >>> 2);
      const end = index + (FRAME_WIDTH >>> 2);
      let phase = (row * FRAME_WIDTH) % denominator;
      while (index + denominator - 1 < end) {
        let mask = masks[phase];
        output32[index] =
          (previous32[index] & ~mask) | (current32[index] & mask);
        for (let word = 1; word < denominator; word++) {
          mask = masks[(phase + word * 4) % denominator];
          output32[index + word] =
            (previous32[index + word] & ~mask)
              | (current32[index + word] & mask);
        }
        index += denominator;
      }
      while (index < end) {
        const mask = masks[phase];
        output32[index] =
          (previous32[index] & ~mask) | (current32[index] & mask);
        phase = (phase + 1) % denominator;
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
    payloadBytes, matchId, playerMask,
    membershipEpoch, generation, frameTic) {
  const result = oracledb.defaultConnection().execute(
    \`update doom_match_live_frame_views
        set tic=:frameTic,player_mask=:playerMask,
            payload_bytes=:payloadBytes,payload_blob=empty_blob(),
            published_at=systimestamp
      where match_id=:matchId
        and ring_slot=mod(:frameTic,64)
        and membership_epoch=:membershipEpoch
        and generation=:generation
      returning payload_blob into :payload\`,
    {
      frameTic,
      playerMask,
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
  const temporalInterval = temporalKeyframeInterval(playerMask);
  if (temporalSame
      && retainedTemporalDeferredTics.length
        < temporalInterval - 1
      && frameTic === retainedTemporalPreviousTic
        + retainedTemporalDeferredTics.length + 1) {
    retainedTemporalDeferredTics.push(frameTic);
    retainedPreparedMatchViews = {
      matchId,
      playerMask,
      membershipEpoch,
      generation,
      frameTic,
      outputOffset: MATCH_VIEW_HEADER_BYTES
        + (playerMask === 3 ? 2 : 1) * FRAME_BYTES,
      temporalDeferred: true,
    };
    return retainedPreparedMatchViews.outputOffset;
  }
  if (!temporalSame) resetTemporalSoloState();
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
  if (playerMask === 1 || playerMask === 3) {
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
        entry.payload, matchId, playerMask,
        membershipEpoch, generation, entry.tic);
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
  + `|multiplayer_keyframe_interval=${multiplayerKeyframeInterval}`
  + '|synthesis=PIXEL_PHASE_DITHER_U32');
