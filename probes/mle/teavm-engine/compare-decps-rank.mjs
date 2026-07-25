#!/usr/bin/env node
import {spawnSync} from 'node:child_process';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';

const expectedTics = 5250;
const maximumClockFailures = Math.floor(expectedTics * 0.005);
const stream = 'live-dm-2026-07-23';
const predecessor = Object.freeze({
  sha256: '2848ef7a8dc4799de7faa46bcf304f4ac3d351da97be94b144a53f3300607f29',
  bytes: 1081331,
});
const candidate = Object.freeze({
  sha256: '5ec18cbe4cff7192d384e81d1010e0133d357d44ff17fa65821e1489c4fd1ee3',
  bytes: 1081335,
});

function fail(message) {
  throw new Error(message);
}

function unfoldSqlcl(text) {
  return text
    .replace(/\r?\n(?=[0-9]+\|memory=)/g, '')
    .replace(/\r?\n(?=[0-9]+\|p(?:95|99)_ms=)/g, '')
    .replace(/\r?\n(?=[0-9]+\|throughput_tps=)/g, '');
}

function exactlyOne(lines, predicate, label) {
  const matches = lines.filter(predicate);
  if (matches.length !== 1) {
    fail(`${label}: expected exactly one record, found ${matches.length}`);
  }
  return matches[0];
}

function nearestRank(values, fraction) {
  const sorted = values.toSorted((left, right) => left - right);
  return sorted[Math.ceil(sorted.length * fraction) - 1];
}

function parseEvidence(text, expected, label) {
  const normalized = unfoldSqlcl(text);
  const lines = normalized.split(/\r?\n/);
  const artifactPrefix = 'PMLE_DECPS_ARTIFACT|';
  const artifact = exactlyOne(
    lines,
    line => line.startsWith(artifactPrefix),
    `${label} artifact`,
  );
  const expectedArtifact =
    `${artifactPrefix}sha256=${expected.sha256}|bytes=${expected.bytes}`
      + '|phase=interpreter';
  if (artifact !== expectedArtifact) {
    fail(`${label}: artifact identity mismatch`);
  }

  const samplePattern =
    /^PMLE_LIVE_REPLAY_TIC\|tic=([0-9]+)\|mle_ms=(-?[0-9.]+)$/;
  const samples = lines
    .map((line, index) => {
      const match = line.match(samplePattern);
      return match === null
        ? null
        : {line: index, tic: Number(match[1]), ms: Number(match[2])};
    })
    .filter(Boolean);
  if (samples.length !== expectedTics) {
    fail(`${label}: expected ${expectedTics} tic samples, found ${samples.length}`);
  }
  for (let index = 0; index < samples.length; index += 1) {
    const sample = samples[index];
    if (sample.tic !== index + 1 || !Number.isFinite(sample.ms)) {
      fail(`${label}: tic sequence/value mismatch at index ${index + 1}`);
    }
  }

  const tickerPrefix =
    `PMLE_LIVE_REPLAY_TICKER|stream=${stream}|tics=${expectedTics}|`;
  const ticker = exactlyOne(
    lines,
    line => line.startsWith('PMLE_LIVE_REPLAY_TICKER|'),
    `${label} ticker`,
  );
  if (!ticker.startsWith(tickerPrefix)) {
    fail(`${label}: ticker stream/tic count mismatch`);
  }
  const artifactLine = lines.indexOf(artifact);
  const tickerLine = lines.indexOf(ticker);
  if (artifactLine >= samples[0].line
      || tickerLine <= samples[samples.length - 1].line) {
    fail(`${label}: artifact, tic samples, and ticker are out of order`);
  }

  const invalid = samples.filter(sample => sample.ms <= 0);
  if (invalid.length > maximumClockFailures) {
    fail(
      `${label}: ${invalid.length} non-positive clock samples exceed `
        + `${maximumClockFailures} (0.5%)`,
    );
  }
  const valid = samples.filter(sample => sample.ms > 0);
  if (valid.length === 0) {
    fail(`${label}: no valid clock samples`);
  }
  return {
    invalidTics: invalid.map(sample => sample.tic),
    validCount: valid.length,
    p50: nearestRank(valid.map(sample => sample.ms), 0.50),
    p95: nearestRank(valid.map(sample => sample.ms), 0.95),
  };
}

function compare(predecessorText, candidateText) {
  const before = parseEvidence(predecessorText, predecessor, 'predecessor');
  const after = parseEvidence(candidateText, candidate, 'candidate');
  const p50Delta = (after.p50 - before.p50) * 100 / before.p50;
  const p95Delta = (after.p95 - before.p95) * 100 / before.p95;
  if (Math.abs(p50Delta) > 5 || Math.abs(p95Delta) > 5) {
    fail(
      `candidate exceeds 5% promotion rule: p50=${p50Delta.toFixed(3)}% `
        + `p95=${p95Delta.toFixed(3)}%`,
    );
  }
  return {before, after, p50Delta, p95Delta};
}

