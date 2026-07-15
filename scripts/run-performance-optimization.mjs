#!/usr/bin/env node
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import {
  CONTRACT, atomicWrite, canonicalJson, dominantStage, improvementPercent, scanRedacted,
  sha256, statistics, validateEvidence, validateSamples
} from './performance/t12.2-ledger.mjs';
import {readAndVerifyArtifacts, validateEvidenceShape as validateBaseline} from './performance/t12.1-evidence.mjs';

const usage = 'usage: run-performance-optimization.mjs <evidence.json> | --verify-only <evidence.json> | --publish <capture-plan.json> <evidence.json>';
const hex = value => typeof value === 'string' && /^[0-9a-f]{64}$/.test(value);
// Live samplers own the external monotonic performance.now/hrtime clock; this
// publisher accepts their raw observations and never times production itself.

function resolvedFrom(planFile, file) {
  assert.equal(typeof file, 'string');
  const resolved = path.resolve(path.dirname(planFile), file);
  assert.ok(resolved.startsWith(`${path.dirname(planFile)}${path.sep}`), `input path escapes capture root: ${file}`);
  return resolved;
}

function readJson(planFile, file) { return JSON.parse(fs.readFileSync(resolvedFrom(planFile, file), 'utf8')); }
function readBytes(planFile, file) { return fs.readFileSync(resolvedFrom(planFile, file)); }

function writeArtifact(outputRoot, relative, body, kind, records) {
  const destination = path.resolve(outputRoot, relative);
  assert.ok(destination.startsWith(`${outputRoot}${path.sep}`), 'artifact output escapes evidence root');
  scanRedacted(body.toString('utf8'), relative);
  atomicWrite(destination, body);
  return {kind, path: relative, sha256: sha256(body), bytes: body.byteLength, records, atomic: true};
}

function sampleArtifact(outputRoot, relative, samples) {
  return writeArtifact(outputRoot, relative, Buffer.from(canonicalJson(samples)), 'samples', CONTRACT.frames);
}

function assertCapturePlan(plan) {
  assert.equal(plan.schema, 1); assert.equal(plan.task, CONTRACT.task); assert.equal(plan.synthetic, false);
  assert.deepEqual(plan.resolution, CONTRACT.resolution);
  assert.deepEqual(plan.replay, {frames: 300, warmFrames: 30, measuredFrames: 270, sha256: CONTRACT.replaySha256});
  assert.equal(plan.capture.owner, 'independent evaluator'); assert.equal(plan.capture.clock, 'external monotonic');
  assert.ok(Date.parse(plan.capture.endedUtc) > Date.parse(plan.capture.startedUtc));
  assert.ok(Array.isArray(plan.attempts) && plan.attempts.length >= 2);
  assert.deepEqual(plan.attempts.map(item => item.id), Array.from({length: plan.attempts.length}, (_, index) => index + 1));
  assert.deepEqual(plan.finalVerification.map(item => item.environment).sort(), CONTRACT.environments.slice().sort());
  scanRedacted(plan);
}

