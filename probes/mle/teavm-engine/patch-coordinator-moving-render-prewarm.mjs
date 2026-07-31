#!/usr/bin/env node

import {createHash} from 'node:crypto';
import {readFileSync,writeFileSync} from 'node:fs';

const [inputPath,outputPath]=process.argv.slice(2);
if(!inputPath||!outputPath) {
  throw new Error(
    'usage: patch-coordinator-moving-render-prewarm.mjs INPUT OUTPUT');
}
const expectedInput=
  'e0efc05a1e4b6c3e722db057b7a085c2d526fb50a4273ea62b86f7529138590a';
const sha=value=>createHash('sha256').update(value).digest('hex');
const source=readFileSync(inputPath,'utf8');
const inputSha=sha(source);
if(inputSha!==expectedInput) {
  throw new Error(`moving-render prewarm input SHA mismatch: ${inputSha}`);
}
const before=`  for (let iteration = 0; iteration < iterations; iteration++) {
    // Prepay both exact viewpoint receiver shapes. The original warmup
    // compiled only player zero; the first live two-view match then paid
    // player one's compilation in its scored startup window.
    renderCompleteMatchFrame(0);
    renderCompleteMatchFrame(1);
  }
`;
const after=`  for (let iteration = 0; iteration < iterations; iteration++) {
    // Initialization has no moving world yet, so compile both full-frame
    // receivers exactly as before. A retained-slot route prewarm calls this
    // same entry point after each authoritative step; render the current
    // confirmed camera there so portal/weapon/sprite shapes are compiled
    // before READY rather than becoming a visible first-play pause.
    if (retainedTic > 0) {
      renderConfirmedTemporalFrame(0, retainedTic);
      renderConfirmedTemporalFrame(1, retainedTic);
    } else {
      renderCompleteMatchFrame(0);
      renderCompleteMatchFrame(1);
    }
  }
`;
const first=source.indexOf(before);
if(first<0||source.indexOf(before,first+before.length)>=0) {
  throw new Error('moving-render prewarm marker is not unique');
}
const output=source.slice(0,first)+after+source.slice(first+before.length);
writeFileSync(outputPath,output,{encoding:'utf8',mode:0o644,flag:'wx'});
console.log(
  `PMLE_MOVING_RENDER_PREWARM_PATCH|PASS|input_sha256=${inputSha}`
    +`|output_sha256=${sha(output)}|bytes=${Buffer.byteLength(output)}`);
