import assert from 'node:assert/strict';
import {ConfirmedWanPolicy,confirmedPlayoutDecision,confirmedPlayoutIntervalMs}
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
assert.throws(()=>confirmedPlayoutIntervalMs(-1),/invalid/);
assert.throws(()=>confirmedPlayoutIntervalMs(1.5),/invalid/);
console.log('PASS confirmed WAN lead/playout/hysteresis/substitution policy');
