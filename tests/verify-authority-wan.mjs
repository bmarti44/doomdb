import assert from 'node:assert/strict';
import {
  ConfirmedWanPolicy,confirmedBatchPlayoutDecision,
  confirmedPlayoutDecision,confirmedPlayoutIntervalMs,
  confirmedInputCatchupCursor,databasePixelPlayoutIntervalMs
}
  from '../client/staging/authority-wan.js';

const policy = new ConfirmedWanPolicy();
assert.equal(policy.inputTargetTic(100), 102);
assert.equal(policy.presentationTargetTic(100), 99);

policy.observeRoundTrip(200, 0);
assert.equal(policy.inputLeadTics, 3, 'lead may move by only one tic');
policy.observeRoundTrip(200, 1_000);
assert.equal(policy.inputLeadTics, 3, 'ten-second hysteresis must hold');
policy.observeRoundTrip(200, 10_001);
assert.equal(policy.inputLeadTics, 4);
for (let time = 20_002; time < 100_000; time += 10_001) {
  policy.observeRoundTrip(400, time);
}
assert.equal(policy.inputLeadTics, 12, 'lead must clamp at twelve tics');
const gapPolicy = new ConfirmedWanPolicy();
gapPolicy.observeRoundTrip(50, 0, 7);
assert.equal(gapPolicy.inputLeadTics, 3, 'frontier gap still moves one tic');
gapPolicy.observeRoundTrip(50, 10_001, 7);
assert.equal(gapPolicy.inputLeadTics, 4);
assert.throws(()=>gapPolicy.observeRoundTrip(50,20_002,1),/invalid/);

policy.observeConfirmedDelivery(0);
policy.observeConfirmedDelivery(28.6);
policy.observeConfirmedDelivery(97.2);
assert.equal(policy.playoutBufferTics,3);
assert.equal(policy.preClampPlayoutBufferTics,3);
assert.equal(policy.presentationTargetTic(50), 50 - policy.playoutBufferTics);
const clampPolicy=new ConfirmedWanPolicy();
clampPolicy.observeConfirmedDelivery(0);
clampPolicy.observeConfirmedDelivery(1000);
assert.ok(clampPolicy.preClampPlayoutBufferTics>6);
assert.equal(clampPolicy.playoutBufferTics,6);
const batchPolicy=new ConfirmedWanPolicy();
batchPolicy.observeConfirmedBatch(0,7);
assert.equal(batchPolicy.expectedConfirmedBatchTics,7);
assert.equal(batchPolicy.preClampPlayoutBufferTics,1);
assert.equal(batchPolicy.playoutBufferTics,1,
  'normal batch width is separate from the jitter reserve');
batchPolicy.observeConfirmedBatch(200,7);
assert.equal(batchPolicy.playoutBufferTics,1);
batchPolicy.observeConfirmedBatch(460,7);
assert.equal(batchPolicy.playoutBufferTics,4,
  'only positive late delivery deficit grows the reserve');
batchPolicy.resetConfirmedBatchDelivery();
assert.equal(batchPolicy.expectedConfirmedBatchTics,1);
assert.equal(batchPolicy.playoutBufferTics,1);
const lowLatencyBatchPolicy=new ConfirmedWanPolicy();
lowLatencyBatchPolicy.observeConfirmedBatch(0,2);
lowLatencyBatchPolicy.observeConfirmedBatch(1000/17.5,2);
assert.equal(lowLatencyBatchPolicy.expectedConfirmedBatchTics,2);
assert.equal(lowLatencyBatchPolicy.preClampPlayoutBufferTics,1);
assert.equal(lowLatencyBatchPolicy.playoutBufferTics,1);
assert.throws(()=>batchPolicy.observeConfirmedBatch(1,-1),/invalid/);
assert.throws(()=>batchPolicy.observeConfirmedBatch(1,65),/invalid/);
const pixelPolicy=new ConfirmedWanPolicy(6,6);
assert.equal(pixelPolicy.playoutBufferTics,6);
const livePixelPolicy=new ConfirmedWanPolicy(6,6);
assert.equal(livePixelPolicy.playoutBufferTics,6,
  'live database-pixel reserve changed');
livePixelPolicy.observeConfirmedBatch(0,2);
livePixelPolicy.observeConfirmedBatch(1000/17.5,2);
assert.equal(livePixelPolicy.playoutBufferTics,6);
assert.equal(pixelPolicy.preClampPlayoutBufferTics,6);
pixelPolicy.observeConfirmedBatch(0,6);
pixelPolicy.observeConfirmedBatch(1000/35*6,6);
assert.equal(pixelPolicy.playoutBufferTics,6,
  'database-pixel reserve must not shrink below its qualified startup floor');
pixelPolicy.resetConfirmedBatchDelivery();
assert.equal(pixelPolicy.playoutBufferTics,6);
assert.throws(()=>new ConfirmedWanPolicy(0),/invalid/);
assert.throws(()=>new ConfirmedWanPolicy(13,13),/invalid/);
assert.throws(()=>new ConfirmedWanPolicy(7,6),/invalid/);

