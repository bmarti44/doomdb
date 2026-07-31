#!/usr/bin/env node

import assert from 'node:assert/strict';
import {readFileSync, writeFileSync, mkdtempSync, rmSync} from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import {pathToFileURL} from 'node:url';

const root = path.resolve(import.meta.dirname, '..');
const coordinatorPath = path.resolve(
  process.argv[2] ?? path.join(
    root, 'artifacts/performance/pmle-exact-live/'
      + 'coordinator-temporal-solo-candidate.mjs'));
const keyframeInterval = Number.parseInt(process.argv[3] ?? '2', 10);
const multiplayerKeyframeInterval =
  Number.parseInt(process.argv[4] ?? '2', 10);
const persistenceMode=process.argv[5]??'DPD1';
const schedulerMode=process.argv[6]??'BASELINE';
const bundleMode=persistenceMode==='BATCH';
const staggeredMode=persistenceMode==='STAGGERED';
const nativeTemporalMode=persistenceMode==='NATIVE'||staggeredMode;
const viewBundleMode=
  persistenceMode==='VIEW_BUNDLE'||nativeTemporalMode;
if (!['DPD1','BATCH','VIEW_BUNDLE','NATIVE','STAGGERED']
    .includes(persistenceMode)) {
  throw new Error(`invalid temporal persistence mode: ${persistenceMode}`);
}
if(!['BASELINE','INPUT_AWARE','SOLO_INPUT_AWARE'].includes(schedulerMode)) {
  throw new Error(`invalid temporal scheduler mode: ${schedulerMode}`);
}
const inputAwareMode=schedulerMode==='INPUT_AWARE';
const soloInputAwareMode=schedulerMode==='SOLO_INPUT_AWARE';
if(inputAwareMode&&!staggeredMode) {
  throw new Error('input-aware scheduling requires staggered persistence');
}
if(soloInputAwareMode&&(!staggeredMode||keyframeInterval!==3)) {
  throw new Error('solo input-aware scheduling requires staggered/interval 3');
}
if (![2,3,4,5].includes(keyframeInterval)
    || ![2,3,4,5].includes(multiplayerKeyframeInterval)) {
  throw new Error('temporal coordinator test intervals must be 2 through 5');
}
const rendererPath = path.join(
  root, 'artifacts/performance/pmle-exact-live/'
    + 'renderer-bsp-precomputed-geometry-production.js');
const iwadPath = path.join(
  root, 'client/dist/play/freedoom1-7323bcc168c5.bin');
const tablePath = path.join(
  root, 'client/dist/play/canonical-runtime-v2-058cd0df9444.bin');
const temporary = mkdtempSync(path.join(os.tmpdir(), 'doomdb-temporal-solo-'));

globalThis.__doomdbTemporalWrites = [];
globalThis.__doomdbMaterializeTemporal = () => {
  const entry=globalThis.__doomdbTemporalWrites.at(-1);
  assert.ok(entry!==undefined,'EPT1 materialization has no endpoint write');
  const source=entry.payload.bytes;
  assert.deepEqual([...source.subarray(0,4)],[69,80,84,49]);
  const sourceView=new DataView(
    source.buffer,source.byteOffset,source.byteLength);
  const previousTic=sourceView.getUint32(4);
  const currentTic=sourceView.getUint32(8);
  const playerMask=source[12];
  const interval=source[13];
  assert.ok(interval>=2&&interval<=5);
  assert.equal(currentTic,previousTic+interval);
  assert.deepEqual([...source.subarray(14,16)],[0,0]);
  const players=playerMask===3?2:1;
  const frameBytes=players*64_000;
  assert.equal(source.byteLength,24+2*frameBytes);
  const previousMeta=source.subarray(16,20);
  const previous=source.subarray(20,20+frameBytes);
  const currentRecord=20+frameBytes;
  const currentMeta=source.subarray(currentRecord,currentRecord+4);
  const current=source.subarray(currentRecord+4);
  const recordBytes=8+frameBytes;
  const output=new Uint8Array(16+interval*recordBytes);
  output.set([68,80,86,50],0);
  const outputView=new DataView(output.buffer);
  outputView.setUint32(4,previousTic+1);
  outputView.setUint32(8,interval);
  output[12]=playerMask;
  const sameMetadata=previousMeta.every(
    (value,index)=>value===currentMeta[index]);
  for(let numerator=1;numerator<interval;numerator++) {
    const tic=previousTic+numerator;
    const record=16+(numerator-1)*recordBytes;
    outputView.setUint32(record,tic);
    output.set(numerator===1?previousMeta:currentMeta,record+4);
    if(!sameMetadata) {
      output.set(current,record+8);
    } else {
      for(let pixel=0;pixel<frameBytes;pixel++) {
        output[record+8+pixel]=(pixel+tic)%interval<numerator
          ?current[pixel]:previous[pixel];
      }
    }
  }
  const lastRecord=16+(interval-1)*recordBytes;
  outputView.setUint32(lastRecord,currentTic);
  output.set(currentMeta,lastRecord+4);
  output.set(current,lastRecord+8);
  entry.payload.bytes=output;
};
globalThis.OracleBlob = class OracleBlob {
  static LOB_READWRITE = 2;
  open() {}
  write(position, bytes) {
    assert.equal(position, 1);
    this.bytes = Uint8Array.from(bytes);
  }
  close() {}
};