function publish(capturePath, evidencePath) {
  assert.equal(process.env.T122_LIVE_CONFIRMED, 'YES', 'live publication requires T122_LIVE_CONFIRMED=YES');
  capturePath = path.resolve(capturePath); evidencePath = path.resolve(evidencePath);
  const captureBytes = fs.readFileSync(capturePath); const plan = JSON.parse(captureBytes); assertCapturePlan(plan);
  const baselinePath = resolvedFrom(capturePath, plan.baseline.evidencePath);
  const baselineEvidence = validateBaseline(JSON.parse(fs.readFileSync(baselinePath, 'utf8')));
  readAndVerifyArtifacts(baselineEvidence, baselinePath);
  assert.equal(plan.baseline.pinnedManifestSha256, CONTRACT.t12_1ManifestSha256); assert.ok(hex(plan.baseline.selectedRevisionSha256));
  assert.equal(baselineEvidence.replay.sha256, CONTRACT.replaySha256);
  // T12.1 proves cursor/replay ancestry; this separately retained external file
  // adds the payload-stage observation required by the T12.2 bottleneck ledger.
  const baselineSamples = readJson(capturePath, plan.baseline.samplesPath); validateSamples(baselineSamples, 'baseline');
  const baselineStats = statistics(baselineSamples);
  const baseline = {pinnedManifestSha256: CONTRACT.t12_1ManifestSha256, publicSchemaSha256: CONTRACT.publicSchemaSha256,
    goldenManifestSha256: CONTRACT.goldenManifestSha256, replaySha256: CONTRACT.replaySha256,
    samples: baselineSamples, statistics: baselineStats, selectedRevisionSha256: plan.baseline.selectedRevisionSha256};
  const outputRoot = path.dirname(evidencePath); let bestP50 = baselineStats.endToEndMs.p50;
  let bestStats = baselineStats, bestRevision = plan.baseline.selectedRevisionSha256;
  const attempts = [];
  for (const descriptor of plan.attempts) {
    assert.ok(CONTRACT.changeClasses.includes(descriptor.changeClass)); assert.ok(hex(descriptor.sourceAfterSha256));
    const samples = readJson(capturePath, descriptor.samplesPath); validateSamples(samples, `attempt ${descriptor.id}`);
    const result = statistics(samples); const improvement = improvementPercent(bestP50, result.endToEndMs.p50);
    const diff = readBytes(capturePath, descriptor.diffPath); assert.ok(diff.byteLength > 0, 'diff is empty'); scanRedacted(diff.toString('utf8'), `attempt ${descriptor.id} diff`);
    const correctnessPayload = readJson(capturePath, descriptor.correctnessPath); const mutationsPayload = readJson(capturePath, descriptor.mutationsPath);
    assert.ok(!Object.hasOwn(correctnessPayload, 'machineReportSha256'), 'correctness payload must not contain its external digest');
    assert.ok(!Object.hasOwn(mutationsPayload, 'machineReportSha256'), 'mutation payload must not contain its external digest');
    const correctnessBody = Buffer.from(canonicalJson(correctnessPayload)); const mutationsBody = Buffer.from(canonicalJson(mutationsPayload));
    const correctness = {...correctnessPayload, machineReportSha256: sha256(correctnessBody)};
    const mutations = {...mutationsPayload, machineReportSha256: sha256(mutationsBody)};
    const prefix = `artifacts/performance/t12.2/raw/attempt-${descriptor.id}`;
    const artifacts = [
      sampleArtifact(outputRoot, `${prefix}/samples.json`, samples),
      writeArtifact(outputRoot, `${prefix}/diff.patch`, diff, 'diff', 1),
      writeArtifact(outputRoot, `${prefix}/correctness.json`, correctnessBody, 'correctness', 1),
      writeArtifact(outputRoot, `${prefix}/mutations.json`, mutationsBody, 'mutations', 1),
      writeArtifact(outputRoot, `${prefix}/report.json`, Buffer.from(canonicalJson(result)), 'report', 1)
    ];
    const attempt = {id: descriptor.id, startedUtc: descriptor.startedUtc, endedUtc: descriptor.endedUtc,
      changeClass: descriptor.changeClass, changeFingerprint: descriptor.changeFingerprint,
      sourceBeforeSha256: bestRevision, sourceAfterSha256: descriptor.sourceAfterSha256,
      diffSha256: artifacts[1].sha256, diffNonempty: true, targetBottleneck: descriptor.targetBottleneck,
      profileSourceRevisionSha256: bestRevision, humanReview: descriptor.humanReview, samples, statistics: result,
      bestBeforeP50: bestP50, improvementPercent: improvement,
      outcome: improvement < 0 ? 'REGRESSION' : improvement < 5 ? 'SUB_FIVE_PERCENT' : 'IMPROVEMENT',
      decision: result.endToEndMs.p50 < bestP50 ? 'ACCEPTED' : 'ROLLED_BACK',
      publicSchemaSha256: CONTRACT.publicSchemaSha256, goldenManifestSha256: CONTRACT.goldenManifestSha256,
      correctness, mutations, artifacts};
    assert.equal(attempt.targetBottleneck, dominantStage(bestStats), `attempt ${descriptor.id} did not target measured bottleneck`);
    attempts.push(attempt);
    if (attempt.decision === 'ACCEPTED') { bestP50 = result.endToEndMs.p50; bestStats = result; bestRevision = descriptor.sourceAfterSha256; }
  }
  let previous = '0'.repeat(64);
  const journal = attempts.map(attempt => {
    const body = {attempt: attempt.id, startedUtc: attempt.startedUtc, endedUtc: attempt.endedUtc,
      sourceBeforeSha256: attempt.sourceBeforeSha256, sourceAfterSha256: attempt.sourceAfterSha256,
      diffSha256: attempt.diffSha256, outcome: attempt.outcome, decision: attempt.decision, prevEntrySha256: previous};
    const entry = {...body, entrySha256: sha256(JSON.stringify(body))}; previous = entry.entrySha256; return entry;
  });
  const finalVerification = plan.finalVerification.map(descriptor => {
    const samples = readJson(capturePath, descriptor.samplesPath); validateSamples(samples, `final ${descriptor.environment}`);
    const result = statistics(samples); const artifact = sampleArtifact(outputRoot, `artifacts/performance/t12.2/raw/final-${descriptor.environment}.json`, samples);
    return {environment: descriptor.environment, selectedRevisionSha256: bestRevision, replaySha256: CONTRACT.replaySha256,
      samples, statistics: result, publicSchemaSha256: CONTRACT.publicSchemaSha256,
      goldenManifestSha256: CONTRACT.goldenManifestSha256, artifact};
  });
  const last = attempts.slice(-2);
  const report = {selectedRevisionSha256: bestRevision, attemptCount: attempts.length, stopAttemptIds: last.map(item => item.id),
    stopRule: 'TWO_CONSECUTIVE_DISTINCT_ATTEMPTS_BELOW_FIVE_PERCENT',
    highestVerified: Object.fromEntries(finalVerification.map(item => [item.environment, {fps: item.statistics.effectiveFps,
      p50Ms: item.statistics.endToEndMs.p50, p95Ms: item.statistics.endToEndMs.p95,
      observation: 'DIRECT_MEASUREMENT', artifactSha256: item.artifact.sha256}])),
    marketingEstimate: false, portableThresholdClaim: false, noMinimumThreshold: true};
  const artifacts = [
    writeArtifact(outputRoot, 'artifacts/performance/t12.2/raw/journal.json', Buffer.from(canonicalJson(journal)), 'journal', journal.length),
    writeArtifact(outputRoot, 'artifacts/performance/t12.2/report/final.json', Buffer.from(canonicalJson(report)), 'report', 1)
  ];
  const evidence = {schema: 1, task: CONTRACT.task, status: 'COMPLETE', synthetic: false, resolution: CONTRACT.resolution,
    replay: plan.replay, capture: {...plan.capture, atomicWrite: true}, baseline, attempts, journal, finalVerification, artifacts, report,
    provenance: {t12_1ManifestSha256: CONTRACT.t12_1ManifestSha256, inputSha256: sha256(captureBytes),
      journalSha256: artifacts[0].sha256, reportSha256: artifacts[1].sha256, redactionPassed: true}};
  validateEvidence(evidence, evidencePath, {readArtifacts: true});
  atomicWrite(evidencePath, `${canonicalJson(evidence)}\n`);
  validateEvidence(evidence, evidencePath, {readArtifacts: true});
  process.stdout.write(`PUBLISHED T12.2 direct evidence (${attempts.length} attempts; local/cloud 300-frame verification)\n`);
}

const arguments_ = process.argv.slice(2);
if (arguments_[0] === '--publish') { assert.equal(arguments_.length, 3, usage); publish(arguments_[1], arguments_[2]); }
else {
  const evidencePath = arguments_[0] === '--verify-only' ? arguments_[1] : arguments_[0];
  assert.equal(arguments_.length, arguments_[0] === '--verify-only' ? 2 : 1, usage);
  validateEvidence(JSON.parse(fs.readFileSync(evidencePath, 'utf8')), evidencePath);
  process.stdout.write('PASS T12.2-PRODUCTION-EVIDENCE (profile ledger, stop rule, direct local/cloud measurements)\n');
}