for (let tic = 0; tic < 1000; tic += 1) {
  policy.recordScheduledTic(tic < 4);
}
assert.equal(policy.neutralSubstitutionRate, 0.004);
assert.throws(() => policy.observeRoundTrip(-1, 0), /invalid/);
assert.throws(() => policy.inputTargetTic(-1), /invalid/);
assert.equal(confirmedPlayoutIntervalMs(0),1000/35);
assert.equal(confirmedPlayoutIntervalMs(1),1000/35);
assert.equal(confirmedPlayoutIntervalMs(2),1000/35);
assert.equal(confirmedPlayoutIntervalMs(6),1000/35);
assert.equal(confirmedPlayoutIntervalMs(7),1000/70);
assert.equal(confirmedPlayoutIntervalMs(16),1000/70);
let mode='FREE';
for(const [occupancy,expectedMode,expectedInterval] of [
  [9,'ACCELERATE',1000/70],
  [8,'ACCELERATE',1000/70],
  [7,'ACCELERATE',1000/70],
  [6,'FREE',1000/35],
  [4,'FREE',1000/35],
  [3,'DECELERATE',31.4],
  [5,'DECELERATE',31.4],
  [6,'FREE',1000/35]
]) {
  const decision=confirmedPlayoutDecision(occupancy,6,mode);
  assert.equal(decision.mode,expectedMode,
    `setpoint mode changed at occupancy ${occupancy}`);
  assert.equal(decision.intervalMs,expectedInterval);
  mode=decision.mode;
}
assert.throws(()=>confirmedPlayoutDecision(-1,6,'FREE'),/invalid/);
assert.throws(()=>confirmedPlayoutDecision(1,7,'FREE'),/invalid/);
assert.throws(()=>confirmedPlayoutDecision(1,6,'INVALID'),/invalid/);
let batchMode='FREE';
for(const [occupancy,expectedMode,expectedInterval] of [
  [14,'FREE',1000/35],
  [6,'FREE',1000/35],
  [17,'ACCELERATE',1000/70],
  [14,'FREE',1000/35],
  [3,'DECELERATE',31.4],
  [6,'FREE',1000/35]
]) {
  const decision=confirmedBatchPlayoutDecision(
    occupancy,6,8,batchMode);
  assert.equal(decision.mode,expectedMode,
    `batch setpoint mode changed at occupancy ${occupancy}`);
  assert.equal(decision.intervalMs,expectedInterval);
  batchMode=decision.mode;
}
assert.throws(()=>confirmedBatchPlayoutDecision(1,6,0,'FREE'),/invalid/);
assert.equal(confirmedBatchPlayoutDecision(7,12,8,'FREE').mode,'DECELERATE');
assert.throws(()=>confirmedBatchPlayoutDecision(1,13,8,'FREE'),/invalid/);
// Atomic batch behavioral cell: a normal eight-frame sawtooth must preserve
// the six-frame reserve without ever entering acceleration or starvation.
let atomicOccupancy=14;
let atomicMode='FREE';
let atomicMinimum=atomicOccupancy;
for(let batch=0;batch<100;batch+=1) {
  for(let frame=0;frame<8;frame+=1) {
    atomicOccupancy-=1;
    atomicMinimum=Math.min(atomicMinimum,atomicOccupancy);
    const decision=confirmedBatchPlayoutDecision(
      atomicOccupancy,6,8,atomicMode);
    atomicMode=decision.mode;
    assert.equal(atomicMode,'FREE');
  }
  assert.equal(atomicOccupancy,6);
  atomicOccupancy+=8;
}
assert.equal(atomicMinimum,6);
// Timed atomic-arrival model with alternating two-tic late/early jitter. The
// normal eight-frame batch is replenished after ten then six presentation
// periods; the batch-aware band must retain confirmed occupancy throughout.
let jitterOccupancy=14;
let jitterMode='FREE';
let jitterMinimum=jitterOccupancy;
for(let cycle=0;cycle<100;cycle+=1) {
  const periods=cycle%2===0?10:6;
  for(let period=0;period<periods;period+=1) {
    assert.ok(jitterOccupancy>0,'timed atomic batch model starved');
    jitterOccupancy-=1;
    jitterMinimum=Math.min(jitterMinimum,jitterOccupancy);
    jitterMode=confirmedBatchPlayoutDecision(
      jitterOccupancy,6,8,jitterMode).mode;
  }
  jitterOccupancy+=8;
}
assert.ok(jitterMinimum>=4);
assert.ok(jitterOccupancy>=6);
// A three-tic late delivery enters bounded deceleration below the reserve;
// the following batch restores FREE mode without acceleration.
atomicOccupancy=3;
let jitterDecision=confirmedBatchPlayoutDecision(
  atomicOccupancy,6,8,atomicMode);
assert.equal(jitterDecision.mode,'DECELERATE');
atomicOccupancy+=8;
jitterDecision=confirmedBatchPlayoutDecision(
  atomicOccupancy,6,8,jitterDecision.mode);
assert.equal(jitterDecision.mode,'FREE');
assert.throws(()=>confirmedPlayoutIntervalMs(-1),/invalid/);
assert.throws(()=>confirmedPlayoutIntervalMs(1.5),/invalid/);
assert.equal(databasePixelPlayoutIntervalMs(true,'FREE',false),1000/35);
assert.equal(databasePixelPlayoutIntervalMs(true,'ACCELERATE',true),20);
assert.equal(databasePixelPlayoutIntervalMs(true,'DECELERATE',false),31);
assert.equal(databasePixelPlayoutIntervalMs(false,'FREE',false),33);
assert.equal(databasePixelPlayoutIntervalMs(false,'ACCELERATE',false),16.5);
assert.equal(databasePixelPlayoutIntervalMs(false,'ACCELERATE',true),25);
assert.equal(databasePixelPlayoutIntervalMs(false,'DECELERATE',false),33.2);
assert.throws(
  ()=>databasePixelPlayoutIntervalMs(false,'INVALID',false),/invalid/);
assert.equal(confirmedInputCatchupCursor(100,110,104),104);
assert.equal(confirmedInputCatchupCursor(100,110,120),109);
assert.equal(confirmedInputCatchupCursor(100,90,120),100);
assert.equal(confirmedInputCatchupCursor(-1,1,0),0);
assert.throws(()=>confirmedInputCatchupCursor(1,2,1.5),/invalid/);
console.log('PASS confirmed WAN lead/playout/hysteresis/substitution policy');
