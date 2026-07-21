import assert from 'node:assert/strict';
import crypto from 'node:crypto';
import fs from 'node:fs';
import path from 'node:path';

export const CONTRACT = Object.freeze({
  task: 'T12.2', resolution: [320, 200], frames: 300, warmFrames: 30, measuredFrames: 270,
  replaySha256: '1ad47bc8e2a5b7518d68b937a333492d66d7d539f827980086d4b4fdad327fe3',
  t12_1ManifestSha256: '506b390a432aafdc6950996fc233cb618891f9456176cde344f0098289b306b4',
  publicSchemaSha256: 'e1f9c194869f0aa0652ca868f2c74a3e466aee77229b775e8c776674d2823291',
  goldenManifestSha256: '031c59e530fe365cc08bd65f6a325435107ffc8516b027c2e9c1dd9ef6b1a31f',
  changeClasses: ['index', 'join-order', 'precomputed-static-relation', 'partitioning', 'aggregation-shape', 'codec', 'transport', 'client'],
  stages: ['database', 'ords', 'payload', 'decode-blit', 'r1', 'r2'],
  environments: ['local', 'cloud'],
  attemptArtifactKinds: ['samples', 'diff', 'correctness', 'mutations', 'report']
});

const forbiddenFragments = ['authorization', 'bearer ', 'password', 'passwd', 'secret', 'token', 'jdbc:', 'oraclecloud.com', 'amazonaws.com', 'ordsbaseurl', 'wallet', 'private_key'];
const forbiddenKey = /(credential|password|authorization|access.?key|session.?id|bind.?value|endpoint|url)$/i;
const hex = value => typeof value === 'string' && /^[0-9a-f]{64}$/.test(value);
const finite = value => Number.isFinite(value) && value >= 0;
const evidenceArtifactPath = value => typeof value === 'string' && /^artifacts\/performance\/t12\.2\/(raw|report)\/[a-z0-9._\/-]+$/.test(value) && !value.includes('..') && !value.includes('//');

export const sha256 = value => crypto.createHash('sha256').update(value).digest('hex');
export const canonicalJson = value => JSON.stringify(value);

export function scanRedacted(value, location = 'evidence') {
  if (typeof value === 'string') {
    const lower = value.toLowerCase();
    for (const fragment of forbiddenFragments) assert.ok(!lower.includes(fragment), `${location}: forbidden ${fragment}`);
  } else if (Array.isArray(value)) {
    value.forEach((item, index) => scanRedacted(item, `${location}[${index}]`));
  } else if (value && typeof value === 'object') {
    for (const [key, item] of Object.entries(value)) {
      assert.ok(!forbiddenKey.test(key), `${location}.${key}: secret-bearing key`);
      scanRedacted(item, `${location}.${key}`);
    }
  }
}

export function percentile(values, fraction) {
  assert.ok(values.length > 0, 'percentile population is empty');
  return values.slice().sort((a, b) => a - b)[Math.ceil(fraction * values.length) - 1];
}

export function validateSamples(samples, label = 'samples') {
  assert.equal(samples.length, CONTRACT.frames, `${label} frames`);
  samples.forEach((sample, frame) => {
    assert.equal(sample.frame, frame, `${label} frame sequence`);
    assert.equal(sample.phase, frame < CONTRACT.warmFrames ? 'warm' : 'measured', `${label} frame ${frame} phase`);
    assert.equal(sample.externalClock, true, `${label} frame ${frame} external clock`);
    for (const metric of ['endToEndMs', 'databaseMs', 'ordsMs', 'payloadMs', 'decodeBlitMs', 'r1Ms', 'r2Ms', 'payloadBytes']) {
      assert.ok(finite(sample[metric]), `${label} frame ${frame} ${metric}`);
    }
    assert.ok(hex(sample.payloadSha256), `${label} frame ${frame} payload digest`);
  });
  scanRedacted(samples, label);
  return samples;
}

