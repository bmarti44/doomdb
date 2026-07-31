#!/usr/bin/env node

import {createHash} from 'node:crypto';
import {readFileSync,writeFileSync} from 'node:fs';

const [inputPath,outputPath]=process.argv.slice(2);
if(!inputPath||!outputPath) {
  throw new Error(
    'usage: patch-coordinator-solo-interval4.mjs INPUT OUTPUT');
}
const expectedInput=
  '15f1664cb9f3e65a60f13a69aa3f4376c612484918b87998431ffacbac2db60a';
const sha=value=>createHash('sha256').update(value).digest('hex');
const source=readFileSync(inputPath,'utf8');
const inputSha=sha(source);
if(inputSha!==expectedInput) {
  throw new Error(`solo interval-four input SHA mismatch: ${inputSha}`);
}
const marker='const TEMPORAL_SOLO_KEYFRAME_INTERVAL = 3;';
if(source.split(marker).length!==2) {
  throw new Error('solo interval-four marker is not unique');
}
const output=source.replace(
  marker,'const TEMPORAL_SOLO_KEYFRAME_INTERVAL = 4;');
writeFileSync(outputPath,output,{encoding:'utf8',mode:0o644,flag:'wx'});
console.log(`PMLE_SOLO_INTERVAL4_PATCH|PASS|input_sha256=${inputSha}`
  +`|output_sha256=${sha(output)}|bytes=${Buffer.byteLength(output)}`
  +'|solo_keyframe_interval=4|effective_camera_endpoint=EXACT'
  +'|multiplayer_scheduler=UNCHANGED');