function load(allocate, write, bytes, label) {
  assert.equal(allocate(bytes.byteLength), bytes.byteLength, `${label} allocate`);
  for (let offset = 0; offset < bytes.byteLength; offset += 16_000) {
    const chunk = bytes.subarray(offset, offset + 16_000);
    assert.equal(write(offset, chunk), offset + chunk.byteLength, `${label} load`);
  }
}

function playerCamera(api) {
  const length = api.presentationWorldSnapshotLength(0);
  assert.ok(Number.isInteger(length) && length >= 56,
    `invalid player world snapshot length ${length}`);
  const bytes = api.presentationWorldSnapshotChunk(0, length);
  assert.ok(bytes instanceof Uint8Array && bytes.byteLength === length,
    'invalid player world snapshot payload');
  const view = new DataView(bytes.buffer, bytes.byteOffset, bytes.byteLength);
  return {
    x: view.getInt32(36, true),
    y: view.getInt32(40, true),
    angle: view.getInt32(48, true) & 0xffff,
  };
}

function logicalViewWrites(rawWrites,playerMask) {
  if(!bundleMode&&!viewBundleMode)return rawWrites;
  const byTic=new Map();
  for(const entry of rawWrites) {
    const batch=entry.payload.bytes;
    if(viewBundleMode) {
      if(nativeTemporalMode
          &&batch[0]===68&&batch[1]===80
          &&batch[2]===68&&batch[3]===49) {
        const mask=batch[8];
        let logical=byTic.get(entry.binds.frameTic);
        if(logical===undefined) {
          const bytes=new Uint8Array(
            16+(playerMask===3?2:1)*64_000);
          bytes.set([68,80,68,49],0);
          new DataView(bytes.buffer).setUint32(4,entry.binds.frameTic);
          bytes[8]=playerMask;bytes[9]=255;bytes[10]=255;bytes[11]=batch[11];
          logical={
            binds:{frameTic:entry.binds.frameTic,playerMask},
            payload:{bytes},logicalMask:0,
          };
          byTic.set(entry.binds.frameTic,logical);
        }
        for(let slot=0,ordinal=0;slot<2;slot++) {
          if((mask&(1<<slot))===0)continue;
          logical.payload.bytes[9+slot]=batch[9+slot];
          logical.payload.bytes.set(
            batch.subarray(16+ordinal*64_000,16+(ordinal+1)*64_000),
            16+slot*64_000);
          logical.logicalMask|=1<<slot;
          ordinal+=1;
        }
        continue;
      }
      assert.deepEqual([...batch.subarray(0,4)],[68,80,86,50]);
      const view=new DataView(batch.buffer,batch.byteOffset,batch.byteLength);
      const firstTic=view.getUint32(4);
      const count=view.getUint32(8);
      const bundleMask=batch[12];
      assert.ok((bundleMask&playerMask)===bundleMask&&bundleMask>0);
      assert.deepEqual([...batch.subarray(13,16)],[0,0,0]);
      const players=bundleMask===3?2:1;
      const recordBytes=8+players*64_000;
      assert.equal(batch.byteLength,16+count*recordBytes);
      assert.equal(
        nativeTemporalMode?entry.binds.currentTic:entry.binds.lastTic,
        firstTic+count-1);
      if(!nativeTemporalMode)
        assert.equal(entry.binds.payloadBytes,batch.byteLength);
      for(let index=0;index<count;index++) {
        const record=16+index*recordBytes;
        const tic=view.getUint32(record);
        assert.equal(tic,firstTic+index);
        if((bundleMask&1)!==0)
          assert.ok(batch[record+4]>=0&&batch[record+4]<=13);
        else assert.equal(batch[record+4],255);
        if((bundleMask&2)!==0)assert.ok(
          batch[record+5]>=0&&batch[record+5]<=13);
        else assert.equal(batch[record+5],255);
        assert.ok(batch[record+6]===0||batch[record+6]===1);
        assert.equal(batch[record+7],0);
        let logical=byTic.get(tic);
        if(logical===undefined) {
          const bytes=new Uint8Array(
            16+(playerMask===3?2:1)*64_000);
          bytes.set([68,80,68,49],0);
          new DataView(bytes.buffer).setUint32(4,tic);
          bytes[8]=playerMask;bytes[9]=255;bytes[10]=255;
          bytes[11]=batch[record+6];
          logical={
            binds:{frameTic:tic,playerMask},
            payload:{bytes},logicalMask:0,
          };
          byTic.set(tic,logical);
        }
        for(let slot=0,ordinal=0;slot<2;slot++) {
          if((bundleMask&(1<<slot))===0)continue;
          logical.payload.bytes[9+slot]=batch[record+4+slot];
          logical.payload.bytes.set(
            batch.subarray(
              record+8+ordinal*64_000,
              record+8+(ordinal+1)*64_000),
            16+slot*64_000);
          logical.logicalMask|=1<<slot;
          ordinal+=1;
        }
      }
      continue;
    }
    assert.deepEqual([...batch.subarray(0,4)],[68,80,66,50]);
    const view=new DataView(batch.buffer,batch.byteOffset,batch.byteLength);
    const count=view.getUint32(4);
    assert.equal(count,entry.binds.frameCount);
    assert.equal(batch.byteLength,8+count*64_008);
    for(let index=0;index<count;index++) {
      const record=8+index*64_008;
      const tic=view.getUint32(record);
      let logical=byTic.get(tic);
      if(logical===undefined) {
        const bytes=new Uint8Array(16+(playerMask===3?2:1)*64_000);
        bytes.set([68,80,68,49],0);
        new DataView(bytes.buffer).setUint32(4,tic);
        bytes[8]=playerMask;bytes[9]=255;bytes[10]=255;
        bytes[11]=batch[record+5];
        logical={binds:{frameTic:tic,playerMask},payload:{bytes}};
        byTic.set(tic,logical);
      }
      const slot=entry.binds.playerSlot;
      logical.payload.bytes[9+slot]=batch[record+4];
      logical.payload.bytes.set(
        batch.subarray(record+8,record+64_008),
        16+slot*64_000);
    }
  }
  return [...byTic.values()].sort(
    (left,right)=>left.binds.frameTic-right.binds.frameTic);
}

