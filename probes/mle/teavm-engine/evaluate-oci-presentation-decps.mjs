#!/usr/bin/env node
import assert from 'node:assert/strict';
import fs from 'node:fs';
import {
  oneDbRecord,
  selfTestDbOutput,
} from '../../../scripts/lib/db-output.mjs';

const parse = (text, prefix) => {
  const row = oneDbRecord(text, `${prefix}|`);
  const fields = new Map();
  for (const token of row.split('|').slice(1)) {
    const at = token.indexOf('=');
    const key = at < 0 ? token : token.slice(0, at);
    const value = at < 0 ? '' : token.slice(at + 1);
    assert.ok(!fields.has(key), `duplicate field ${key}`);
    fields.set(key, value);
  }
  return fields;
};

const requireSha = (fields, name) => {
  const value = fields.get(name) ?? '';
  assert.match(value, /^[0-9a-f]{64}$/, `${name} must be SHA-256`);
  return value;
};

const evaluate = (oracleText, rankText, expectedSamples) => {
  const oracle = parse(oracleText, 'PMLE_OCI_PRESENTATION_ORACLE');
  const rank = parse(rankText, 'PMLE_OCI_PRESENTATION_RANK');
  assert.equal(oracle.get('PASS'), '');
  assert.equal(rank.get('DIAGNOSTIC_NOT_GATE'), '');
  assert.equal(Number(oracle.get('samples')), expectedSamples);
  assert.equal(Number(rank.get('samples')), expectedSamples);
  assert.equal(Number(oracle.get('unique')), expectedSamples);
  assert.equal(Number(rank.get('unique')), expectedSamples);
  assert.equal(rank.get('transport'), 'persistent_returning_oracle_blob');
  for (const name of ['artifact_sha256', 'stream_sha256', 'chain_sha256']) {
    assert.equal(requireSha(rank, name), requireSha(oracle, name), name);
  }
  const p95 = Number(rank.get('pipeline_p95_ms'));
  assert.ok(Number.isFinite(p95) && p95 >= 0);
  const expectedVerdict = p95 <= 33.333 ? 'PASS' : 'FAIL';
  assert.equal(rank.get('exact_30fps'), expectedVerdict);
  assert.equal(Number(rank.get('clock_suspects')), 0);
  const temporaryLobsDelta = Number(rank.get('temporary_lobs_delta'));
  assert.ok(Number.isInteger(temporaryLobsDelta) && temporaryLobsDelta >= 0);
  return {
    samples: expectedSamples,
    pipelineP95Milliseconds: p95,
    exact30Fps: expectedVerdict,
    temporaryLobsDelta,
    locatorHygiene: temporaryLobsDelta === 0 ? 'PASS' : 'FAIL',
    artifactSha256: requireSha(rank, 'artifact_sha256'),
    streamSha256: requireSha(rank, 'stream_sha256'),
    chainSha256: requireSha(rank, 'chain_sha256'),
  };
};

if (process.argv[2] === '--self-test') {
  selfTestDbOutput();
  const sha = 'ab'.repeat(32);
  const oracle =
    `PMLE_OCI_PRESENTATION_ORACLE|PASS|samples=100|unique=100|` +
    `artifact_sha256=${sha}|stream_sha256=${sha}|chain_sha256=${sha}\n`;
  const rank =
    `PMLE_OCI_PRESENTATION_RANK|DIAGNOSTIC_NOT_GATE|` +
    `transport=persistent_returning_oracle_blob|samples=100|unique=100|` +
    `pipeline_p95_ms=32.5|clock_suspects=0|temporary_lobs_delta=0|` +
    `exact_30fps=PASS|artifact_sha256=${sha}|stream_sha256=${sha}|` +
    `chain_sha256=${sha}\n`;
  assert.equal(evaluate(oracle, rank, 100).exact30Fps, 'PASS');
  assert.equal(evaluate(
    oracle, rank.replace('temporary_lobs_delta=0',
      'temporary_lobs_delta=1'), 100,
  ).locatorHygiene, 'FAIL');
  for (const invalid of [
    rank.replace('exact_30fps=PASS', 'exact_30fps=FAIL'),
    rank + rank,
  ]) {
    assert.throws(() => evaluate(oracle, invalid, 100));
  }
  console.log('PASS PMLE-OCI-PRESENTATION-DECPS-EVALUATOR-SELF-TEST');
} else {
  const [, , oraclePath, rankPath, samplesText] = process.argv;
  const samples = Number(samplesText);
  assert.ok(oraclePath && rankPath && [100, 300].includes(samples),
    'usage: evaluate-oci-presentation-decps.mjs ORACLE RANK 100|300');
  const verdict = evaluate(
    fs.readFileSync(oraclePath, 'utf8'),
    fs.readFileSync(rankPath, 'utf8'),
    samples,
  );
  console.log(
    `PMLE_OCI_PRESENTATION_DECPS_VERDICT|DIAGNOSTIC_NOT_GATE|` +
    `samples=${verdict.samples}|pipeline_p95_ms=` +
    `${verdict.pipelineP95Milliseconds.toFixed(3)}|` +
    `exact_30fps=${verdict.exact30Fps}|` +
    `temporary_lobs_delta=${verdict.temporaryLobsDelta}|` +
    `locator_hygiene=${verdict.locatorHygiene}|` +
    `artifact_sha256=${verdict.artifactSha256}|` +
    `stream_sha256=${verdict.streamSha256}|` +
    `chain_sha256=${verdict.chainSha256}`,
  );
}
