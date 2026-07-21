#!/usr/bin/env node
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import {
  readAndVerifyArtifacts, validateEvidenceShape
} from '../scripts/performance/t12.1-evidence.mjs';

const root = path.resolve(import.meta.dirname, '..');
const evidencePath = process.env.T121_EVIDENCE ??
  path.join(root, '.artifacts/t12.1/evidence.json');
const browserPath = process.env.T121_BROWSER_EVIDENCE ??
  path.join(root, '.artifacts/t12.1/browser-two-run.json');
const evidence = validateEvidenceShape(JSON.parse(fs.readFileSync(evidencePath)));
readAndVerifyArtifacts(evidence, evidencePath);
const browser = JSON.parse(fs.readFileSync(browserPath));
assert.equal(browser.schema, 1); assert.equal(browser.task, 'T12.1-BROWSER-TWO-RUN');
assert.equal(browser.replaySha256, evidence.replay.sha256);
assert.equal(browser.identicalChains, true);
assert.equal(browser.summaries.length, 2);
for (const summary of browser.summaries) {
  assert.equal(summary.frames, 300);
  assert.ok(summary.fps >= 30, `browser run ${summary.run} is below 30 FPS`);
}
const replayArtifact = evidence.rawArtifacts.find(row => row.kind === 'replay');
assert.ok(replayArtifact, 'attribution replay artifact missing');
const replay = JSON.parse(fs.readFileSync(path.resolve(
  path.dirname(evidencePath), replayArtifact.path)));
for (const key of ['stateChainSha256', 'frameChainSha256', 'payloadChainSha256']) {
  assert.equal(browser.summaries[0][key], browser.summaries[1][key],
    `${key} differs between browser runs`);
  assert.equal(replay[key], browser.summaries[0][key],
    `${key} differs in private attribution replay`);
}
assert.equal(evidence.report.clockAnomalies, 0,
  'accepted local attribution contains a backward-clock sample');
assert.ok(evidence.report.commitSamples > 0,
  'accepted local attribution contains no commit timing samples');
process.stdout.write(`PASS T12.1-LOCAL-EVIDENCE ${JSON.stringify({
  browserFps: browser.summaries.map(row => row.fps),
  serialFps: evidence.report.metrics.effectiveFps.value,
  commitSamples: evidence.report.commitSamples,
  chains: Object.fromEntries(['stateChainSha256', 'frameChainSha256',
    'payloadChainSha256'].map(key => [key, replay[key]]))
})}\n`);
