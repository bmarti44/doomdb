#!/usr/bin/env node
import assert from 'node:assert/strict';
import fs from 'node:fs';

const staging = fs.readFileSync('client/staging/index.html', 'utf8');
const dist = fs.readFileSync('client/dist/index.html', 'utf8');
assert.equal(dist, staging, 'published dashboard differs from staging source');
for (const marker of [
  'Oracle AI Database 26ai Free',
  'MLE authority',
  '/play/multiplayer.html',
  "fetch('/mle-status.json'",
  'OJVM oracle stays in repository/dev tooling only',
  'Cold MLE initialization now measures 4.542–4.826 seconds',
  'full browser reached its first confirmed frame in 5.223 seconds',
  'separate Co-op and Multiplayer shortcuts remain on the right',
  'single normal lifecycle writer',
  'explicitly VOIDED',
  '58,875/58,858 confirmed presentations',
  'hidden-tab lifecycle',
  'WAN matrix',
  'Presentation / DVR'
]) {
  assert.ok(staging.includes(marker), `dashboard marker missing: ${marker}`);
}
for (const stale of [
  'new games use Mocha Doom in OJVM',
  'cloud certification next',
  'Current play page:</strong> new <code>/play/</code> games use Mocha Doom in OJVM'
]) {
  assert.ok(!staging.includes(stale), `stale dashboard claim survived: ${stale}`);
}
const status = JSON.parse(fs.readFileSync('client/dist/mle-status.json', 'utf8'));
assert.equal(status.schema, 1);
assert.equal(status.artifacts.authority.sha256,
  'a942cd2dcbdc8fa523a51af27aefc778ea9fbbebfe93f0a03fe4856c6df6c8e2');
assert.equal(status.artifacts.presentation.sha256,
  'e55d5f1138fa94d4fc7efd0acf27cbc89cb8a894e3d6828d84837a364b4426dc');
assert.equal(status.gates.presentationHud96Tics, 'PASS');
assert.equal(status.gates.ledgerEveryTic13272, 'PASS');
assert.equal(status.gates.finalWorkerSoak, 'PASS');
assert.equal(status.gates.lifecycleHardening, 'PASS');
assert.equal(status.gates.postHardeningCausalSoak, 'PASS');
assert.equal(status.gates.soloMleAuthority, 'PASS');
assert.equal(status.gates.warmPoolAdmissionP95, 'PASS');
assert.equal(status.gates.warmStandbyHealing, 'PASS');
assert.equal(status.solo.legacyEndpointCalls, 0);
assert.equal(status.solo.startupOptimization,
  'deploy-time retained MLE pool, exact tic-zero restore, and headless init diet');
assert.equal(status.solo.warmAdmissionP95Seconds, 3.440);
assert.equal(status.solo.warmAdmissionSamples, 10);
assert.equal(status.solo.sequentialAuthorityFirstAdmittableSeconds, 28);
assert.equal(status.soak.promotedAttemptState, 'VOIDED');
assert.equal(status.soak.postDietPartialPlateauProven, false);
assert.deepEqual(status.soak.causalSoakPresentations, [6286, 6287]);
assert.equal(status.soak.artifactSha256,
  'a942cd2dcbdc8fa523a51af27aefc778ea9fbbebfe93f0a03fe4856c6df6c8e2');
assert.deepEqual(status.soak.browserPresentations, [58875, 58858]);
assert.equal(status.soak.maxConfirmedLagTics, 17);
assert.equal(status.soak.resourceManagerCpuQuantumSamples, 0);
assert.equal(status.architecture.productionOjvm, false);
assert.equal(status.playModes.singlePlayer.state, 'AVAILABLE');
assert.equal(status.playModes.coop.path, '/play/multiplayer.html#mode=COOP');
assert.equal(status.playModes.multiplayer.path,
  '/play/multiplayer.html#mode=DEATHMATCH');
assert.equal(status.remaining.find(item => item.id === 'ADB').state, 'DORMANT');
console.log('PASS MLE-DASHBOARD (current artifacts, evidence, links, and honesty gates)');
