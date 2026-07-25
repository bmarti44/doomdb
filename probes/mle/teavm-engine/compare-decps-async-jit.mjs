#!/usr/bin/env node
import {spawnSync} from 'node:child_process';
import fs from 'node:fs';
import {normalizeDbOutput} from '../../../scripts/lib/db-output.mjs';

const file = process.argv[2];
if (!file) {
  throw new Error('usage: compare-decps-async-jit.mjs PAIR_LOG');
}
const tics = 5250;
const selfTest = file === '--self-test';
const selfTestArtifact =
  'PMLE_DECPS_ARTIFACT'
  + '|sha256=5ec18cbe4cff7192d384e81d1010e0133d357d44ff17fa65821e1489c4fd1ee3'
  + '|bytes=1081335|phase=default-async-pair';
const selfTestTicker = median =>
  'PMLE_LIVE_REPLAY_TICKER'
  + `|stream=live-dm-2026-07-23|tics=5250|p50_ms=${median}`;
const selfTestPass = pass =>
  Array.from({length: tics}, (_, index) => {
    const tic = index + 1;
    const value = pass === 0 ? 100 : (tic <= 100 ? 79 : 95);
    return `PMLE_LIVE_REPLAY_TIC|tic=${tic}|mle_ms=${value}`
      + `|monotonic_ms=${value}|clock_delta_ms=0|clock_suspect=0`;
  });
const selfTestWindows = pass =>
  Array.from({length: 53}, (_, index) => {
    const through = Math.min((index + 1) * 100, tics);
    const tps = pass === 0 ? 10 : (index === 0 ? 12.5 : 10.526315789);
    return `PMLE_LIVE_REPLAY_WINDOW|through_tic=${through}`
      + `|monotonic_tps=${tps}`;
  });
const makeSelfTest = () => [
  selfTestArtifact,
  ...selfTestPass(0),
  ...selfTestWindows(0),
  selfTestTicker(100),
  ...selfTestPass(1),
  ...selfTestWindows(1),
  selfTestTicker(95),
].join('\n');
const text = normalizeDbOutput(
  selfTest ? makeSelfTest() : fs.readFileSync(file, 'utf8'),
).join('\n');
const samples = [];
for (const match of text.matchAll(
    /^PMLE_LIVE_REPLAY_TIC\|tic=([0-9]+)\|mle_ms=(-?[0-9.]+)\|monotonic_ms=([0-9.]+)\|clock_delta_ms=([0-9.]+)\|clock_suspect=([01])$/gm)) {
  samples.push({
    tic: Number(match[1]),
    wallMs: Number(match[2]),
    monotonicMs: Number(match[3]),
    recordedDeltaMs: Number(match[4]),
    recordedSuspect: match[5] === '1',
  });
}
if (samples.length !== tics * 2) {
  throw new Error(`expected ${tics * 2} async samples, found ${samples.length}`);
}
for (let pass = 0; pass < 2; pass += 1) {
  for (let index = 0; index < tics; index += 1) {
    const sample = samples[pass * tics + index];
    if (sample.tic !== index + 1
        || !Number.isFinite(sample.wallMs)
        || !Number.isFinite(sample.monotonicMs)
        || sample.monotonicMs < 0) {
      throw new Error(`async pass ${pass + 1} tic sequence mismatch`);
    }
    const delta = Math.abs(sample.wallMs - sample.monotonicMs);
    const suspect = sample.wallMs <= 0 || delta > 30;
    if (sample.recordedSuspect !== suspect
        || Math.abs(sample.recordedDeltaMs - delta) > .002) {
      throw new Error(`async pass ${pass + 1} clock classification mismatch`);
    }
  }
}
const suspects = samples.filter(sample => sample.recordedSuspect);
const exclusionCap = Math.floor(samples.length * .005);
if (suspects.length > exclusionCap) {
  throw new Error(
    `async clock exclusions exceed 0.5% cap: ${suspects.length}/${samples.length}`,
  );
}
const exactLines = (prefix, label) => {
  const lines = text.split(/\r?\n/).filter(line => line.startsWith(prefix));
  if (lines.length !== 1) {
    throw new Error(`${label}: expected one ${prefix}, found ${lines.length}`);
  }
  return lines[0];
};
const artifact = exactLines('PMLE_DECPS_ARTIFACT|', 'async-JIT artifact');
if (artifact !==
    'PMLE_DECPS_ARTIFACT'
    + '|sha256=5ec18cbe4cff7192d384e81d1010e0133d357d44ff17fa65821e1489c4fd1ee3'
    + '|bytes=1081335|phase=default-async-pair') {
  throw new Error('async-JIT artifact is not the approved de-CPS candidate');
}
const tickerPrefix =
  `PMLE_LIVE_REPLAY_TICKER|stream=live-dm-2026-07-23|tics=${tics}|`;
