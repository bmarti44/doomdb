import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import {execFileSync} from 'node:child_process';
import {
  CONTRACT, buildReport, canonicalJson, readAndVerifyArtifacts, scanRedacted,
  sha256, validateDatabaseObservations, validateEvidenceShape, validateReplay
} from '../scripts/performance/t12.1-evidence.mjs';
import {runCollector} from '../scripts/performance/t12.1-collector.mjs';

const replay = {
  schema: 1,
  task: 'T12.1',
  identitySha256: CONTRACT.replaySha256,
  resolution: [320, 200],
  frames: Array.from({length: 300}, (_, frame) => ({
    frame,
    pose: CONTRACT.poses[frame % 4],
    command: CONTRACT.commands[frame % 5],
    request: {seq: frame, forward: frame % 2}
  }))
};
assert.equal(validateReplay(replay), replay);

const shapes = [];
for (const [familyIndex, family] of CONTRACT.families.entries()) {
  for (const pose of CONTRACT.poses) for (const command of CONTRACT.commands) {
    shapes.push({family, pose, command, normalizedShape: `${family.toUpperCase()}(:B1,:B2)`, forceMatchingSignature: String(9000 + familyIndex), bindCount: 2});
  }
}
const observations = {
  families: CONTRACT.families.slice(),
  plans: CONTRACT.families.map((family, index) => ({
    family, format: 'ALLSTATS LAST', planHashValue: 100 + index,
    executionsBefore: 0, executionsAfter: 90,
    operations: [{id: 0, operation: 'SELECT STATEMENT', starts: 90, aRows: 90, elapsedUs: 1000}]
  })),
  vsql: CONTRACT.families.map((family, index) => ({
    family, sqlIdSha256: sha256(`sql-id-${index}`), forceMatchingSignature: String(9000 + index),
    normalizedShape: `${family.toUpperCase()}(:B1,:B2)`, parseCallsBefore: 1,
    parseCallsAfter: 2, executionsBefore: 0, executionsAfter: 90, versionCount: 1
  })),
  shapes,
  stageSamples: Array.from({length: 300}, (_, frame) => ({frame, databaseMs: 4, ordsMs: 1, r1Ms: 1, r2Ms: 2}))
};
assert.equal(validateDatabaseObservations(observations), observations);

const samples = replay.frames.map(item => ({
  frame: item.frame,
  phase: item.frame < 30 ? 'warm' : 'measured',
  pose: item.pose,
  command: item.command,
  externalClock: true,
  endToEndMs: 10 + item.frame % 3,
  databaseMs: 4,
  ordsMs: 1,
  decodeBlitMs: 2,
  r1Ms: 1,
  r2Ms: 2,
  payloadBytes: 8000 + item.frame,
  payloadSha256: sha256(`payload-${item.frame}`),
  responseBodyKeys: ['audio', 'cols', 'frame_sha', 'h', 'tic', 'v', 'w']
}));

const temporary = fs.mkdtempSync(path.join(os.tmpdir(), 'doomdb-t121-unit-'));
try {
  const rawValues = {samples, plans: observations.plans, vsql: observations.vsql,
    payloads: samples.map(({frame, payloadBytes, payloadSha256}) => ({frame, payloadBytes, payloadSha256})),
    replay: {identitySha256: CONTRACT.replaySha256}};
  const rawArtifacts = [];
  for (const kind of CONTRACT.rawKinds) {
    const relative = `artifacts/performance/t12.1/raw/${kind}.json`;
    const body = canonicalJson(rawValues[kind]);
    const destination = path.join(temporary, relative);
    fs.mkdirSync(path.dirname(destination), {recursive: true});
    fs.writeFileSync(destination, body);
    rawArtifacts.push({kind, path: relative, sha256: sha256(body), bytes: Buffer.byteLength(body), records: Array.isArray(rawValues[kind]) ? rawValues[kind].length : 1});
  }
  const report = buildReport(samples, observations.vsql, rawArtifacts);
  const reportBody = JSON.stringify(report);
  const reportPath = 'artifacts/performance/t12.1/report/baseline.json';
  fs.mkdirSync(path.dirname(path.join(temporary, reportPath)), {recursive: true});
  fs.writeFileSync(path.join(temporary, reportPath), reportBody);
  const evidence = {
    schema: 1, task: 'T12.1', status: 'COMPLETE', synthetic: false, resolution: [320, 200],
    replay: {frames: 300, warmFrames: 30, measuredFrames: 270, sha256: CONTRACT.replaySha256, commandsSha256: sha256(JSON.stringify(samples.map(item => item.command)))},
    capture: {owner: 'independent evaluator', clock: 'external monotonic', startedUtc: '2026-07-15T12:00:00Z', endedUtc: '2026-07-15T12:01:00Z', atomicWrite: true},
    samples, plans: observations.plans, vsql: observations.vsql, shapes,
    rawArtifacts,
    reportArtifact: {path: reportPath, sha256: sha256(reportBody), bytes: Buffer.byteLength(reportBody)},
    report
  };
  const evidencePath = path.join(temporary, 'evidence.json');
  fs.writeFileSync(evidencePath, canonicalJson(evidence));
  validateEvidenceShape(evidence);
  readAndVerifyArtifacts(evidence, evidencePath);
  assert.match(execFileSync(process.execPath, [path.resolve('scripts/verify-performance-baseline.mjs'), evidencePath], {encoding: 'utf8'}), /PASS T12\.1-PRODUCTION-EVIDENCE/);
  assert.match(execFileSync(process.execPath, [path.resolve('evaluator/t12.1/validate-evidence.mjs'), evidencePath, temporary], {encoding: 'utf8'}), /PASS T12\.1-LIVE-EVIDENCE/);
  const drift = structuredClone(observations);
  drift.shapes[0].normalizedShape = 'DRIFT(:B1)';
  assert.throws(() => validateDatabaseObservations(drift), /shape drift/);
  const leaked = structuredClone(evidence);
  leaked.samples[0].responseBodyKeys.push('databaseMs');
  assert.throws(() => validateEvidenceShape(leaked), /timer leak/);
  assert.throws(() => scanRedacted({nested: {password: 'x'}}), /secret-bearing key/);
  const damaged = structuredClone(evidence);
  damaged.rawArtifacts[0].sha256 = '0'.repeat(64);
  assert.throws(() => readAndVerifyArtifacts(damaged, evidencePath), /digest/);
} finally {
  fs.rmSync(temporary, {recursive: true, force: true});
}

const collectorEcho = await runCollector([
  process.execPath, '-e',
  "let s='';process.stdin.on('data',c=>s+=c);process.stdin.on('end',()=>process.stdout.write(JSON.stringify({schema:JSON.parse(s).schema})))"
], {schema: 1});
assert.deepEqual(collectorEcho, {schema: 1});
assert.rejects(() => runCollector(['collector', '--password=x'], {}), /credentials/);

process.stdout.write('PASS T12.1-PRODUCTION-UNITS (replay, observations, artifacts, redaction, collector protocol)\n');