function render(result) {
  const bad = values => values.length === 0 ? 'none' : values.join(',');
  return [
    'PMLE_DECPS_RANK_CLOCK_INTEGRITY|PASS'
      + `|maximum_exclusions=${maximumClockFailures}`
      + `|predecessor_excluded=${result.before.invalidTics.length}`
      + `|predecessor_tics=${bad(result.before.invalidTics)}`
      + `|candidate_excluded=${result.after.invalidTics.length}`
      + `|candidate_tics=${bad(result.after.invalidTics)}`,
    'PMLE_DECPS_RANK_COMPARISON|PASS'
      + `|tics=${expectedTics}`
      + `|predecessor_sha256=${predecessor.sha256}`
      + `|candidate_sha256=${candidate.sha256}`
      + `|predecessor_valid=${result.before.validCount}`
      + `|candidate_valid=${result.after.validCount}`
      + `|predecessor_p50_ms=${result.before.p50.toFixed(3)}`
      + `|candidate_p50_ms=${result.after.p50.toFixed(3)}`
      + `|p50_delta_pct=${result.p50Delta.toFixed(3)}`
      + `|predecessor_p95_ms=${result.before.p95.toFixed(3)}`
      + `|candidate_p95_ms=${result.after.p95.toFixed(3)}`
      + `|p95_delta_pct=${result.p95Delta.toFixed(3)}`
      + '|promotion_limit_pct=5.000',
  ].join('\n');
}

function syntheticArtifact(identity, samples) {
  const values = samples.map(
    (value, index) =>
      `PMLE_LIVE_REPLAY_TIC|tic=${index + 1}|mle_ms=${value}`,
  );
  return [
    `PMLE_DECPS_ARTIFACT|sha256=${identity.sha256}`
      + `|bytes=${identity.bytes}|phase=interpreter`,
    ...values,
    `PMLE_LIVE_REPLAY_TICKER|stream=${stream}|tics=${expectedTics}`
      + '|p50_ms=1|p95_ms=1|p99_ms=1|max_ms=1|throughput_tps=1',
  ].join('\n');
}

function selfTest() {
  const beforeValues = Array.from({length: expectedTics}, () => 100);
  const afterValues = Array.from({length: expectedTics}, () => 104);
  beforeValues[40] = -1;
  afterValues[80] = 0;
  const before = syntheticArtifact(predecessor, beforeValues);
  const after = syntheticArtifact(candidate, afterValues);
  const result = compare(before, after);
  if (result.p50Delta !== 4 || result.p95Delta !== 4) {
    fail('positive comparator self-test produced the wrong delta');
  }

  const rejected = (beforeMutation, afterMutation, expectedMessage) => {
    const directory = fs.mkdtempSync(
      path.join(os.tmpdir(), 'pmle-decps-rank-selftest-'),
    );
    const beforeFile = path.join(directory, 'before.log');
    const afterFile = path.join(directory, 'after.log');
    fs.writeFileSync(beforeFile, beforeMutation(before));
    fs.writeFileSync(afterFile, afterMutation(after));
    try {
      const child = spawnSync(
        process.execPath,
        [new URL(import.meta.url).pathname, beforeFile, afterFile],
        {encoding: 'utf8'},
      );
      if (child.status === 0 || !child.stderr.includes(expectedMessage)) {
        fail(`adversarial self-test was not rejected: ${expectedMessage}`);
      }
    } finally {
      fs.rmSync(directory, {recursive: true, force: true});
    }
  };
  const same = value => value;
  rejected(
    value => value.replace('|tic=1|', '|tic=2|'),
    same,
    'tic sequence/value mismatch',
  );
  rejected(
    same,
    value => value.replace(candidate.sha256, `0${candidate.sha256.slice(1)}`),
    'artifact identity mismatch',
  );
  rejected(
    same,
    value => {
      let changed = value;
      for (let tic = 1; tic <= maximumClockFailures + 1; tic += 1) {
        changed = changed.replace(`|tic=${tic}|mle_ms=104`, `|tic=${tic}|mle_ms=0`);
      }
      return changed;
    },
    'non-positive clock samples exceed',
  );
  rejected(
    same,
    value => value.replaceAll('|mle_ms=104', '|mle_ms=106'),
    'exceeds 5% promotion rule',
  );
  rejected(
    same,
    value => {
      const lines = value.split('\n');
      lines.unshift(lines.pop());
      return lines.join('\n');
    },
    'out of order',
  );
  console.log('PASS PMLE-DECPS-RANK-COMPARATOR-SELF-TEST');
}

if (process.argv[2] === '--self-test') {
  selfTest();
} else {
  const predecessorFile = process.argv[2];
  const candidateFile = process.argv[3];
  if (!predecessorFile || !candidateFile) {
    fail(
      'usage: compare-decps-rank.mjs PREDECESSOR_LOG CANDIDATE_LOG '
        + '| --self-test',
    );
  }
  console.log(
    render(compare(
      fs.readFileSync(predecessorFile, 'utf8'),
      fs.readFileSync(candidateFile, 'utf8'),
    )),
  );
}
