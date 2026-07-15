import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import {execFileSync} from 'node:child_process';
import {makeEvidence, makeFixtureArtifactBodies} from '../evaluator/t12.2/reference.mjs';
import fixtures from '../evaluator/t12.2/fixtures.json' with {type: 'json'};
import {
  CONTRACT, atomicWrite, dominantStage, improvementPercent, percentile, sha256,
  statistics, validateEvidence, validateSamples
} from '../scripts/performance/t12.2-ledger.mjs';

assert.deepEqual(CONTRACT.resolution, [320, 200]);
assert.equal(CONTRACT.frames, 300); assert.equal(CONTRACT.warmFrames, 30); assert.equal(CONTRACT.measuredFrames, 270);
assert.equal(percentile([9, 1, 4, 2], .5), 2);
assert.equal(improvementPercent(20, 19), 5);

const evidence = makeEvidence(fixtures);
const rootArtifacts = Object.fromEntries(evidence.artifacts.map(item => [item.kind, item]));
evidence.provenance = {t12_1ManifestSha256: CONTRACT.t12_1ManifestSha256, inputSha256: sha256('capture plan'),
  journalSha256: rootArtifacts.journal.sha256, reportSha256: rootArtifacts.report.sha256, redactionPassed: true};
assert.equal(validateEvidence(evidence, 'unused.json', {readArtifacts: false}), evidence);
assert.equal(validateSamples(evidence.baseline.samples), evidence.baseline.samples);
const baselineStats = statistics(evidence.baseline.samples);
assert.equal(dominantStage(baselineStats), 'database');
assert.equal(baselineStats.endToEndMs.p50, evidence.baseline.statistics.endToEndMs.p50);

const mutate = (change, pattern) => {
  const copy = structuredClone(evidence); change(copy); assert.throws(() => validateEvidence(copy, 'unused.json', {readArtifacts: false}), pattern);
};
mutate(copy => { copy.attempts[0].targetBottleneck = 'ords'; }, /bottleneck|Expected values/);
mutate(copy => { copy.attempts[0].publicSchemaSha256 = '0'.repeat(64); }, /Expected values/);
mutate(copy => { copy.attempts[1].correctness.skipped = true; }, /Expected values/);
mutate(copy => { copy.attempts[2].mutations.survivors = ['M1']; }, /Expected values/);
mutate(copy => { copy.attempts[2].humanReview.ineffectiveWorkChosenToStop = true; }, /Expected values/);
mutate(copy => { copy.journal[1].prevEntrySha256 = '0'.repeat(64); }, /Expected values/);
mutate(copy => { copy.finalVerification[0].samples.pop(); }, /frames/);
mutate(copy => { copy.report.highestVerified.local.observation = 'ESTIMATE'; }, /Expected values/);
mutate(copy => { copy.provenance.inputSha256 = 'bad'; }, /falsy|inputSha256/);
mutate(copy => { copy.notes = 'bearer abc'; }, /forbidden/);

const earlyStop = structuredClone(evidence);
earlyStop.attempts[0].improvementPercent = 1;
assert.throws(() => validateEvidence(earlyStop, 'unused.json', {readArtifacts: false}));

const temporary = fs.mkdtempSync(path.join(os.tmpdir(), 'doomdb-t122-unit-'));
try {
  const file = path.join(temporary, 'nested', 'atomic.json'); atomicWrite(file, '{"ok":true}');
  assert.equal(fs.readFileSync(file, 'utf8'), '{"ok":true}');
  assert.equal(fs.readdirSync(path.dirname(file)).some(name => name.includes('.tmp-')), false);
  const bodies = makeFixtureArtifactBodies(evidence);
  for (const [relative, body] of Object.entries(bodies)) {
    const artifactFile = path.join(temporary, relative); fs.mkdirSync(path.dirname(artifactFile), {recursive: true}); fs.writeFileSync(artifactFile, body);
  }
  const evidencePath = path.join(temporary, 'evidence.json'); fs.writeFileSync(evidencePath, `${JSON.stringify(evidence)}\n`);
  assert.equal(validateEvidence(evidence, evidencePath), evidence);
  assert.match(execFileSync(process.execPath, ['scripts/run-performance-optimization.mjs', '--verify-only', evidencePath], {encoding: 'utf8'}), /PASS T12\.2-PRODUCTION-EVIDENCE/);
  assert.match(execFileSync(process.execPath, ['evaluator/t12.2/validate-evidence.mjs', evidencePath, temporary], {encoding: 'utf8'}), /PASS T12\.2-LIVE-EVIDENCE/);
  const tamperedReport = JSON.parse(fs.readFileSync(path.join(temporary, evidence.attempts[0].artifacts.find(item => item.kind === 'correctness').path), 'utf8'));
  tamperedReport.assertions -= 1;
  fs.writeFileSync(path.join(temporary, evidence.attempts[0].artifacts.find(item => item.kind === 'correctness').path), JSON.stringify(tamperedReport));
  assert.throws(() => validateEvidence(evidence, evidencePath), /bytes|hash/);
} finally { fs.rmSync(temporary, {recursive: true, force: true}); }

assert.match(execFileSync(process.execPath, ['evaluator/t12.2/source-audit.mjs'], {encoding: 'utf8', env: {...process.env, T122_REQUIRE_PRODUCTION: '1'}}), /PASS T12\.2-SOURCE-AUDIT/);
assert.throws(() => execFileSync(process.execPath, ['scripts/run-performance-optimization.mjs', '--publish', 'missing.json', 'out.json'], {stdio: 'pipe'}), /Command failed/);
process.stdout.write('PASS T12.2-PRODUCTION-UNITS (ledger, profiling, stop rule, invariance, provenance, redaction)\n');
