#!/usr/bin/env node
import assert from 'node:assert/strict';
import crypto from 'node:crypto';
import fs from 'node:fs';
import path from 'node:path';
import {gunzipSync} from 'node:zlib';
import {performance} from 'node:perf_hooks';
import {
  CONTRACT, atomicWrite, buildReport, canonicalJson, readAndVerifyArtifacts,
  scanRedacted, sha256, validateEvidenceShape, validateReplay
} from './performance/t12.1-evidence.mjs';
import {collectDatabaseEvidence} from './performance/t12.1-collector.mjs';

// Runtime plans are required as DBMS_XPLAN DISPLAY_CURSOR(..., 'ALLSTATS LAST').
// Cursor hygiene comes from redacted V$SQL before/after observations.
const usage = 'usage: verify-performance-baseline.mjs <evidence.json> | --collect <replay.json> <evidence.json>';

function decodeTransport(document) {
  assert.ok(document && typeof document === 'object' && !Array.isArray(document), 'REST document is invalid');
  const encoded = document.p_payload;
  assert.equal(typeof encoded, 'string', 'REST payload missing');
  const compressed = Buffer.from(encoded, 'base64');
  assert.ok(compressed.length > 0, 'empty transport payload');
  const frame = JSON.parse(gunzipSync(compressed));
  assert.equal(frame.w, CONTRACT.width);
  assert.equal(frame.h, CONTRACT.height);
  assert.ok(Array.isArray(frame.cols) && frame.cols.length === CONTRACT.width);
  const pixels = Buffer.alloc(CONTRACT.width * CONTRACT.height);
  for (let x = 0; x < CONTRACT.width; x += 1) {
    let y = 0;
    for (const run of frame.cols[x]) {
      assert.ok(Array.isArray(run) && run.length === 3);
      const [start, length, color] = run;
      assert.equal(start, y);
      assert.ok(Number.isInteger(length) && length > 0 && y + length <= CONTRACT.height);
      assert.ok(Number.isInteger(color) && color >= 0 && color <= 255);
      for (let offset = 0; offset < length; offset += 1) pixels[(y + offset) * CONTRACT.width + x] = color;
      y += length;
    }
    assert.equal(y, CONTRACT.height);
  }
  // The timed blit is a complete memory copy, independent of production code.
  const canvas = Buffer.alloc(pixels.length);
  pixels.copy(canvas);
  return {compressed, frame, canvas};
}

async function post(base, route, body) {
  const target = new URL(`${route}/`, base.endsWith('/') ? base : `${base}/`);
  const response = await fetch(target, {
    method: 'POST',
    headers: {'content-type': 'application/json'},
    body: JSON.stringify(body),
    redirect: 'error',
    signal: AbortSignal.timeout(120_000)
  });
  assert.equal(response.ok, true, `${route} failed with ${response.status}`);
  const bytes = Buffer.from(await response.arrayBuffer());
  return {bytes, document: JSON.parse(bytes.toString('utf8'))};
}

function commandDigest(samples) {
  return sha256(JSON.stringify(samples.map(sample => sample.command)));
}

function writeArtifact(root, relative, value, kind, records, trailingNewline = true) {
  const body = trailingNewline ? canonicalJson(value) : JSON.stringify(value);
  const destination = path.resolve(root, relative);
  assert.ok(destination.startsWith(`${root}${path.sep}`), 'artifact path escape');
  scanRedacted(value, relative);
  atomicWrite(destination, body);
  return {kind, path: relative, sha256: sha256(body), bytes: Buffer.byteLength(body), records};
}

