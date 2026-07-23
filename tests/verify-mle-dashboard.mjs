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
  'pre-optimization authority-plus-standby baseline was 248.629 seconds cold',
  'confirmed-only game surface in 110.458 seconds',
  'separate Co-op and Multiplayer shortcuts remain on the right',
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
  '06ac33331d9a9158d63fba2da4688ad5d3ff30c316b4c20c09e38d77d3fdebf0');
assert.equal(status.artifacts.presentation.sha256,
  'bd35d27784db2332e1c06f08a7eeb8940b1a17a732bfb45de0b4b3b42d419b83');
assert.equal(status.gates.ledgerEveryTic13272, 'PASS');
assert.equal(status.gates.finalWorkerSoak, 'PASS');
assert.equal(status.gates.soloMleAuthority, 'PASS');
assert.equal(status.solo.legacyEndpointCalls, 0);
assert.equal(status.solo.startupOptimization, 'early authority admission verified');
assert.equal(status.solo.authorityAdmissionSeconds, 110.458);
assert.equal(status.architecture.productionOjvm, false);
assert.equal(status.remaining.find(item => item.id === 'ADB').state, 'DORMANT');
console.log('PASS MLE-DASHBOARD (current artifacts, evidence, links, and honesty gates)');