const allTickerLines = text.split(/\r?\n/)
  .filter(line => line.startsWith('PMLE_LIVE_REPLAY_TICKER|'));
const tickerLines = allTickerLines
  .filter(line => line.startsWith(tickerPrefix));
if (allTickerLines.length !== 2 || tickerLines.length !== 2) {
  throw new Error(
    'async-JIT pair requires exactly two full expected-stream ticker '
    + `terminals, found ${tickerLines.length}/${allTickerLines.length}`,
  );
}
const orderedLines = text.split(/\r?\n/);
const sampleLineIndexes = [];
const tickerLineIndexes = [];
let artifactLineIndex = -1;
for (let index = 0; index < orderedLines.length; index += 1) {
  if (orderedLines[index].startsWith('PMLE_LIVE_REPLAY_TIC|')) {
    sampleLineIndexes.push(index);
  } else if (orderedLines[index].startsWith(tickerPrefix)) {
    tickerLineIndexes.push(index);
  } else if (orderedLines[index] === artifact) {
    artifactLineIndex = index;
  }
}
if (artifactLineIndex < 0
    || artifactLineIndex >= sampleLineIndexes[0]
    || tickerLineIndexes[0] <= sampleLineIndexes[tics - 1]
    || tickerLineIndexes[0] >= sampleLineIndexes[tics]
    || tickerLineIndexes[1] <= sampleLineIndexes[tics * 2 - 1]) {
  throw new Error(
    'async-JIT artifact, pass samples, and ticker terminals are out of order',
  );
}
const median = values => {
  const sorted = values.toSorted((left, right) => left - right);
  const middle = Math.floor(sorted.length / 2);
  return sorted.length % 2 === 0
    ? (sorted[middle - 1] + sorted[middle]) / 2
    : sorted[middle];
};
const windowRows = text.split(/\r?\n/)
  .filter(line => line.startsWith('PMLE_LIVE_REPLAY_WINDOW|'))
  .map(line => Object.fromEntries(line.split('|').slice(1).map(token => {
    const separator = token.indexOf('=');
    return [token.slice(0, separator), token.slice(separator + 1)];
  })));
if (windowRows.length !== 106) {
  throw new Error(`expected 106 monotonic windows, found ${windowRows.length}`);
}
const windows = [];
for (let start = 0; start < tics; start += 100) {
  const count = Math.min(100, tics - start);
  const firstSamples = samples.slice(start, start + count)
    .filter(row => !row.recordedSuspect).map(row => row.wallMs);
  const secondSamples = samples.slice(tics + start, tics + start + count)
    .filter(row => !row.recordedSuspect).map(row => row.wallMs);
  if (firstSamples.length === 0 || secondSamples.length === 0) {
    throw new Error(`async window through ${start + count} has no valid clock samples`);
  }
  const first = median(firstSamples);
  const second = median(
    secondSamples,
  );
  const improvement = (first - second) * 100 / first;
  const windowIndex = windows.length;
  const firstWindow = windowRows[windowIndex];
  const secondWindow = windowRows[53 + windowIndex];
  if (Number(firstWindow.through_tic) !== start + count
      || Number(secondWindow.through_tic) !== start + count) {
    throw new Error(`monotonic window through ${start + count} is out of order`);
  }
  const firstMonotonicTps = Number(firstWindow.monotonic_tps);
  const secondMonotonicTps = Number(secondWindow.monotonic_tps);
  if (!(firstMonotonicTps > 0) || !(secondMonotonicTps > 0)) {
    throw new Error(`monotonic window through ${start + count} is invalid`);
  }
  const monotonicImprovement =
    (secondMonotonicTps - firstMonotonicTps) * 100 / firstMonotonicTps;
  windows.push({
    through: start + count, first, second, improvement, monotonicImprovement,
  });
  console.log(
    `PMLE_DECPS_ASYNC_JIT_WINDOW|through_tic=${start + count}`
    + `|pass1_median_ms=${first.toFixed(3)}`
    + `|pass2_median_ms=${second.toFixed(3)}`
    + `|improvement_pct=${improvement.toFixed(3)}`
    + `|monotonic_tps_improvement_pct=${monotonicImprovement.toFixed(3)}`,
  );
}
const maximum = Math.max(...windows.map(window => window.improvement));
const maximumMonotonic = Math.max(
  ...windows.map(window => window.monotonicImprovement),
);
const landing = windows.some(window =>
  window.improvement >= 20 && window.monotonicImprovement >= 20);
