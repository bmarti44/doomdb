#!/usr/bin/env node

import {createHash} from 'node:crypto';
import {readFileSync, writeFileSync} from 'node:fs';

const [inputPath, outputPath, intervalArgument = '4'] = process.argv.slice(2);
if (!inputPath || !outputPath) {
  throw new Error(
    'usage: patch-coordinator-staggered-multiview.mjs INPUT OUTPUT [4|5]');
}
const staggeredInterval = Number.parseInt(intervalArgument, 10);
if (![4,5].includes(staggeredInterval)
    || `${staggeredInterval}` !== intervalArgument) {
  throw new Error(`invalid staggered multiview interval: ${intervalArgument}`);
}
const playerOneReseedInterval = staggeredInterval - 2;
const expectedInput =
  '55d86b81e6e76ee4416622a59052526481ff2d14536b68f2535ca291b246d85b';
const sha = value => createHash('sha256').update(value).digest('hex');
let source = readFileSync(inputPath, 'utf8');
const inputSha = sha(source);
if (inputSha !== expectedInput) {
  throw new Error(
    `staggered multiview input SHA mismatch: ${inputSha} != ${expectedInput}`);
}
const replaceOnce = (before, after, label) => {
  const first = source.indexOf(before);
  if (first < 0 || source.indexOf(before, first + before.length) >= 0) {
    throw new Error(`staggered multiview ${label} marker is not unique`);
  }
  source = source.slice(0, first) + after
    + source.slice(first + before.length);
};

replaceOnce(
  'let retainedTemporalSynthesis;\n',
  `let retainedTemporalSynthesis;
let retainedStaggeredIdentity;
let retainedStaggeredStreams = [undefined, undefined];
const STAGGERED_MULTIVIEW_INTERVAL = ${staggeredInterval};
`,
  'state declarations');
replaceOnce(
  `    renderCompleteMatchFrame(0);
`,
  `    // Prepay both exact viewpoint receiver shapes. The original warmup
    // compiled only player zero; the first live two-view match then paid
    // player one's compilation in its scored startup window.
    renderCompleteMatchFrame(0);
    renderCompleteMatchFrame(1);
`,
  'two-view renderer prewarm');
replaceOnce(
  `  const frameBytes = players * FRAME_BYTES;
  const sourceBytes = MATCH_VIEW_HEADER_BYTES + frameBytes;
`,
  `  const frameBytes = players * FRAME_BYTES;
  const sourceBytes = MATCH_VIEW_HEADER_BYTES + frameBytes;
  const interval = currentTic - previousTic;
`,
  'native interval declaration');
replaceOnce(
  `      || currentTic !== previousTic + 3
`,
  `      || interval < 2 || interval > ${staggeredInterval}
`,
  'native interval validation');
replaceOnce(
  `  bytes[13] = 3;
`,
  `  bytes[13] = interval;
`,
  'native interval header');
replaceOnce(
  `  return 16 + 3 * (8 + frameBytes);
`,
  `  return 16 + interval * (8 + frameBytes);
`,
  'native interval result');

