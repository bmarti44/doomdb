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

function ascii(bytes, start, length) {
  return bytes.subarray(start, start + length).toString('ascii');
}

function decodeBinary(bytes) {
  const magic = bytes.length >= 4 ? ascii(bytes, 0, 4) : '';
  assert.ok(magic === 'DMF3' || magic === 'DMF4', 'unsupported DMF envelope');
  assert.ok(bytes.length >= 140, 'short DMF envelope');
  const tic = bytes.readInt32BE(4);
  const stateSha = ascii(bytes, 10, 64);
  const frameSha = ascii(bytes, 74, 64);
  const audioLength = bytes.readUInt16BE(138);
  const frameStart = 140 + audioLength;
  assert.ok(tic >= 0 && frameStart <= bytes.length, 'invalid DMF header');
  const transport = Buffer.alloc(CONTRACT.width * CONTRACT.height);
  if (magic === 'DMF3') {
    assert.equal(bytes.length, frameStart + transport.length);
    bytes.copy(transport, 0, frameStart);
  } else {
    let source = frameStart, target = 0;
    while (source < bytes.length && target < transport.length) {
      const control = bytes[source++];
      const length = (control & 0x7f) + 1;
      if ((control & 0x80) !== 0) {
        assert.ok(source < bytes.length && target + length <= transport.length);
        transport.fill(bytes[source++], target, target + length);
      } else {
        assert.ok(source + length <= bytes.length && target + length <= transport.length);
        bytes.copy(transport, target, source, source + length);
        source += length;
      }
      target += length;
    }
    assert.equal(source, bytes.length); assert.equal(target, transport.length);
  }
  const pixels = Buffer.alloc(transport.length);
  for (let x = 0; x < CONTRACT.width; x += 1) {
    for (let y = 0; y < CONTRACT.height; y += 1)
      pixels[y * CONTRACT.width + x] = transport[x * CONTRACT.height + y];
  }
  assert.match(stateSha, /^[0-9a-f]{64}$/);
  assert.equal(frameSha, sha256(pixels), 'DMF frame digest');
  JSON.parse(bytes.subarray(140, frameStart).toString('utf8'));
  return {tic, magic, stateSha, frameSha, pixels};
}

function decodeTransport(document) {
  assert.ok(document && typeof document === 'object' && !Array.isArray(document), 'REST document is invalid');
  const encoded = document.p_payload;
  assert.equal(typeof encoded, 'string', 'REST payload missing');
  const compressed = Buffer.from(encoded, 'base64');
  assert.ok(compressed.length > 0, 'empty transport payload');
  const inflated = compressed[0] === 0x1f && compressed[1] === 0x8b ?
    gunzipSync(compressed) : compressed;
  const frame = decodeBinary(inflated);
  const pixels = frame.pixels;
  // The timed blit is a complete memory copy, independent of production code.
  const canvas = Buffer.alloc(pixels.length);
  pixels.copy(canvas);
  return {compressed, frame, canvas};
}