export function statistics(samples) {
  validateSamples(samples);
  const measured = samples.slice(CONTRACT.warmFrames);
  const values = key => measured.map(sample => sample[key]);
  const mean = values('endToEndMs').reduce((sum, value) => sum + value, 0) / CONTRACT.measuredFrames;
  return {
    endToEndMs: {p50: percentile(values('endToEndMs'), .5), p95: percentile(values('endToEndMs'), .95)},
    effectiveFps: 1000 / mean,
    stageMedians: {
      database: percentile(values('databaseMs'), .5), ords: percentile(values('ordsMs'), .5),
      payload: percentile(values('payloadMs'), .5), 'decode-blit': percentile(values('decodeBlitMs'), .5),
      r1: percentile(values('r1Ms'), .5), r2: percentile(values('r2Ms'), .5)
    }
  };
}

export const dominantStage = stats => Object.entries(stats.stageMedians).sort((left, right) => right[1] - left[1])[0][0];
export const improvementPercent = (before, after) => (before - after) / before * 100;

function assertTestReport(report, kind) {
  if (kind === 'correctness') {
    assert.equal(report.passed, true); assert.equal(report.skipped, false);
    assert.ok(Number.isInteger(report.expectedAssertions) && report.expectedAssertions > 0);
    assert.equal(report.assertions, report.expectedAssertions);
  } else {
    assert.equal(report.passed, true); assert.equal(report.skipped, false);
    assert.ok(Number.isInteger(report.required) && report.required > 0);
    assert.equal(report.killed, report.required); assert.deepEqual(report.survivors, []);
  }
  assert.ok(hex(report.machineReportSha256), `${kind} machine report digest`);
  return report;
}

const reportPayload = report => {
  const {machineReportSha256, ...payload} = report;
  return payload;
};

function chainEntry(attempt, previous) {
  const entry = {attempt: attempt.id, startedUtc: attempt.startedUtc, endedUtc: attempt.endedUtc,
    sourceBeforeSha256: attempt.sourceBeforeSha256, sourceAfterSha256: attempt.sourceAfterSha256,
    diffSha256: attempt.diffSha256, outcome: attempt.outcome, decision: attempt.decision,
    prevEntrySha256: previous};
  return {...entry, entrySha256: sha256(JSON.stringify(entry))};
}

function validateArtifact(artifact) {
  assert.ok(CONTRACT.attemptArtifactKinds.includes(artifact.kind) || ['journal', 'report', 'samples'].includes(artifact.kind));
  assert.ok(evidenceArtifactPath(artifact.path), `unsafe artifact path ${artifact.path}`);
  assert.ok(hex(artifact.sha256)); assert.ok(Number.isInteger(artifact.bytes) && artifact.bytes > 0);
  assert.ok(Number.isInteger(artifact.records) && artifact.records > 0); assert.equal(artifact.atomic, true);
}

