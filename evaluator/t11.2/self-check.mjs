import assert from 'node:assert/strict';
import fs from 'node:fs';
import {makeEvidence,sha,validateEvidence,validatePolicy} from './reference.mjs';

const fixture=JSON.parse(fs.readFileSync(
  new URL('./fixtures.json',import.meta.url)));
const testIds=JSON.parse(fs.readFileSync(
  new URL('./test-ids.json',import.meta.url))).tests;
let assertions=0;
const check=(value,label)=>{assert.ok(value,label);assertions++;};
check(validatePolicy(fixture),'policy');
const evidence=makeEvidence(fixture);
check(validateEvidence(evidence,fixture),'positive evidence');
check(testIds.length===16&&new Set(testIds.map(row=>row.id)).size===16,
  'test-id inventory');
check(evidence.deployment.objects.length===17,'exact static inventory');
check(evidence.target.sameOrigin,'same origin');
check(evidence.browser.performance.fps>=30,'30 FPS');
check(evidence.browser.performance.uniqueFrames===300,'unique moving frames');
check(evidence.deployment.objects.some(object=>
  object.cacheControl===fixture.cachePolicy.immutable),'immutable assets');
check(evidence.deployment.objects.some(object=>
  object.key==='COPYING-freedoom.txt'),'redistribution notice');
check(sha('stable')===sha('stable'),'deterministic hash');
process.stdout.write(
  `PASS T11.2-EVAL-SELF-CHECK (${assertions}/${assertions} hosted-contract assertions)\n`);
