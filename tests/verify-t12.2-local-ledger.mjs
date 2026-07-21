#!/usr/bin/env node
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import {
  atomicWrite, readAndVerifyArtifacts, scanRedacted, validateEvidenceShape
} from '../scripts/performance/t12.1-evidence.mjs';

const root = path.resolve(import.meta.dirname, '..');
const paths = {
  baseline: '.artifacts/t12.1/evidence.json',
  selected: '.artifacts/t12.2/attempt-1-transport-2ms/evidence.json',
  transportRegression: '.artifacts/t12.2/attempt-2-transport-1ms/evidence.json',
  indexRegression: '.artifacts/t12.2/attempt-3-index-poll/evidence.json',
  browser: '.artifacts/t12.2/attempt-1-transport-2ms/browser.json'
};
const evidence = Object.fromEntries(Object.entries(paths).filter(([key]) => key !== 'browser')
  .map(([key, relative]) => {
    const file = path.join(root, relative);
    const value = validateEvidenceShape(JSON.parse(fs.readFileSync(file)));
    readAndVerifyArtifacts(value, file);
    return [key, {file, value}];
  }));
const replay = ({file, value}) => {
  const artifact = value.rawArtifacts.find(row => row.kind === 'replay');
  assert.ok(artifact); return JSON.parse(fs.readFileSync(path.resolve(
    path.dirname(file), artifact.path)));
};
const chainKeys = ['stateChainSha256', 'frameChainSha256', 'payloadChainSha256'];
const selectedReplay = replay(evidence.selected);
for (const entry of Object.values(evidence)) {
  const candidate = replay(entry);
  for (const key of chainKeys) assert.equal(candidate[key], selectedReplay[key],
    `${key} drifted during optimization`);
}
const browser = JSON.parse(fs.readFileSync(path.join(root, paths.browser)));
assert.equal(browser.identicalChains, true); assert.equal(browser.summaries.length, 2);
for (const summary of browser.summaries) {
  assert.ok(summary.fps >= 30, `selected browser run ${summary.run} below 30 FPS`);
  for (const key of chainKeys) assert.equal(summary[key], selectedReplay[key],
    `selected browser ${key} drift`);
}
const p50 = key => evidence[key].value.report.metrics.endToEndMs.p50;
const improvement = (before, after) => (before - after) / before * 100;
const attempts = [
  {id: 1, changeClass: 'transport', fingerprint: 'poll-ready-quantum-5ms-to-2ms',
    beforeP50Ms: p50('baseline'), afterP50Ms: p50('selected'),
    p95Ms: evidence.selected.value.report.metrics.endToEndMs.p95,
    effectiveFps: evidence.selected.value.report.metrics.effectiveFps.value,
    clockAnomalies: evidence.selected.value.report.clockAnomalies,
    decision: 'ACCEPTED'},
  {id: 2, changeClass: 'transport', fingerprint: 'poll-ready-quantum-2ms-to-1ms',
    beforeP50Ms: p50('selected'), afterP50Ms: p50('transportRegression'),
    p95Ms: evidence.transportRegression.value.report.metrics.endToEndMs.p95,
    effectiveFps: evidence.transportRegression.value.report.metrics.effectiveFps.value,
    clockAnomalies: evidence.transportRegression.value.report.clockAnomalies,
    decision: 'ROLLED_BACK'},
  {id: 3, changeClass: 'index', fingerprint: 'redundant-request-status-poll-index',
    beforeP50Ms: p50('selected'), afterP50Ms: p50('indexRegression'),
    p95Ms: evidence.indexRegression.value.report.metrics.endToEndMs.p95,
    effectiveFps: evidence.indexRegression.value.report.metrics.effectiveFps.value,
    clockAnomalies: evidence.indexRegression.value.report.clockAnomalies,
    decision: 'ROLLED_BACK'}
].map(attempt => ({...attempt,
  improvementPercent: improvement(attempt.beforeP50Ms, attempt.afterP50Ms)}));
assert.ok(attempts[0].improvementPercent >= 5); assert.equal(attempts[0].decision, 'ACCEPTED');
assert.ok(attempts[1].improvementPercent < 5); assert.ok(attempts[2].improvementPercent < 5);
assert.notEqual(attempts[1].changeClass, attempts[2].changeClass);
assert.equal(attempts[1].decision, 'ROLLED_BACK'); assert.equal(attempts[2].decision, 'ROLLED_BACK');
const apiSource = fs.readFileSync(path.join(root, 'sql/rest/010_doom_api.sql'), 'utf8');
assert.match(apiSource, /readiness.not the sleep floor[\s\S]{0,120}dbms_session\.sleep\(\.002\)/,
  'selected 2 ms poll quantum is not in production source');
assert.doesNotMatch(apiSource, /doom_worker_request_t122_ix/i,
  'rejected temporary index leaked into production source');
const ledger = {schema: 1, task: 'T12.2-LOCAL', status: 'COMPLETE',
  replaySha256: evidence.selected.value.replay.sha256, attempts,
  stopRule: {kind: 'TWO_CONSECUTIVE_DISTINCT_ATTEMPTS_BELOW_FIVE_PERCENT',
    attemptIds: [2, 3]}, selected: {attemptId: 1, pollQuantumMs: 2,
    browserFps: browser.summaries.map(row => row.fps),
    chainSha256: Object.fromEntries(chainKeys.map(key => [key, selectedReplay[key]]))},
  cloudPublicationPendingP11: true};
scanRedacted(ledger, 'T12.2 local ledger');
const destination = path.join(root, '.artifacts/t12.2/local-ledger.json');
atomicWrite(destination, `${JSON.stringify(ledger)}\n`);
process.stdout.write(`PASS T12.2-LOCAL-LEDGER ${JSON.stringify(ledger)}\n`);