export function validateEvidence(evidence, evidencePath, {readArtifacts = true} = {}) {
  assert.equal(evidence.schema, 1); assert.equal(evidence.task, CONTRACT.task); assert.equal(evidence.status, 'COMPLETE');
  assert.equal(evidence.synthetic, false); assert.deepEqual(evidence.resolution, CONTRACT.resolution);
  assert.deepEqual(evidence.replay, {frames: 300, warmFrames: 30, measuredFrames: 270, sha256: CONTRACT.replaySha256});
  assert.equal(evidence.capture.owner, 'independent evaluator'); assert.equal(evidence.capture.clock, 'external monotonic');
  assert.equal(evidence.capture.atomicWrite, true); assert.ok(Date.parse(evidence.capture.endedUtc) > Date.parse(evidence.capture.startedUtc));
  assert.equal(evidence.baseline.pinnedManifestSha256, CONTRACT.t12_1ManifestSha256);
  assert.equal(evidence.baseline.publicSchemaSha256, CONTRACT.publicSchemaSha256);
  assert.equal(evidence.baseline.goldenManifestSha256, CONTRACT.goldenManifestSha256);
  assert.equal(evidence.baseline.replaySha256, CONTRACT.replaySha256); assert.ok(hex(evidence.baseline.selectedRevisionSha256));
  let bestStats = statistics(evidence.baseline.samples); assert.deepEqual(evidence.baseline.statistics, bestStats);
  let bestP50 = bestStats.endToEndMs.p50, bestRevision = evidence.baseline.selectedRevisionSha256;
  let previous = '0'.repeat(64); const diffs = new Set(), fingerprints = new Set(); let firstStopIndex = -1;
  assert.ok(evidence.attempts.length >= 2); assert.equal(evidence.journal.length, evidence.attempts.length);
  evidence.attempts.forEach((attempt, index) => {
    assert.equal(attempt.id, index + 1); assert.ok(Date.parse(attempt.endedUtc) > Date.parse(attempt.startedUtc));
    assert.ok(CONTRACT.changeClasses.includes(attempt.changeClass)); assert.ok(attempt.changeFingerprint.length > 8);
    assert.ok(!fingerprints.has(attempt.changeFingerprint), 'duplicate change fingerprint'); fingerprints.add(attempt.changeFingerprint);
    assert.equal(attempt.sourceBeforeSha256, bestRevision); assert.ok(hex(attempt.sourceAfterSha256));
    assert.ok(attempt.diffNonempty && hex(attempt.diffSha256) && !diffs.has(attempt.diffSha256), 'empty or repeated diff'); diffs.add(attempt.diffSha256);
    assert.equal(attempt.targetBottleneck, dominantStage(bestStats)); assert.equal(attempt.profileSourceRevisionSha256, bestRevision);
    assert.deepEqual({approved: attempt.humanReview.approved, targetedMeasuredBottleneck: attempt.humanReview.targetedMeasuredBottleneck, ineffectiveWorkChosenToStop: attempt.humanReview.ineffectiveWorkChosenToStop}, {approved: true, targetedMeasuredBottleneck: true, ineffectiveWorkChosenToStop: false});
    assert.ok(attempt.humanReview.rationale.length > 80); assert.ok(Date.parse(attempt.humanReview.reviewedUtc) >= Date.parse(attempt.endedUtc));
    const result = statistics(attempt.samples); assert.deepEqual(attempt.statistics, result); assert.equal(attempt.bestBeforeP50, bestP50);
    const improvement = improvementPercent(bestP50, result.endToEndMs.p50); assert.ok(Math.abs(improvement - attempt.improvementPercent) < 1e-9);
    assert.equal(attempt.outcome, improvement < 0 ? 'REGRESSION' : improvement < 5 ? 'SUB_FIVE_PERCENT' : 'IMPROVEMENT');
    assert.equal(attempt.decision, result.endToEndMs.p50 < bestP50 ? 'ACCEPTED' : 'ROLLED_BACK');
    assert.equal(attempt.publicSchemaSha256, CONTRACT.publicSchemaSha256); assert.equal(attempt.goldenManifestSha256, CONTRACT.goldenManifestSha256);
    assertTestReport(attempt.correctness, 'correctness'); assertTestReport(attempt.mutations, 'mutations');
    assert.deepEqual(attempt.artifacts.map(item => item.kind).sort(), CONTRACT.attemptArtifactKinds.slice().sort()); attempt.artifacts.forEach(validateArtifact);
    const byKind = Object.fromEntries(attempt.artifacts.map(item => [item.kind, item]));
    assert.equal(byKind.samples.sha256, sha256(JSON.stringify(attempt.samples))); assert.equal(byKind.diff.sha256, attempt.diffSha256);
    assert.equal(byKind.correctness.sha256, attempt.correctness.machineReportSha256); assert.equal(byKind.mutations.sha256, attempt.mutations.machineReportSha256);
    assert.equal(byKind.report.sha256, sha256(JSON.stringify(attempt.statistics)));
    const entry = chainEntry(attempt, previous); assert.deepEqual(evidence.journal[index], entry); previous = entry.entrySha256;
    if (attempt.decision === 'ACCEPTED') { bestP50 = result.endToEndMs.p50; bestStats = result; bestRevision = attempt.sourceAfterSha256; }
    if (index >= 1) {
      const prior = evidence.attempts[index - 1];
      if (prior.improvementPercent < 5 && attempt.improvementPercent < 5 && prior.changeClass !== attempt.changeClass && prior.changeFingerprint !== attempt.changeFingerprint && firstStopIndex < 0) firstStopIndex = index;
    }
  });
  assert.equal(firstStopIndex, evidence.attempts.length - 1, 'journal did not stop at the first qualifying pair');
  const last = evidence.attempts.slice(-2); assert.deepEqual(evidence.report.stopAttemptIds, last.map(item => item.id));
  assert.equal(evidence.report.stopRule, 'TWO_CONSECUTIVE_DISTINCT_ATTEMPTS_BELOW_FIVE_PERCENT');
  assert.deepEqual(evidence.finalVerification.map(item => item.environment).sort(), CONTRACT.environments.slice().sort());
  for (const verification of evidence.finalVerification) {
    assert.equal(verification.selectedRevisionSha256, bestRevision); assert.equal(verification.replaySha256, CONTRACT.replaySha256);
    assert.equal(verification.publicSchemaSha256, CONTRACT.publicSchemaSha256); assert.equal(verification.goldenManifestSha256, CONTRACT.goldenManifestSha256);
    const result = statistics(verification.samples); assert.deepEqual(verification.statistics, result); validateArtifact(verification.artifact);
    assert.equal(verification.artifact.kind, 'samples'); assert.equal(verification.artifact.sha256, sha256(JSON.stringify(verification.samples)));
    assert.deepEqual(evidence.report.highestVerified[verification.environment], {fps: result.effectiveFps, p50Ms: result.endToEndMs.p50, p95Ms: result.endToEndMs.p95, observation: 'DIRECT_MEASUREMENT', artifactSha256: verification.artifact.sha256});
  }
  assert.equal(evidence.report.selectedRevisionSha256, bestRevision); assert.equal(evidence.report.attemptCount, evidence.attempts.length);
  assert.equal(evidence.report.marketingEstimate, false); assert.equal(evidence.report.portableThresholdClaim, false); assert.equal(evidence.report.noMinimumThreshold, true);
  assert.deepEqual(evidence.artifacts.map(item => item.kind).sort(), ['journal', 'report']); evidence.artifacts.forEach(validateArtifact);
  const rootArtifacts = Object.fromEntries(evidence.artifacts.map(item => [item.kind, item]));
  assert.equal(rootArtifacts.journal.sha256, sha256(JSON.stringify(evidence.journal))); assert.equal(rootArtifacts.report.sha256, sha256(JSON.stringify(evidence.report)));
  const all = [...evidence.artifacts, ...evidence.attempts.flatMap(item => item.artifacts), ...evidence.finalVerification.map(item => item.artifact)];
  assert.equal(new Set(all.map(item => item.path)).size, all.length, 'duplicate artifact path');
  assert.equal(evidence.provenance.t12_1ManifestSha256, CONTRACT.t12_1ManifestSha256); assert.ok(hex(evidence.provenance.inputSha256));
  assert.equal(evidence.provenance.journalSha256, rootArtifacts.journal.sha256); assert.equal(evidence.provenance.reportSha256, rootArtifacts.report.sha256);
  assert.equal(evidence.provenance.redactionPassed, true);
  scanRedacted(evidence);
  if (readArtifacts) {
    const root = path.dirname(path.resolve(evidencePath));
    const bodies = {};
    for (const artifact of all) {
      const file = path.resolve(root, artifact.path); assert.ok(file.startsWith(`${root}${path.sep}`), 'artifact escapes evidence root');
      const body = fs.readFileSync(file); bodies[artifact.path] = body;
      assert.equal(body.byteLength, artifact.bytes, `${artifact.path} bytes`); assert.equal(sha256(body), artifact.sha256, `${artifact.path} hash`); scanRedacted(body.toString('utf8'), artifact.path);
    }
    const json = artifact => JSON.parse(bodies[artifact.path]);
    assert.deepEqual(json(rootArtifacts.journal), evidence.journal); assert.deepEqual(json(rootArtifacts.report), evidence.report);
    for (const attempt of evidence.attempts) {
      const byKind = Object.fromEntries(attempt.artifacts.map(item => [item.kind, item]));
      assert.deepEqual(json(byKind.samples), attempt.samples); assert.deepEqual(json(byKind.correctness), reportPayload(attempt.correctness));
      assert.deepEqual(json(byKind.mutations), reportPayload(attempt.mutations)); assert.deepEqual(json(byKind.report), attempt.statistics);
    }
    for (const verification of evidence.finalVerification) assert.deepEqual(json(verification.artifact), verification.samples);
  }
  return evidence;
}

export function atomicWrite(file, body) {
  fs.mkdirSync(path.dirname(file), {recursive: true, mode: 0o700});
  const temporary = `${file}.tmp-${process.pid}-${crypto.randomBytes(8).toString('hex')}`;
  const descriptor = fs.openSync(temporary, 'wx', 0o600);
  try { fs.writeFileSync(descriptor, body); fs.fsyncSync(descriptor); } finally { fs.closeSync(descriptor); }
  fs.renameSync(temporary, file);
}