const inert = windows.every(window =>
  window.improvement < 10 && window.monotonicImprovement < 10);
const verdict = landing
  ? 'LANDING_SIGNAL'
  : (inert
    ? 'ASYNC_JIT_INERT'
    : 'INCONCLUSIVE_10_TO_20_PERCENT');
console.log(
  `PMLE_DECPS_ASYNC_JIT|PASS|passes=2|tics_per_pass=${tics}`
  + '|authority_sha256=5ec18cbe4cff7192d384e81d1010e0133d357d44ff17fa65821e1489c4fd1ee3'
  + `|matched_windows=${windows.length}`
  + `|clock_exclusions=${suspects.length}|clock_exclusion_cap=${exclusionCap}`
  + `|maximum_improvement_pct=${maximum.toFixed(3)}`
  + `|maximum_monotonic_tps_improvement_pct=${maximumMonotonic.toFixed(3)}`
  + `|verdict=${verdict}`,
);
if (selfTest) {
  if (verdict !== 'LANDING_SIGNAL' || maximum !== 21) {
    throw new Error('async-JIT matched-window self-test failed');
  }
  const rejected = (mutate, expected) => {
    const temporary = `.pmle-decps-async-jit-selftest-${process.pid}.log`;
    fs.writeFileSync(temporary, mutate(makeSelfTest()));
    try {
      const result = spawnSync(
        process.execPath,
        [new URL(import.meta.url).pathname, temporary],
        {encoding: 'utf8'},
      );
      if (result.status === 0 || !result.stderr.includes(expected)) {
        throw new Error(`adversarial self-test was not rejected: ${expected}`);
      }
    } finally {
      fs.rmSync(temporary, {force: true});
    }
  };
  rejected(
    value => value.replace('|tic=1|', '|tic=0|'),
    'tic sequence mismatch',
  );
  rejected(
    value => value.replace(
      '5ec18cbe4cff7192d384e81d1010e0133d357d44ff17fa65821e1489c4fd1ee3',
      '0ec18cbe4cff7192d384e81d1010e0133d357d44ff17fa65821e1489c4fd1ee3',
    ),
    'not the approved de-CPS candidate',
  );
  rejected(
    value => value.replace('PMLE_LIVE_REPLAY_TICKER', 'REMOVED_TICKER'),
    'requires exactly two full expected-stream ticker terminals',
  );
  rejected(
    value => `${value}\n`
      + 'PMLE_LIVE_REPLAY_TICKER|stream=stale-stream|tics=5250|p50_ms=1',
    'requires exactly two full expected-stream ticker terminals',
  );
  rejected(
    value => {
      const lines = value.split('\n');
      const tickerIndex = lines.findIndex(line =>
        line.startsWith('PMLE_LIVE_REPLAY_TICKER|'));
      const firstTicker = lines.splice(tickerIndex, 1)[0];
      lines.push(firstTicker);
      return lines.join('\n');
    },
    'ticker terminals are out of order',
  );
  console.log('PASS PMLE-DECPS-ASYNC-JIT-COMPARATOR-SELF-TEST');
}