async function post(base, route, body) {
  const request = target => fetch(target, {
    method: 'POST',
    headers: {'content-type': 'application/json'},
    body: JSON.stringify(body),
    redirect: 'error',
    signal: AbortSignal.timeout(120_000)
  });
  let target = new URL(route.toUpperCase(), base.endsWith('/') ? base : `${base}/`);
  let response = await request(target);
  if (response.status === 404) {
    target = new URL(route, base.endsWith('/') ? base : `${base}/`);
    response = await request(target);
  }
  assert.equal(response.ok, true, `${route} failed with ${response.status}`);
  const headersAt = performance.now();
  const bytes = Buffer.from(await response.arrayBuffer());
  const completeAt = performance.now();
  return {bytes, document: JSON.parse(bytes.toString('utf8')), headersAt, completeAt};
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
  const replay = validateReplay(JSON.parse(replayBytes), replayBytes);
  const startedUtc = new Date().toISOString();
  const external = [];
  let session;
  for (const item of replay.frames) {
    const begin = performance.now();
    let response;
    let submitMs = 0;
    if (item.frame === 0) response = await post(base, 'new_game', item.request);
    else {
      const command = {...item.request, seq: item.frame};
      const submitted = await post(base, 'submit_step', {
        p_session: session, p_commands: JSON.stringify({v: 2, commands: [command]})
      });
      submitMs = submitted.completeAt - begin;
      assert.match(submitted.document.p_request, /^[0-9a-f]{32}$/);
      do {
        response = await post(base, 'poll_frame', {
          p_session: session, p_seq: item.frame, p_wait_ms: 1000
        });
      } while (response.document.p_ready === 0);
      assert.equal(response.document.p_ready, 1);
    }
    const responseAt = response.completeAt;
    if (item.frame === 0) {
      assert.match(response.document.p_session, /^[0-9a-f]{32}$/);
      session = response.document.p_session;
    }
    const decodeBegin = performance.now();
    const decoded = decodeTransport(response.document);
    const decodeEnd = performance.now();
    const paletteBegin = performance.now();
    const rgba = Buffer.alloc(decoded.canvas.length * 4);
    for (let pixel = 0; pixel < decoded.canvas.length; pixel += 1) {
      const color = decoded.canvas[pixel];
      rgba[pixel * 4] = color; rgba[pixel * 4 + 1] = color;
      rgba[pixel * 4 + 2] = color; rgba[pixel * 4 + 3] = 255;
    }
    const paletteEnd = performance.now();
    const blit = Buffer.alloc(rgba.length); rgba.copy(blit);
    const paintEnd = performance.now();
    const responseBodyKeys = Object.keys(response.document).sort();
    for (const key of CONTRACT.forbiddenPayloadKeys) assert.ok(!responseBodyKeys.includes(key), `stage timer leaked in frame ${item.frame}`);
    external.push({
      frame: item.frame,
      phase: item.frame < CONTRACT.warmFrames ? 'warm' : 'measured',
      pose: item.pose,
      command: item.command,
      externalClock: true,
      endToEndMs: responseAt - begin,
      transferMs: response.completeAt - response.headersAt,
      decodeMs: decodeEnd - decodeBegin,
      paletteMs: paletteEnd - paletteBegin,
      blitMs: paintEnd - paletteEnd,
      decodeBlitMs: paintEnd - decodeBegin,
      inputToPaintMs: paintEnd - begin,
      submitMs,
      payloadBytes: response.bytes.length,
      transportBytes: decoded.compressed.length,
      stateSha256: decoded.frame.stateSha,
      frameSha256: decoded.frame.frameSha,
      payloadSha256: sha256(decoded.compressed),
      responseBodyKeys
    });
  }
  const observations = await collectDatabaseEvidence(collectorCommand,
    CONTRACT.replaySha256, session, process.env);
  session = undefined;
  const samples = external.map((sample, frame) => {
    const merged = {...sample, ...observations.stageSamples[frame]};
    // The database collector owns worker timings. ORDS plus connection/pool
    // overhead is the externally observed interval left after database work
    // and response-body transfer; it never enters the public payload.
    merged.ordsMs = Math.max(0,
      merged.endToEndMs - merged.databaseMs - merged.transferMs);
    return merged;
  });
  const root = path.dirname(path.resolve(evidencePath));
  const payloads = samples.map(({frame, payloadBytes, transportBytes, stateSha256,
    frameSha256, payloadSha256, responseBodyKeys}) => ({frame, payloadBytes,
    transportBytes, stateSha256, frameSha256, payloadSha256, responseBodyKeys}));
  const replayLedger = {identitySha256: CONTRACT.replaySha256,
    sourceBytesSha256: sha256(replayBytes), frames: 300, warmFrames: 30,
    measuredFrames: 270, resolution: [320, 200],
    engine: CONTRACT.engine, commandsSha256: commandDigest(samples),
    stateChainSha256: sha256(JSON.stringify(samples.map(row => row.stateSha256))),
    frameChainSha256: sha256(JSON.stringify(samples.map(row => row.frameSha256))),
    payloadChainSha256: sha256(JSON.stringify(samples.map(row => row.payloadSha256)))};
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
    replay: {frames: 300, warmFrames: 30, measuredFrames: 270,
      sha256: CONTRACT.replaySha256, commandsSha256: commandDigest(samples)},
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
