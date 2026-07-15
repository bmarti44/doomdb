import assert from 'node:assert/strict';
import crypto from 'node:crypto';
import fs from 'node:fs';
import path from 'node:path';

export const CONTRACT = Object.freeze({
  task: 'T12.1',
  width: 320,
  height: 200,
  frames: 300,
  warmFrames: 30,
  measuredFrames: 270,
  replaySha256: 'c393f8f38a5a89e3bcda88d46e9b62f84e5856ae63bda597b2f67b9cd3856c65',
  poses: ['spawn', 'corridor', 'door', 'combat'],
  commands: ['IDLE', 'MOVE', 'TURN', 'USE', 'FIRE'],
  families: ['step', 'frame', 'asset'],
  rawKinds: ['samples', 'plans', 'vsql', 'payloads', 'replay'],
  metricNames: ['endToEndMs', 'databaseMs', 'ordsMs', 'decodeBlitMs', 'r1Ms', 'r2Ms', 'payloadBytes'],
  forbiddenPayloadKeys: ['r1Ms', 'r2Ms', 'databaseMs', 'ordsMs', 'stageTimers', 'sqlId', 'planHash']
});

const forbiddenText = [
  'authorization', 'bearer ', 'password', 'passwd', 'secret', 'token', 'jdbc:',
  'oraclecloud.com', 'amazonaws.com', 'ordsbaseurl', 'wallet', 'private_key'
];
const forbiddenKey = /(credential|password|authorization|access.?key|session.?id|bind.?value|endpoint|url)$/i;
const hex = value => typeof value === 'string' && /^[0-9a-f]{64}$/.test(value);
const finite = value => Number.isFinite(value) && value >= 0;
const artifactPath = value => typeof value === 'string' &&
  /^artifacts\/performance\/t12\.1\/(raw|report)\/[a-z0-9._-]+$/.test(value) && !value.includes('..');

export const sha256 = value => crypto.createHash('sha256').update(value).digest('hex');
export const canonicalJson = value => `${JSON.stringify(value)}\n`;

