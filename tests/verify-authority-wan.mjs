import assert from 'node:assert/strict';
import {ConfirmedWanPolicy} from '../client/staging/authority-wan.js';

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
assert.ok(policy.playoutBufferTics >= 2 && policy.playoutBufferTics <= 6);
assert.equal(policy.presentationTargetTic(50), 50 - policy.playoutBufferTics);

for (let tic = 0; tic < 1000; tic += 1) {
  policy.recordScheduledTic(tic < 4);
}
assert.equal(policy.neutralSubstitutionRate, 0.004);
assert.throws(() => policy.observeRoundTrip(-1, 0), /invalid/);
assert.throws(() => policy.inputTargetTic(-1), /invalid/);
console.log('PASS confirmed WAN lead/playout/hysteresis/substitution policy');