const helpers = `
function resetStaggeredMultiview() {
  retainedStaggeredIdentity = undefined;
  retainedStaggeredStreams = [undefined, undefined];
}

function compactStaggeredView(combined, playerSlot, frameTic) {
  const mask = 1 << playerSlot;
  const compact = new Uint8Array(MATCH_VIEW_HEADER_BYTES + FRAME_BYTES);
  compact.set([68, 80, 68, 49], 0); // DPD1.
  putU32Be(compact, 4, frameTic >>> 0);
  compact[8] = mask;
  compact[9] = playerSlot === 0 ? combined[9] : 255;
  compact[10] = playerSlot === 1 ? combined[10] : 255;
  compact[11] = combined[11];
  compact.set(combined.subarray(
    MATCH_VIEW_HEADER_BYTES + playerSlot * FRAME_BYTES,
    MATCH_VIEW_HEADER_BYTES + (playerSlot + 1) * FRAME_BYTES),
  MATCH_VIEW_HEADER_BYTES);
  return compact;
}

function renderStaggeredView(playerSlot, frameTic) {
  const mask = 1 << playerSlot;
  renderCompleteMatchFrame(playerSlot, false, frameTic);
  const compact = new Uint8Array(MATCH_VIEW_HEADER_BYTES + FRAME_BYTES);
  compact.set([68, 80, 68, 49], 0); // DPD1.
  putU32Be(compact, 4, frameTic >>> 0);
  compact[8] = mask;
  compact[9] = playerSlot === 0 ? retainedPaletteIndex : 255;
  compact[10] = playerSlot === 1 ? retainedPaletteIndex : 255;
  compact[11] = exactPresentation ? 1 : 0;
  compact.set(retainedFrame, MATCH_VIEW_HEADER_BYTES);
  return compact;
}

/**
 * Two exact viewpoints formerly rasterized in one interval-three burst.
 * Keep their complete confirmed frame streams but phase the expensive
 * endpoints: a generation seed contains both views, player one gets a shorter
 * reseed, then each player advances on the selected staggered interval.
 * Native EPT1 materialization fills every intervening tic.
 */
function prepareStaggeredMatchViews(
    matchId, membershipEpoch, generation, frameTic) {
  if (!exactPresentation) {
    throw new Error('staggered multiview requires exact presentation');
  }
  const changed = retainedStaggeredIdentity === undefined
    || retainedStaggeredIdentity.matchId !== matchId
    || retainedStaggeredIdentity.membershipEpoch !== membershipEpoch
    || retainedStaggeredIdentity.generation !== generation;
  if (changed) {
    resetStaggeredMultiview();
    clearRetainedWorldFrames();
    retainedMatchViewIdentity = {matchId, membershipEpoch, generation};
    retainedMatchViews =
      new Uint8Array(MATCH_VIEW_HEADER_BYTES + 2 * FRAME_BYTES);
    retainedMatchViews.set([68, 80, 68, 49], 0); // DPD1.
    putU32Be(retainedMatchViews, 4, frameTic >>> 0);
    retainedMatchViews[8] = 3;
    retainedMatchViews[9] = 255;
    retainedMatchViews[10] = 255;
    retainedMatchViews[11] = 1;
    for (let playerSlot = 0; playerSlot < 2; playerSlot++) {
      renderCompleteMatchFrame(playerSlot, playerSlot === 0, frameTic);
      retainedMatchViews[9 + playerSlot] = retainedPaletteIndex;
      retainedMatchViews.set(
        retainedFrame,
        MATCH_VIEW_HEADER_BYTES + playerSlot * FRAME_BYTES);
    }
    const seed = new Uint8Array(retainedMatchViews);
    retainedStaggeredStreams[0] = {
      previous: compactStaggeredView(seed, 0, frameTic),
      previousTic: frameTic,
      nextInterval: STAGGERED_MULTIVIEW_INTERVAL,
    };
    retainedStaggeredStreams[1] = {
      previous: compactStaggeredView(seed, 1, frameTic),
      previousTic: frameTic,
      nextInterval: ${playerOneReseedInterval},
    };
    retainedStaggeredIdentity = {
      matchId, membershipEpoch, generation,
    };
    retainedPreparedMatchViews = {
      matchId,
      playerMask: 3,
      membershipEpoch,
      generation,
      frameTic,
      outputOffset: MATCH_VIEW_HEADER_BYTES + 2 * FRAME_BYTES,
      staggeredPayload: seed,
      staggeredMask: 3,
    };
    return retainedPreparedMatchViews.outputOffset;
  }
  const due = [];
  for (let playerSlot = 0; playerSlot < 2; playerSlot++) {
    const state = retainedStaggeredStreams[playerSlot];
    if (state === undefined
        || frameTic <= state.previousTic
        || frameTic > state.previousTic + state.nextInterval) {
      throw new Error(
        \`staggered multiview continuity: \${playerSlot}/\${frameTic}\`
          + \`/\${state?.previousTic}/\${state?.nextInterval}\`);
    }
    if (frameTic === state.previousTic + state.nextInterval) {
      const current = renderStaggeredView(playerSlot, frameTic);
      due.push({
        previous: state.previous,
        current,
        previousTic: state.previousTic,
        currentTic: frameTic,
        playerMask: 1 << playerSlot,
      });
      state.previous = current;
      state.previousTic = frameTic;
      state.nextInterval = STAGGERED_MULTIVIEW_INTERVAL;
    }
  }
  if (due.length > 1) {
    throw new Error('staggered multiview endpoint phases collided');
  }
  retainedPreparedMatchViews = {
    matchId,
    playerMask: 3,
    membershipEpoch,
    generation,
    frameTic,
    outputOffset: MATCH_VIEW_HEADER_BYTES + 2 * FRAME_BYTES,
    staggeredEndpoints: due[0],
  };
  return retainedPreparedMatchViews.outputOffset;
}

`;
replaceOnce(
  'export function prepareMatchViews(\n',
  helpers + 'function prepareMatchViewsUnstaggered(\n',
  'prepare rename and helper insertion');

