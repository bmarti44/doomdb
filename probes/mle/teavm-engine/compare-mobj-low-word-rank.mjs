#!/usr/bin/env node
import assert from 'node:assert/strict';
import fs from 'node:fs';
import {normalizeDbOutput} from '../../../scripts/lib/db-output.mjs';

const identities = [
  {sha: '5ec18cbe4cff7192d384e81d1010e0133d357d44ff17fa65821e1489c4fd1ee3',
    bytes: 1081335},
  {sha: 'c3d490fde9dd0cfea303419a049535f5a31b1684a1e752fa0389e4a50dfeefd8',
    bytes: 1081185},
];
const percentile = (values, fraction) =>
  values.toSorted((left, right) => left - right)[
    Math.ceil(values.length * fraction) - 1];
const fields = line => Object.fromEntries(line.split('|').slice(1).map(token => {
  const separator = token.indexOf('=');
  return [token.slice(0, separator), token.slice(separator + 1)];
}));

function parse(text, identity) {
  const lines = normalizeDbOutput(text);
  assert.equal(lines.filter(line => line ===
    `PMLE_DECPS_ARTIFACT|sha256=${identity.sha}|bytes=${identity.bytes}`
      + '|phase=interpreter').length, 1);
  const samples = lines.filter(line =>
    line.startsWith('PMLE_LIVE_REPLAY_TIC|')).map((line, index) => {
    const match = line.match(
      /^PMLE_LIVE_REPLAY_TIC\|tic=([0-9]+)\|mle_ms=(-?[0-9.]+)\|/);
    assert.ok(match);
    assert.equal(Number(match[1]), index + 1);
    return Number(match[2]);
  });
  assert.equal(samples.length, 5250);
  assert.ok(samples.filter(value => value <= 0).length <= 26);
  const valid = samples.filter(value => value > 0);
  const tickerRows = lines.filter(line =>
    line.startsWith('PMLE_LIVE_REPLAY_TICKER|'));
  assert.equal(tickerRows.length, 1);
  const ticker = fields(tickerRows[0]);
  assert.equal(ticker.stream, 'live-dm-2026-07-23');
  assert.equal(ticker.tics, '5250');
  const windows = lines.filter(line =>
    line.startsWith('PMLE_LIVE_REPLAY_WINDOW|')).map((line, index) => {
    const value = fields(line);
    const through = Number(value.through_tic);
    const start = index * 100;
    assert.equal(through, Math.min(start + 100, 5250));
    const awakeMatch = line.match(/\|awakeMonsters=([0-9]+)\|/);
    assert.ok(awakeMatch);
    return {
      through,
      awake: Number(awakeMatch[1]),
      median: percentile(
        samples.slice(start, through).filter(sample => sample > 0), .5),
    };
  });
  assert.equal(windows.length, 53);
  return {
    p50: percentile(valid, .5),
    p95: percentile(valid, .95),
    monotonicTps: Number(ticker.monotonic_tps),
    windows,
  };
}

function compare(before, after) {
  const improvement = (baseline, candidate) =>
    (baseline - candidate) * 100 / baseline;
  const peak = before.windows.map((window, index) => ({
    through: window.through,
    awake: window.awake,
    improvement: improvement(window.median, after.windows[index].median),
  })).filter(window => window.awake >= 20);
  assert.equal(peak.length, 7);
  const result = {
    p50Improvement: improvement(before.p50, after.p50),
    p95Improvement: improvement(before.p95, after.p95),
    throughputImprovement:
      (after.monotonicTps - before.monotonicTps) * 100 / before.monotonicTps,
    peakMedianImprovement: percentile(
      peak.map(window => window.improvement), .5),
    peakMaximumImprovement: Math.max(
      ...peak.map(window => window.improvement)),
  };
  result.verdict = Math.max(
    result.p50Improvement,
    result.p95Improvement,
    result.throughputImprovement,
    result.peakMedianImprovement,
  ) >= 5 ? 'PROMOTE_FOR_FULL_BATTERY' : 'REJECT_BELOW_5_PERCENT';
  return result;
}

if (process.argv[2] === '--self-test') {
  const before = {
    p50: 100, p95: 100, monotonicTps: 10,
    windows: Array.from({length: 7}, (_, index) => ({
      through: (index + 1) * 100, awake: 20, median: 100,
    })),
  };
  const rejected = compare(before, {
    p50: 96, p95: 96, monotonicTps: 10.4,
    windows: before.windows.map(value => ({...value, median: 96})),
  });
  assert.equal(rejected.verdict, 'REJECT_BELOW_5_PERCENT');
  const promoted = compare(before, {
    p50: 94, p95: 94, monotonicTps: 10.6,
    windows: before.windows.map(value => ({...value, median: 94})),
  });
  assert.equal(promoted.verdict, 'PROMOTE_FOR_FULL_BATTERY');
  console.log('PASS PMLE-MOBJ-LOW-WORD-COMPARATOR-SELF-TEST');
} else {
  const [baselinePath, candidatePath] = process.argv.slice(2);
  assert.ok(baselinePath && candidatePath);
  const result = compare(
    parse(fs.readFileSync(baselinePath, 'utf8'), identities[0]),
    parse(fs.readFileSync(candidatePath, 'utf8'), identities[1]),
  );
  console.log(
    `PMLE_MOBJ_LOW_WORD_RANK|${result.verdict}`
    + `|p50_improvement_pct=${result.p50Improvement.toFixed(3)}`
    + `|p95_improvement_pct=${result.p95Improvement.toFixed(3)}`
    + `|throughput_improvement_pct=${result.throughputImprovement.toFixed(3)}`
    + `|peak_awake20_window_count=7`
    + `|peak_median_improvement_pct=${result.peakMedianImprovement.toFixed(3)}`
    + `|peak_maximum_improvement_pct=${result.peakMaximumImprovement.toFixed(3)}`
    + '|promotion_threshold_pct=5.000',
  );
}