try {
  const stubPath = path.join(temporary, 'oracledb.mjs');
  writeFileSync(stubPath, `
export default {
  BIND_OUT: 3003,
  ORACLE_BLOB: 2019,
  defaultConnection() {
    return {
      execute(sql, binds) {
        if (sql.includes('materialize_temporal_bundle')) {
          globalThis.__doomdbMaterializeTemporal();
          return {rowsAffected: 1};
        }
        const payload = new globalThis.OracleBlob();
        globalThis.__doomdbTemporalWrites.push({sql, binds, payload});
        return {rowsAffected: 1, outBinds: {payload: [payload]}};
      },
    };
  },
};
`);
  const rendererUrl = pathToFileURL(rendererPath).href;
  const transformed = readFileSync(coordinatorPath, 'utf8')
    .replace(
      "import * as engine from 'doom_dvl2_engine';",
      `import * as engine from '${rendererUrl}';`)
    .replace(
      "import * as renderer from 'doom_live_renderer';",
      `import * as renderer from '${rendererUrl}';`)
    .replace(
      "import * as compositor from 'doom_live_compositor';",
      `import * as compositor from '${rendererUrl}';`)
    .replace(
      "import oracledb from 'mle-js-oracledb';",
      `import oracledb from '${pathToFileURL(stubPath).href}';`);
  const modulePath = path.join(temporary, 'coordinator.mjs');
  writeFileSync(modulePath, transformed);
  const api = await import(pathToFileURL(modulePath).href);
  const iwad = new Uint8Array(readFileSync(iwadPath));
  const tables = new Uint8Array(readFileSync(tablePath));
  const reloadAuthorityAssets = label => {
    load(api.allocateIwad, api.loadIwadChunk, iwad, `${label} IWAD`);
    load(
      api.allocateTablePack, api.loadTablePackChunk, tables,
      `${label} tables`);
  };
  reloadAuthorityAssets('initial');
  const initialized = api.initializeMultiplayerGame(2, 0, 3, 1, 1);
  assert.match(initialized, /state=multiplayer-initialized\|gametic=0\|/);

  const matchId = '0123456789abcdef0123456789abcdef';
  const command = new Uint8Array(32);
  command[0] = 25;
  const writesPerTic = [];
  let cameraAtFirstForwardTic;
  const lastTic=1+2*keyframeInterval;
  const soloInputTics=new Set(soloInputAwareMode?[2,5,7]:[]);
  for (let tic = 1; tic <= lastTic; tic++) {
    assert.equal(api.stepOnly(2, 1, command), tic, `step tic ${tic}`);
    if (tic === 1) cameraAtFirstForwardTic = playerCamera(api);
    const before = globalThis.__doomdbTemporalWrites.length;
    assert.equal(
      api.prepareMatchViews(
        matchId, 1, 1, 1, tic, soloInputTics.has(tic)?1:0), 64_016,
      `prepare tic ${tic}`);
    assert.equal(
      api.publishPreparedMatchViews(matchId, 1, 1, 1, tic), 64_016,
      `publish tic ${tic}`);
    writesPerTic.push(globalThis.__doomdbTemporalWrites.length - before);
  }
  assert.deepEqual(writesPerTic,
    Array.from({length:lastTic},(_,index)=>{
      const tic=index+1;
      if(soloInputAwareMode)return [1,2,5,7].includes(tic)?1:0;
      if(tic===1)return 1;
      if((tic-1)%keyframeInterval!==0)return 0;
      return bundleMode||viewBundleMode?1:keyframeInterval;
    }));
  const writes = logicalViewWrites(globalThis.__doomdbTemporalWrites,1);
  assert.deepEqual(writes.map(entry => entry.binds.frameTic),
    Array.from({length:lastTic},(_,index)=>index+1));
  for (const [index, entry] of writes.entries()) {
    const bytes = entry.payload.bytes;
    assert.equal(bytes.byteLength, 64_016);
    assert.deepEqual([...bytes.subarray(0, 4)], [68,80,68,49]);
    assert.equal(new DataView(
      bytes.buffer, bytes.byteOffset, bytes.byteLength).getUint32(4), index + 1);
    assert.equal(bytes[8], 1);
    assert.equal(bytes[11], 1);
  }
  const exactEndpointDiffs=[];
  const soloEndpoints=soloInputAwareMode?[1,2,5,7]:Array.from(
    {length:3},(_,index)=>1+index*keyframeInterval);
  for(let pair=0;pair<soloEndpoints.length-1;pair++) {
    const tic=soloEndpoints[pair];
    const currentTic=soloEndpoints[pair+1];
    const previous=writes[tic-1].payload.bytes;
    const current=writes[currentTic-1].payload.bytes;
    let changed=0;
    for(let offset=16;offset<64_016;offset+=1) {
      if(previous[offset]!==current[offset])changed+=1;
    }
    exactEndpointDiffs.push(changed);
    assert.ok(changed>=1_000,
      `current-camera keyframes changed only ${changed} pixels at tic ${tic}`);
  }

  // Every intermediate frame is the exact spatial phase mix between adjacent
  // keyframes. This checks every pixel, not a sampled visual checksum.
  for (let pair=0;pair<soloEndpoints.length-1;pair++) {
    const priorTic=soloEndpoints[pair];
    const currentTic=soloEndpoints[pair+1];
    const interval=currentTic-priorTic;
    const previous = writes[priorTic - 1].payload.bytes;
    const current = writes[currentTic - 1].payload.bytes;
    const sameMetadata=previous[9]===current[9]
      &&previous[11]===current[11];
    for (let phase = 1; phase < interval; phase++) {
      const synthetic = writes[priorTic + phase - 1].payload.bytes;
      const tic = priorTic + phase;
      for (let row = 0; row < 200; row++) {
        for (let column = 0; column < 320; column++) {
          const offset = 16 + row * 320 + column;
          const pixel=row*320+column;
          const expected=!sameMetadata
            ?current[offset]
            :(pixel+tic)%interval<phase?current[offset]:previous[offset];
          assert.equal(
            synthetic[offset], expected,
            `synthetic mismatch tic=${tic} row=${row} column=${column}`);
        }
      }
    }
  }

  // A changed framebuffer is not sufficient evidence that controls work:
  // weapon/world animation changes pixels while the player remains still.
  // Pin the authoritative pose exported by the same retained MLE engine.
  const cameraAfterHeldForward = playerCamera(api);
  const forwardDisplacement = Math.hypot(
    cameraAfterHeldForward.x - cameraAtFirstForwardTic.x,
    cameraAfterHeldForward.y - cameraAtFirstForwardTic.y);
  assert.ok(forwardDisplacement > 0,
    'held forward command did not move the authoritative player');
  const turnLeft = new Uint8Array(32);
  new DataView(turnLeft.buffer).setInt16(2, 320, false);
  for (let tic = lastTic+1; tic <= lastTic+7; tic++) {
    assert.equal(api.stepOnly(2, 1, turnLeft), tic, `turn step tic ${tic}`);
  }
  const cameraAfterHeldTurn = playerCamera(api);
  assert.notEqual(cameraAfterHeldTurn.angle, cameraAfterHeldForward.angle,
    'held turn command did not rotate the authoritative player');

  // A new generation cannot inherit a prior-generation interpolation source.
  api.release();
  reloadAuthorityAssets('recovery');
  const recovered = api.initializeMultiplayerGame(2, 0, 3, 1, 1);
  assert.match(recovered, /state=multiplayer-initialized\|gametic=0\|/);
  assert.equal(api.stepOnly(2, 1, command), 1);
  let before = globalThis.__doomdbTemporalWrites.length;
  assert.equal(api.prepareMatchViews(matchId, 1, 1, 2, 1), 64_016);
  assert.equal(api.publishPreparedMatchViews(matchId, 1, 1, 2, 1), 64_016);
  assert.equal(globalThis.__doomdbTemporalWrites.length - before, 1);
  const recoveryWrites=logicalViewWrites(
    globalThis.__doomdbTemporalWrites.slice(before),1);
  assert.equal(recoveryWrites.at(-1).binds.frameTic, 1);

  // Multiplayer keeps two complete, distinct database-authored viewpoints.
  // Its temporal interval reduces the expensive exact two-POV raster rate
  // while preserving every confirmed tic as a complete 128,000-pixel
  // payload. Exact endpoints remain the proven Mocha renderer output.
  api.release();
  reloadAuthorityAssets('multiplayer');
  const multiplayer = api.initializeMultiplayerGame(2, 1, 3, 1, 1);
  assert.match(multiplayer, /state=multiplayer-initialized\|gametic=0\|/);
  const multiplayerWriteStart=globalThis.__doomdbTemporalWrites.length;
  const multiplayerWritesPerTic=[];
  const multiplayerLastTic=staggeredMode
    ? inputAwareMode?17:3*multiplayerKeyframeInterval-1
    : 1+2*multiplayerKeyframeInterval;
  for (let tic = 1; tic <= multiplayerLastTic; tic++) {
    assert.equal(api.stepOnly(2, 3, command), tic);
    before = globalThis.__doomdbTemporalWrites.length;
    const inputMask=inputAwareMode
      ? ({2:1,3:1,5:2,6:2,7:3}[tic]??0)
      : 0;
    assert.equal(
      api.prepareMatchViews(matchId,3,1,3,tic,inputMask),128_016);
    assert.equal(api.publishPreparedMatchViews(matchId, 3, 1, 3, tic), 128_016);
    multiplayerWritesPerTic.push(
      globalThis.__doomdbTemporalWrites.length-before);
  }
  assert.deepEqual(multiplayerWritesPerTic,
    Array.from({length:multiplayerLastTic},(_,index)=>{
      const tic=index+1;
      if(staggeredMode) {
        if(inputAwareMode) {
          return [1,3,4,6,7,11,12,16,17].includes(tic)?1:0;
        }
        const playerZeroDue=tic>1
          &&(tic-1)%multiplayerKeyframeInterval===0;
        const playerOneDue=tic>=multiplayerKeyframeInterval-1
          &&(tic-(multiplayerKeyframeInterval-1))
            %multiplayerKeyframeInterval===0;
        return tic===1||playerZeroDue||playerOneDue?1:0;
      }
      if(viewBundleMode)
        return tic===1?1:(tic-1)%multiplayerKeyframeInterval===0?1:0;
      if(bundleMode)
        return tic===1?2:(tic-1)%multiplayerKeyframeInterval===0?2:0;
      return tic===1?1:(tic-1)%multiplayerKeyframeInterval===0
        ?multiplayerKeyframeInterval:0;
    }));
  const allMultiplayerWrites=logicalViewWrites(
    globalThis.__doomdbTemporalWrites.slice(multiplayerWriteStart),3);
  const multiplayerWrites=staggeredMode
    ?allMultiplayerWrites.filter(entry=>entry.logicalMask===3)
    :allMultiplayerWrites;
  assert.deepEqual(
    multiplayerWrites.map(entry=>entry.binds.frameTic),
    Array.from(
      {length:staggeredMode
        ?inputAwareMode?16:2*multiplayerKeyframeInterval+1
        :multiplayerLastTic},
      (_,index)=>index+1));
  for(const entry of multiplayerWrites) {
    const payload=entry.payload.bytes;
    assert.equal(payload.byteLength, 128_016);
    assert.equal(payload[8], 3);
    assert.equal(entry.binds.playerMask,3);
    assert.equal(
      new DataView(payload.buffer,payload.byteOffset,payload.byteLength)
        .getUint32(4),
      entry.binds.frameTic);
  }
  for(const entry of multiplayerWrites) {
    const payload=entry.payload.bytes;
    assert.notDeepEqual(
      payload.subarray(16,64_016),payload.subarray(64_016,128_016),
      `multiplayer viewpoints collapsed at tic ${entry.binds.frameTic}`);
  }
  if(!staggeredMode) {
    for(let syntheticTic=2;syntheticTic<multiplayerLastTic;syntheticTic++) {
      const numerator=(syntheticTic-1)%multiplayerKeyframeInterval;
      if(numerator===0)continue;
      const previousTic=syntheticTic-numerator;
      const currentTic=previousTic+multiplayerKeyframeInterval;
      const previous=multiplayerWrites[previousTic-1].payload.bytes;
      const synthetic=multiplayerWrites[syntheticTic-1].payload.bytes;
      const current=multiplayerWrites[currentTic-1].payload.bytes;
      assert.equal(previous[9],current[9]);
      assert.equal(previous[10],current[10]);
      for(let offset=16;offset<128_016;offset+=1) {
        const pixel=offset-16;
        const row=Math.floor((pixel%64_000)/320);
        const column=pixel%320;
        const choosePrevious=multiplayerKeyframeInterval===2
          ? ((row+column+syntheticTic)&1)===0
          : (pixel+syntheticTic)%multiplayerKeyframeInterval>=numerator;
        assert.equal(synthetic[offset],
          choosePrevious?previous[offset]:current[offset],
          `multiplayer temporal mismatch tic=${syntheticTic} offset=${offset}`);
      }
    }
  } else {
    const byTic=new Map(allMultiplayerWrites.map(
      entry=>[entry.binds.frameTic,entry]));
    const endpoints=inputAwareMode
      ? [[1,3,7,12,17],[1,4,6,11,16]]
      : [
        [1,1+multiplayerKeyframeInterval,
          1+2*multiplayerKeyframeInterval],
        [1,multiplayerKeyframeInterval-1,
          2*multiplayerKeyframeInterval-1,
          3*multiplayerKeyframeInterval-1],
      ];
    for(let playerSlot=0;playerSlot<2;playerSlot++) {
      const frameOffset=16+playerSlot*64_000;
      for(let pair=0;pair<endpoints[playerSlot].length-1;pair++) {
        const previousTic=endpoints[playerSlot][pair];
        const currentTic=endpoints[playerSlot][pair+1];
        const interval=currentTic-previousTic;
        const previous=byTic.get(previousTic);
        const current=byTic.get(currentTic);
        assert.ok((previous.logicalMask&(1<<playerSlot))!==0);
        assert.ok((current.logicalMask&(1<<playerSlot))!==0);
        const sameMetadata=[9+playerSlot,11].every(offset=>
          previous.payload.bytes[offset]===current.payload.bytes[offset]);
        for(let tic=previousTic+1;tic<currentTic;tic++) {
          const synthetic=byTic.get(tic);
          assert.ok((synthetic.logicalMask&(1<<playerSlot))!==0);
          const numerator=tic-previousTic;
          for(let pixel=0;pixel<64_000;pixel++) {
            const expected=!sameMetadata
              ?current.payload.bytes[frameOffset+pixel]
              :(pixel+tic)%interval<numerator
                ?current.payload.bytes[frameOffset+pixel]
                :previous.payload.bytes[frameOffset+pixel];
            assert.equal(
              synthetic.payload.bytes[frameOffset+pixel],expected,
              `staggered temporal mismatch slot=${playerSlot}`
                + ` tic=${tic} pixel=${pixel}`
                + ` interval=${interval} numerator=${numerator}`
                + ` metadata=${sameMetadata}`
                + ` previous=${previous.payload.bytes[frameOffset+pixel]}`
                + ` current=${current.payload.bytes[frameOffset+pixel]}`);
          }
        }
      }
    }
  }
  api.release();
  process.stdout.write(
    'PASS PMLE-TEMPORAL-SOLO-COORDINATOR '
      + `tics=${lastTic} writes=${lastTic} interval=${keyframeInterval}`
      + ` exact=3`
      + ` synthesized=${lastTic-3}`
      + ` forward_displacement=${forwardDisplacement.toFixed(3)}`
      + ` turn_delta=${
        (cameraAfterHeldTurn.angle-cameraAfterHeldForward.angle+65536)%65536}`
      + ` keyframe_changed_pixels=${exactEndpointDiffs.join('/')}`
      + ' movement=PASS consecutive=YES generation_reset=PASS'
      + ` multiplayer_two_pov_temporal=PASS`
      + ` temporal_bundle=${
        staggeredMode?'EPT1_STAGGERED_MASKED_DPV2':
          nativeTemporalMode?'EPT1_NATIVE_EXACT_DPV2':
          viewBundleMode?'DPV2_COMBINED_TEMPORAL_AND_POV':
          bundleMode?'DPB2_PER_PLAYER':'DPD1_PER_TIC'}`
      + ` multiplayer_interval=${multiplayerKeyframeInterval}\n`);
} finally {
  rmSync(temporary, {recursive: true, force: true});
}