replaceOnce(
  'export function publishPreparedMatchViews(\n',
  `export function prepareMatchViews(
    matchId, playerMask, membershipEpoch, generation, frameTic) {
  if (playerMask === 3) {
    if (typeof matchId !== 'string' || !/^[0-9a-f]{32}$/.test(matchId)
        || !Number.isSafeInteger(membershipEpoch) || membershipEpoch < 1
        || !Number.isSafeInteger(generation) || generation < 1
        || !Number.isSafeInteger(frameTic) || frameTic < 1
        || frameTic > 0xffffffff) {
      throw new Error(
        \`invalid staggered match views: \${matchId}/\${membershipEpoch}\`
          + \`/\${generation}/\${frameTic}\`);
    }
    return prepareStaggeredMatchViews(
      matchId, membershipEpoch, generation, frameTic);
  }
  return prepareMatchViewsUnstaggered(
    matchId, playerMask, membershipEpoch, generation, frameTic);
}

function publishPreparedMatchViewsUnstaggered(
`,
  'publish rename and prepare wrapper');

replaceOnce(
  'export function renderAndPublishMatchViews(\n',
  `export function publishPreparedMatchViews(
    matchId, playerMask, membershipEpoch, generation, frameTic) {
  const prepared = retainedPreparedMatchViews;
  if (playerMask === 3 && prepared?.playerMask === 3
      && prepared.matchId === matchId
      && prepared.membershipEpoch === membershipEpoch
      && prepared.generation === generation
      && prepared.frameTic === frameTic
      && prepared.outputOffset
        === MATCH_VIEW_HEADER_BYTES + 2 * FRAME_BYTES) {
    if (prepared.staggeredPayload instanceof Uint8Array) {
      persistTemporalMatchView(
        prepared.staggeredPayload, matchId, prepared.staggeredMask,
        membershipEpoch, generation, frameTic);
    } else if (prepared.staggeredEndpoints !== undefined) {
      persistNativeTemporalEndpoints(
        prepared.staggeredEndpoints, matchId,
        prepared.staggeredEndpoints.playerMask,
        membershipEpoch, generation);
    }
    retainedPreparedMatchViews = undefined;
    return MATCH_VIEW_HEADER_BYTES + 2 * FRAME_BYTES;
  }
  return publishPreparedMatchViewsUnstaggered(
    matchId, playerMask, membershipEpoch, generation, frameTic);
}

export function renderAndPublishMatchViews(
`,
  'publish wrapper');

replaceOnce(
  '  resetTemporalSoloState();\n',
  '  resetTemporalSoloState();\n  resetStaggeredMultiview();\n',
  'release reset');

// Preserve substantially more confirmed pixels across public ORDS/resource
// manager tails. Every read and write site must share the same modulo; fail
// closed if the generated input shape changes.
const moduloSites = [...source.matchAll(/mod\((:[A-Za-z]+),64\)/g)];
const sequenceSites = [...source.matchAll(/state\.sequence % 64/g)];
if (moduloSites.length !== 7 || sequenceSites.length !== 1) {
  throw new Error(
    `live-frame ring markers changed: modulo=${moduloSites.length}`
      + ` sequence=${sequenceSites.length}`);
}
source = source.replace(/mod\((:[A-Za-z]+),64\)/g, 'mod($1,128)');
source = source.replace(/state\.sequence % 64/g, 'state.sequence % 128');

const output = Buffer.from(source);
writeFileSync(outputPath, output);
process.stdout.write(
  'PMLE_STAGGERED_MULTIVIEW_PATCH|PASS'
    + `|input_sha256=${inputSha}`
    + `|output_bytes=${output.byteLength}`
    + `|output_sha256=${sha(output)}`
    + `|endpoint_interval=${staggeredInterval}`
    + `|initial_player_one_interval=${playerOneReseedInterval}`
    + '|live_frame_ring_entries=128'
    + '|player_masks=1,2,3\n');
