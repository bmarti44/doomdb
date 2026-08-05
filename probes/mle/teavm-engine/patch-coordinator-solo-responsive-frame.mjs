#!/usr/bin/env node

import {createHash} from 'node:crypto';
import {readFileSync,writeFileSync} from 'node:fs';

const [inputPath,outputPath]=process.argv.slice(2);
if(!inputPath||!outputPath) {
  throw new Error(
    'usage: patch-coordinator-solo-responsive-frame.mjs INPUT OUTPUT');
}

const expectedInput=
  '15f1664cb9f3e65a60f13a69aa3f4376c612484918b87998431ffacbac2db60a';
const sha=value=>createHash('sha256').update(value).digest('hex');
let source=readFileSync(inputPath,'utf8');
const inputSha=sha(source);
if(inputSha!==expectedInput) {
  throw new Error(`responsive-frame input SHA mismatch: ${inputSha}`);
}
const replaceOnce=(before,after,label)=>{
  const first=source.indexOf(before);
  if(first<0||source.indexOf(before,first+before.length)>=0) {
    throw new Error(`responsive-frame ${label} marker is not unique`);
  }
  source=source.slice(0,first)+after+source.slice(first+before.length);
};

replaceOnce(
`let retainedTemporalSynthesis;
let retainedStaggeredIdentity;`,
`let retainedTemporalSynthesis;
let retainedResponsiveFrame;
let retainedResponsiveThroughTic = -1;
let retainedStaggeredIdentity;`,
  'retained buffer');

replaceOnce(
`function cacheRenderedWorld(playerSlot, frameTic, snapshot) {
  const frame = rendererFrameView(renderer);`,
`function cacheRenderedWorld(
    playerSlot, frameTic, snapshot, suppliedFrame = undefined) {
  const frame = suppliedFrame ?? rendererFrameView(renderer);`,
  'cache source');

replaceOnce(
`function synthesizeConfirmedWorld(playerSlot, frameTic, snapshot) {`,
`function synthesizeConfirmedWorld(
    playerSlot, frameTic, snapshot, suppliedTarget = undefined) {`,
  'synthesis signature');

replaceOnce(
`  retainedTemporalPrevious = undefined;
}`,
`  retainedTemporalPrevious = undefined;
  retainedResponsiveThroughTic = -1;
}`,
  'generation reset');

replaceOnce(
`  const current = snapshotCamera(snapshot, frameTic);
  const target = rendererFrameView(renderer);`,
`  const current = snapshotCamera(snapshot, frameTic);
  const target = suppliedTarget ?? rendererFrameView(renderer);
  // A standalone responsive frame has no subsequent HUD compositor pass.
  // Start from the complete last exact Mocha frame, then replace only its
  // world viewport with the newly confirmed camera projection below.
  target.set(source);`,
  'standalone target');

replaceOnce(
`    retainedPaletteIndex =
      typeof renderer.presentationPaletteIndex === 'function'
        ? renderer.presentationPaletteIndex()
        : 0;
    return retainedFrame;`,
`    retainedPaletteIndex =
      typeof renderer.presentationPaletteIndex === 'function'
        ? renderer.presentationPaletteIndex()
        : 0;
    if (Number.isInteger(frameTic)
        && typeof authorityEngine.presentationWorldSnapshotNativeByRef
          === 'function') {
      const snapshotLength=
        authorityEngine.presentationWorldSnapshotLength(playerSlot);
      const snapshot=authorityEngine.presentationWorldSnapshotNativeByRef();
      if (!ArrayBuffer.isView(snapshot)
          || snapshot.byteLength<snapshotLength) {
        throw new Error('exact camera snapshot is not a typed array');
      }
      cacheRenderedWorld(playerSlot,frameTic,snapshot,retainedFrame);
    }
    return retainedFrame;`,
  'exact cache');

replaceOnce(
`  let outputOffset = MATCH_VIEW_HEADER_BYTES;
  let first = true;`,
`  let outputOffset = MATCH_VIEW_HEADER_BYTES;
  // A newly effective solo camera command must not wait for a second full
  // Mocha raster before the player sees it. Reproject the last exact Mocha
  // viewport from the newly confirmed authoritative camera inside MLE, keep
  // the exact HUD/weapon/status pixels, and publish this one responsive frame
  // immediately. The next scheduled interval keyframe falls through to the
  // proven exact raster and re-establishes the keyframe chain. The browser
  // still receives only database-authored pixels and performs no prediction
  // or rendering.
  if (inputMask === 1) {
    retainedResponsiveThroughTic=Math.max(
      retainedResponsiveThroughTic,frameTic+2);
  }
  const cachedCamera=retainedWorldCameras[0];
  const responsiveInput = exactPresentation && playerMask === 1
    && temporalSame && frameTic <= retainedResponsiveThroughTic
    && retainedWorldFrames[0] instanceof Uint8Array
    && cachedCamera !== undefined
    && frameTic > cachedCamera.tic
    && frameTic-cachedCamera.tic < temporalInterval
    && typeof authorityEngine.presentationWorldSnapshotNativeByRef
      === 'function';
  if (responsiveInput) {
    const snapshotLength=authorityEngine.presentationWorldSnapshotLength(0);
    const snapshot=authorityEngine.presentationWorldSnapshotNativeByRef();
    if (!ArrayBuffer.isView(snapshot)
        || snapshot.byteLength<snapshotLength) {
      throw new Error('responsive camera snapshot is not a typed array');
    }
    if (!(retainedResponsiveFrame instanceof Uint8Array)
        || retainedResponsiveFrame.byteLength !== FRAME_BYTES) {
      retainedResponsiveFrame=new Uint8Array(FRAME_BYTES);
    }
    synthesizeConfirmedWorld(
      0,frameTic,snapshot,retainedResponsiveFrame);
    retainedMatchViews[9]=retainedPaletteIndex;
    retainedMatchViews.set(retainedResponsiveFrame,outputOffset);
    outputOffset+=FRAME_BYTES;
    const responsivePayload=captureTemporalExact(outputOffset);
    const endpointInterval=frameTic-retainedTemporalPreviousTic;
    const publication=endpointInterval>=2
      &&endpointInterval<=temporalInterval
      &&retainedTemporalPrevious instanceof Uint8Array
      &&retainedTemporalDeferredTics.length===endpointInterval-1
      ?{temporalEndpoints:{
          previous:retainedTemporalPrevious,
          current:responsivePayload,
          previousTic:retainedTemporalPreviousTic,
          currentTic:frameTic,
        }}
      :{temporalPayloads:[{tic:frameTic,payload:responsivePayload}]};
    retainedPreparedMatchViews={
      matchId,playerMask,membershipEpoch,generation,frameTic,outputOffset,
      ...publication,responsiveInput:true,
    };
    return outputOffset;
  }
  let first = true;`,
  'responsive path');

writeFileSync(outputPath,source,{encoding:'utf8',mode:0o644,flag:'wx'});
console.log(`PMLE_SOLO_RESPONSIVE_FRAME_PATCH|PASS|input_sha256=${inputSha}`
  +`|output_sha256=${sha(source)}|bytes=${Buffer.byteLength(source)}`
  +'|authority=UNCHANGED|exact_keyframe=NEXT_SCHEDULED_INTERVAL'
  +'|client_renderer=NONE');
