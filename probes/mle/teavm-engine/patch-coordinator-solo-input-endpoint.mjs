#!/usr/bin/env node

import {createHash} from 'node:crypto';
import {readFileSync,writeFileSync} from 'node:fs';

const [inputPath,outputPath]=process.argv.slice(2);
if(!inputPath||!outputPath) {
  throw new Error('usage: patch-coordinator-solo-input-endpoint.mjs INPUT OUTPUT');
}
const expectedInput=
  'afbe04722b3a5db03e3a73c834b5ff7600c8c7f4ca73d8296b9f04d6f6135c3e';
const sha=value=>createHash('sha256').update(value).digest('hex');
const source=readFileSync(inputPath,'utf8');
const inputSha=sha(source);
if(inputSha!==expectedInput) {
  throw new Error(`solo input endpoint input SHA mismatch: ${inputSha}`);
}
let output=source;
const replaceOnce=(before,after,label)=>{
  const first=output.indexOf(before);
  if(first<0||output.indexOf(before,first+before.length)>=0) {
    throw new Error(`solo input endpoint ${label} marker is not unique`);
  }
  output=output.slice(0,first)+after+output.slice(first+before.length);
};

replaceOnce(
`function prepareMatchViewsUnstaggered(
    matchId, playerMask, membershipEpoch, generation, frameTic) {`,
`function prepareMatchViewsUnstaggered(
    matchId, playerMask, membershipEpoch, generation, frameTic, inputMask) {`,
  'unstaggered signature');

replaceOnce(
`  if (temporalSame
      && retainedTemporalDeferredTics.length`,
`  if (temporalSame
      && inputMask === 0
      && retainedTemporalDeferredTics.length`,
  'defer fence');

replaceOnce(
`    if (temporalInterval === 3
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
    } else {`,
`    const endpointInterval=frameTic-retainedTemporalPreviousTic;
    if (temporalSame
        && retainedTemporalPrevious instanceof Uint8Array
        && endpointInterval >= 2 && endpointInterval <= temporalInterval
        && retainedTemporalDeferredTics.length === endpointInterval - 1) {
      retainedPreparedMatchViews.temporalEndpoints = {
        previous: retainedTemporalPrevious,
        current,
        previousTic: retainedTemporalPreviousTic,
        currentTic: frameTic,
      };
    } else {`,
  'variable exact endpoint');

replaceOnce(
`export function prepareMatchViews(
    matchId, playerMask, membershipEpoch, generation, frameTic) {
  if (playerMask === 3) {`,
`export function prepareMatchViews(
    matchId, playerMask, membershipEpoch, generation, frameTic,
    inputMask = 0) {
  if (!Number.isSafeInteger(inputMask) || inputMask < 0 || inputMask > 3
      || (inputMask & ~playerMask) !== 0) {
    throw new Error(\`invalid effective-input view mask: \${inputMask}\`);
  }
  if (playerMask === 3) {`,
  'public signature');

replaceOnce(
`  return prepareMatchViewsUnstaggered(
    matchId, playerMask, membershipEpoch, generation, frameTic);`,
`  return prepareMatchViewsUnstaggered(
    matchId, playerMask, membershipEpoch, generation, frameTic, inputMask);`,
  'unstaggered invocation');

writeFileSync(outputPath,output,{encoding:'utf8',mode:0o644,flag:'wx'});
console.log(`PMLE_SOLO_INPUT_ENDPOINT_PATCH|PASS|input_sha256=${inputSha}`
  +`|output_sha256=${sha(output)}|bytes=${Buffer.byteLength(output)}`
  +'|solo_endpoint_interval_min=1|solo_endpoint_interval_max=3'
  +'|multiplayer_scheduler=UNCHANGED');
