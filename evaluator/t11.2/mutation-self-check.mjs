import assert from 'node:assert/strict';
import fs from 'node:fs';
import {makeEvidence,validateEvidence} from './reference.mjs';

const fixture=JSON.parse(fs.readFileSync(
  new URL('./fixtures.json',import.meta.url)));
const specifications=JSON.parse(fs.readFileSync(
  new URL('./mutation-specs.json',import.meta.url))).mutations;
const mutations=[
  ['localTarget',e=>{e.target.provider='LOCAL';}],
  ['crossOrigin',e=>{e.target.sameOrigin=false;}],
  ['nonDatabaseStatics',e=>{e.target.databaseResidentStatics=false;}],
  ['wrongModule',e=>{e.deployment.dedicatedModule='doom_api';}],
  ['extraModule',e=>{e.deployment.moduleCount=2;}],
  ['extraAutoRest',e=>{e.deployment.autoRestObjects.push('DOOM_HOSTED_ASSET');}],
  ['extraArtifact',e=>{e.deployment.objects.push({...e.deployment.objects[0],key:'secret.map'});}],
  ['databaseShaDrift',e=>{e.deployment.objects[0].databaseSha256='0'.repeat(64);}],
  ['liveShaDrift',e=>{e.deployment.objects[0].liveGetSha256='0'.repeat(64);}],
  ['badMime',e=>{e.deployment.objects[0].contentType='application/json';}],
  ['badCache',e=>{e.deployment.objects[0].cacheControl=fixture.cachePolicy.immutable;}],
  ['missingLicense',e=>{e.deployment.objects=e.deployment.objects.filter(x=>x.key!=='COPYING-freedoom.txt');}],
  ['routeMock',e=>{e.browser.routeFulfillCount=1;}],
  ['blobModuleDrift',e=>{e.browser.verifiedBlobModuleLoads=1;}],
  ['slowFps',e=>{e.browser.performance.fps=29.9;}],
  ['slowP95',e=>{e.browser.performance.p95IntervalMs=33.334;}],
  ['slowP99',e=>{e.browser.performance.p99IntervalMs=57.144;}],
  ['longPause',e=>{e.browser.performance.maxIntervalMs=100.001;}],
  ['browserRenderer',e=>{e.browser.performance.databasePixelFrames=false;}],
  ['duplicateFrame',e=>{e.browser.performance.uniqueFrames=299;}],
  ['ticGap',e=>{e.browser.performance.sequentialTics=false;}],
  ['multipleCheckpoints',e=>{e.runtime.checkpointCount=2;}],
  ['unmeasuredCheckpoint',e=>{e.runtime.checkpointUnmeasuredCount=1;}],
  ['slowCheckpoint',e=>{
    e.runtime.checkpointSlowCount=1;e.runtime.checkpointMaxStepMs=101;
  }],
  ['checkpointTimingLie',e=>{
    e.runtime.checkpointTimingSource='SPARSE_GT_100MS_SLOW_CALLS';
  }],
  ['runtimeAuthorityDrift',e=>{e.runtime.authoritySha256='0'.repeat(64);}],
  ['capacityLeak',e=>{e.browser.cleanup.released=false;}],
  ['otherOrigin',e=>{e.network[0].originSha256='f'.repeat(64);}],
  ['redirect',e=>{e.network[0].redirected=true;}],
  ['credentialLeak',e=>{e.authorization='secret';}],
  ['nonAtomic',e=>{e.provenance.atomicWrite=false;}]
];
assert.deepEqual(specifications.map(row=>row.mode),mutations.map(row=>row[0]),
  'declared mutation inventory');
let killed=0;
for(const [label,mutate] of mutations){
  const evidence=structuredClone(makeEvidence(fixture));
  mutate(evidence);
  assert.throws(()=>validateEvidence(evidence,fixture),label);
  killed++;
}
process.stdout.write(
  `PASS T11.2-EVAL-MUTATION-SELF-CHECK (${killed}/${mutations.length} mutations killed)\n`);