export function scanRedacted(value, location = 'evidence') {
  if (typeof value === 'string') {
    const lower = value.toLowerCase();
    for (const fragment of forbiddenText) assert.ok(!lower.includes(fragment), `${location}: forbidden text ${fragment}`);
    return;
  }
  if (Array.isArray(value)) return value.forEach((item, index) => scanRedacted(item, `${location}[${index}]`));
  if (value && typeof value === 'object') {
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

export function validateReplay(replay) {
  assert.equal(replay.schema, 1);
  assert.equal(replay.task, CONTRACT.task);
  assert.equal(replay.identitySha256, CONTRACT.replaySha256, 'unapproved replay identity');
  assert.deepEqual(replay.resolution, [CONTRACT.width, CONTRACT.height]);
  assert.equal(replay.frames.length, CONTRACT.frames);
  replay.frames.forEach((frame, index) => {
    assert.equal(frame.frame, index);
    assert.ok(CONTRACT.poses.includes(frame.pose), `frame ${index} pose`);
    assert.ok(CONTRACT.commands.includes(frame.command), `frame ${index} command class`);
    assert.equal(typeof frame.request, 'object');
    assert.ok(frame.request && !Array.isArray(frame.request));
    scanRedacted(frame, `replay.frames[${index}]`);
  });
  return replay;
}

function validateSamples(samples) {
  assert.equal(samples.length, CONTRACT.frames);
  samples.forEach((sample, index) => {
    assert.equal(sample.frame, index);
    assert.equal(sample.phase, index < CONTRACT.warmFrames ? 'warm' : 'measured');
    assert.ok(CONTRACT.poses.includes(sample.pose));
    assert.ok(CONTRACT.commands.includes(sample.command));
    assert.equal(sample.externalClock, true);
    for (const metric of CONTRACT.metricNames) assert.ok(finite(sample[metric]), `frame ${index} ${metric}`);
    assert.ok(hex(sample.payloadSha256));
    assert.ok(Array.isArray(sample.responseBodyKeys));
    for (const key of CONTRACT.forbiddenPayloadKeys) assert.ok(!sample.responseBodyKeys.includes(key), `payload timer leak ${key}`);
  });
}

export function validateDatabaseObservations(observations) {
  assert.deepEqual(observations.families.slice().sort(), CONTRACT.families.slice().sort());
  assert.equal(observations.plans.length, CONTRACT.families.length);
  assert.equal(observations.vsql.length, CONTRACT.families.length);
  assert.equal(observations.shapes.length, CONTRACT.families.length * CONTRACT.poses.length * CONTRACT.commands.length);
  assert.equal(observations.stageSamples.length, CONTRACT.frames);
  observations.plans.forEach(plan => {
    assert.ok(CONTRACT.families.includes(plan.family));
    assert.equal(plan.format, 'ALLSTATS LAST');
    assert.ok(Number.isInteger(plan.planHashValue));
    assert.ok(plan.executionsAfter > plan.executionsBefore);
    assert.ok(plan.operations.length > 0);
    plan.operations.forEach(operation => {
      assert.ok(Number.isInteger(operation.id));
      assert.equal(typeof operation.operation, 'string');
      assert.ok(Number.isInteger(operation.starts));
      assert.ok(Number.isInteger(operation.aRows));
      assert.ok(finite(operation.elapsedUs));
    });
  });
  observations.vsql.forEach(cursor => {
    assert.ok(CONTRACT.families.includes(cursor.family));
    assert.ok(hex(cursor.sqlIdSha256));
    assert.match(cursor.forceMatchingSignature, /^\d+$/);
    assert.ok(!/select|update|insert|delete/i.test(cursor.normalizedShape), 'raw SQL is forbidden');
    assert.ok(cursor.parseCallsAfter >= cursor.parseCallsBefore);
    assert.ok(cursor.parseCallsAfter - cursor.parseCallsBefore <= 1, `${cursor.family} hard-parse growth`);
    assert.equal(cursor.executionsAfter - cursor.executionsBefore, 90, `${cursor.family} execution coverage`);
    assert.equal(cursor.versionCount, 1, `${cursor.family} child cursor proliferation`);
  });
  for (const family of CONTRACT.families) {
    const shapes = observations.shapes.filter(shape => shape.family === family);
    assert.equal(new Set(shapes.map(shape => shape.normalizedShape)).size, 1, `${family} shape drift`);
    assert.equal(new Set(shapes.map(shape => shape.forceMatchingSignature)).size, 1, `${family} signature drift`);
    assert.equal(new Set(shapes.map(shape => shape.pose)).size, CONTRACT.poses.length);
    assert.equal(new Set(shapes.map(shape => shape.command)).size, CONTRACT.commands.length);
  }
  observations.stageSamples.forEach((sample, frame) => {
    assert.equal(sample.frame, frame);
    for (const metric of ['databaseMs', 'ordsMs', 'r1Ms', 'r2Ms']) assert.ok(finite(sample[metric]), `stage ${frame} ${metric}`);
  });
  scanRedacted(observations, 'database observations');
  return observations;
}

export function buildReport(samples, vsql, rawArtifacts) {
  validateSamples(samples);
  const measured = samples.slice(CONTRACT.warmFrames);
  const metrics = {};
  for (const name of CONTRACT.metricNames) {
    const values = measured.map(sample => sample[name]);
    metrics[name] = {p50: percentile(values, 0.5), p95: percentile(values, 0.95)};
  }
  const meanLatency = measured.reduce((sum, sample) => sum + sample.endToEndMs, 0) / CONTRACT.measuredFrames;
  metrics.effectiveFps = {value: 1000 / meanLatency};
  return {
    measuredFrames: CONTRACT.measuredFrames,
    metrics,
    cursor: {
      parseCallsDelta: vsql.reduce((sum, row) => sum + row.parseCallsAfter - row.parseCallsBefore, 0),
      executionsDelta: vsql.reduce((sum, row) => sum + row.executionsAfter - row.executionsBefore, 0),
      statementFamilies: CONTRACT.families.length
    },
    noMinimumThreshold: true,
    rawManifestSha256: sha256(JSON.stringify(rawArtifacts))
  };
}

export function validateEvidenceShape(evidence) {
  assert.equal(evidence.schema, 1);
  assert.equal(evidence.task, CONTRACT.task);
  assert.equal(evidence.status, 'COMPLETE');
  assert.equal(evidence.synthetic, false);
  assert.deepEqual(evidence.resolution, [CONTRACT.width, CONTRACT.height]);
  assert.deepEqual([evidence.replay.frames, evidence.replay.warmFrames, evidence.replay.measuredFrames], [300, 30, 270]);
  assert.equal(evidence.replay.sha256, CONTRACT.replaySha256);
  assert.ok(hex(evidence.replay.commandsSha256));
  assert.equal(evidence.capture.owner, 'independent evaluator');
  assert.equal(evidence.capture.clock, 'external monotonic');
  assert.equal(evidence.capture.atomicWrite, true);
  assert.ok(Date.parse(evidence.capture.endedUtc) > Date.parse(evidence.capture.startedUtc));
  validateSamples(evidence.samples);
  assert.equal(evidence.plans.length, 3);
  assert.equal(evidence.vsql.length, 3);
  assert.equal(evidence.shapes.length, 60);
  assert.deepEqual(evidence.rawArtifacts.map(item => item.kind).sort(), CONTRACT.rawKinds.slice().sort());
  for (const item of [...evidence.rawArtifacts, evidence.reportArtifact]) {
    assert.ok(artifactPath(item.path));
    assert.ok(hex(item.sha256));
    assert.ok(Number.isInteger(item.bytes) && item.bytes > 0);
  }
  scanRedacted(evidence);
  return evidence;
}

export function atomicWrite(file, body) {
  fs.mkdirSync(path.dirname(file), {recursive: true, mode: 0o700});
  const temporary = `${file}.tmp-${process.pid}-${crypto.randomBytes(8).toString('hex')}`;
  const descriptor = fs.openSync(temporary, 'wx', 0o600);
  try {
    fs.writeFileSync(descriptor, body);
    fs.fsyncSync(descriptor);
  } finally {
    fs.closeSync(descriptor);
  }
  fs.renameSync(temporary, file);
}

export function readAndVerifyArtifacts(evidence, evidencePath) {
  const root = path.dirname(path.resolve(evidencePath));
  for (const artifact of [...evidence.rawArtifacts, evidence.reportArtifact]) {
    const file = path.resolve(root, artifact.path);
    assert.ok(file.startsWith(`${root}${path.sep}`), 'artifact escapes evidence root');
    const body = fs.readFileSync(file);
    assert.equal(body.byteLength, artifact.bytes, `${artifact.path} byte count`);
    assert.equal(sha256(body), artifact.sha256, `${artifact.path} digest`);
    scanRedacted(JSON.parse(body.toString('utf8')), artifact.path);
  }
}