async function collect(replayPath, evidencePath) {
  assert.equal(process.env.T121_LIVE_CONFIRMED, 'YES', 'live collection requires T121_LIVE_CONFIRMED=YES');
  const base = process.env.T121_ORDS_BASE_URL;
  assert.ok(base, 'T121_ORDS_BASE_URL is required');
  const parsedBase = new URL(base);
  assert.ok(['http:', 'https:'].includes(parsedBase.protocol));
  assert.equal(parsedBase.username, '');
  assert.equal(parsedBase.password, '');
  const collectorCommand = JSON.parse(process.env.T121_DB_COLLECTOR_COMMAND || 'null');
  assert.ok(Array.isArray(collectorCommand), 'T121_DB_COLLECTOR_COMMAND must be a JSON argv array');
  const replayBytes = fs.readFileSync(replayPath);
  const replay = validateReplay(JSON.parse(replayBytes));
  const startedUtc = new Date().toISOString();
  const observationsPromise = collectDatabaseEvidence(collectorCommand, replay.identitySha256, process.env);
  const external = [];
  let session;
  for (const item of replay.frames) {
    const route = item.frame === 0 ? 'new_game' : 'step';
    const request = item.frame === 0 ? item.request : {
      p_session: session,
      p_commands: JSON.stringify({v: 1, commands: [item.request]})
    };
    const begin = performance.now();
    const response = await post(base, route, request);
    const responseAt = performance.now();
    if (item.frame === 0) {
      assert.match(response.document.p_session, /^[0-9a-f]{32}$/);
      session = response.document.p_session;
    }
    const decodeBegin = performance.now();
    const decoded = decodeTransport(response.document);
    const decodeEnd = performance.now();
    const responseBodyKeys = Object.keys(decoded.frame).sort();
    for (const key of CONTRACT.forbiddenPayloadKeys) assert.ok(!responseBodyKeys.includes(key), `stage timer leaked in frame ${item.frame}`);
    external.push({
      frame: item.frame,
      phase: item.frame < CONTRACT.warmFrames ? 'warm' : 'measured',
      pose: item.pose,
      command: item.command,
      externalClock: true,
      endToEndMs: responseAt - begin,
      decodeBlitMs: decodeEnd - decodeBegin,
      payloadBytes: response.bytes.length,
      payloadSha256: sha256(response.bytes),
      responseBodyKeys
    });
  }
  session = undefined;
  const observations = await observationsPromise;
  const samples = external.map((sample, frame) => ({...sample, ...observations.stageSamples[frame]}));
  const root = path.dirname(path.resolve(evidencePath));
  const payloads = samples.map(({frame, payloadBytes, payloadSha256, responseBodyKeys}) => ({frame, payloadBytes, payloadSha256, responseBodyKeys}));
  const replayLedger = {identitySha256: replay.identitySha256, sourceBytesSha256: sha256(replayBytes), frames: 300, warmFrames: 30, measuredFrames: 270, resolution: [320, 200], commandsSha256: commandDigest(samples)};
  const rawArtifacts = [
    writeArtifact(root, 'artifacts/performance/t12.1/raw/samples.json', samples, 'samples', 300),
    writeArtifact(root, 'artifacts/performance/t12.1/raw/plans.json', observations.plans, 'plans', 3),
    writeArtifact(root, 'artifacts/performance/t12.1/raw/vsql.json', observations.vsql, 'vsql', 3),
    writeArtifact(root, 'artifacts/performance/t12.1/raw/payloads.json', payloads, 'payloads', 300),
    writeArtifact(root, 'artifacts/performance/t12.1/raw/replay.json', replayLedger, 'replay', 1)
  ];
  const report = buildReport(samples, observations.vsql, rawArtifacts);
  const reportArtifact = writeArtifact(root, 'artifacts/performance/t12.1/report/baseline.json', report, 'report', 1, false);
  delete reportArtifact.kind;
  delete reportArtifact.records;
  const evidence = {
    schema: 1,
    task: CONTRACT.task,
    status: 'COMPLETE',
    synthetic: false,
    resolution: [320, 200],
    replay: {frames: 300, warmFrames: 30, measuredFrames: 270, sha256: replay.identitySha256, commandsSha256: commandDigest(samples)},
    capture: {owner: 'independent evaluator', clock: 'external monotonic', startedUtc, endedUtc: new Date().toISOString(), atomicWrite: true},
    samples,
    plans: observations.plans,
    vsql: observations.vsql,
    shapes: observations.shapes,
    rawArtifacts,
    reportArtifact,
    report
  };
  validateEvidenceShape(evidence);
  atomicWrite(path.resolve(evidencePath), canonicalJson(evidence));
  readAndVerifyArtifacts(evidence, evidencePath);
  process.stdout.write(`COLLECTED T12.1 baseline evidence (${CONTRACT.frames} frames; ${CONTRACT.measuredFrames} measured)\n`);
}

function verify(evidencePath) {
  const evidence = validateEvidenceShape(JSON.parse(fs.readFileSync(evidencePath, 'utf8')));
  readAndVerifyArtifacts(evidence, evidencePath);
  assert.equal(evidence.report.rawManifestSha256, sha256(JSON.stringify(evidence.rawArtifacts)));
  assert.equal(evidence.reportArtifact.sha256, sha256(JSON.stringify(evidence.report)));
  process.stdout.write('PASS T12.1-PRODUCTION-EVIDENCE (atomic artifacts, replay, plans, cursors, payloads, redaction)\n');
}

const arguments_ = process.argv.slice(2);
if (arguments_[0] === '--collect') {
  assert.equal(arguments_.length, 3, usage);
  await collect(arguments_[1], arguments_[2]);
} else {
  assert.equal(arguments_.length, 1, usage);
  verify(arguments_[0]);
}
