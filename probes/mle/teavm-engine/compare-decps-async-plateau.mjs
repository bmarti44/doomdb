#!/usr/bin/env node
import assert from 'node:assert/strict';
import fs from 'node:fs';
import {normalizeDbOutput} from '../../../scripts/lib/db-output.mjs';

const authority =
  '5ec18cbe4cff7192d384e81d1010e0133d357d44ff17fa65821e1489c4fd1ee3';
const tics = 5250;
const windowsPerPass = 53;
const selfTest = process.argv[2] === '--self-test';
const passes = selfTest ? 4 : Number(process.argv[3]);
assert.ok(Number.isInteger(passes) && passes >= 4 && passes <= 6,
  'plateau pass count must be 4..6');

const median = values => {
  const sorted = values.toSorted((left, right) => left - right);
  const middle = Math.floor(sorted.length / 2);
  return sorted.length % 2 === 0
    ? (sorted[middle - 1] + sorted[middle]) / 2
    : sorted[middle];
};
const fields = line => Object.fromEntries(line.split('|').slice(1).map(token => {
  const separator = token.indexOf('=');
  return [token.slice(0, separator), token.slice(separator + 1)];
}));
const improvement = (before, after) => (before - after) * 100 / before;

function synthetic() {
  const lines = [
    `PMLE_DECPS_ARTIFACT|sha256=${authority}|bytes=1081335`
      + '|phase=default-async-plateau',
  ];
  for (let pass = 1; pass <= passes; pass++) {
    lines.push(`PMLE_DECPS_ASYNC_PLATEAU_PASS|pass=${pass}|event=BEGIN`
      + `|utc=2026-07-25T00:0${pass}:00.000Z`);
    const value = pass === 1 ? 100 : 75;
    for (let tic = 1; tic <= tics; tic++) {
      lines.push(`PMLE_LIVE_REPLAY_TIC|tic=${tic}|mle_ms=${value}`
        + `|monotonic_ms=${value}|clock_delta_ms=0|clock_suspect=0`);
    }
    for (let index = 0; index < windowsPerPass; index++) {
      lines.push('PMLE_LIVE_REPLAY_WINDOW'
        + `|through_tic=${Math.min((index + 1) * 100, tics)}`
        + `|monotonic_tps=${pass === 1 ? 10 : 13.333333}`);
    }
    lines.push('PMLE_LIVE_REPLAY_TICKER'
      + `|stream=live-dm-2026-07-23|tics=${tics}`
      + `|monotonic_tps=${pass === 1 ? 10 : 13.333333}`);
    lines.push(`PMLE_DECPS_ASYNC_PLATEAU_PASS|pass=${pass}|event=END`
      + `|utc=2026-07-25T00:0${pass}:30.000Z`);
  }
  return lines.join('\n');
}

const input = selfTest ? synthetic() : fs.readFileSync(process.argv[2], 'utf8');
const lines = normalizeDbOutput(input);
const artifact = lines.filter(line => line.startsWith('PMLE_DECPS_ARTIFACT|'));
assert.deepEqual(artifact, [
  `PMLE_DECPS_ARTIFACT|sha256=${authority}|bytes=1081335`
    + '|phase=default-async-plateau',
]);

const markers = lines.filter(line =>
  line.startsWith('PMLE_DECPS_ASYNC_PLATEAU_PASS|'));
assert.equal(markers.length, passes * 2);
for (let pass = 1; pass <= passes; pass++) {
  assert.match(markers[(pass - 1) * 2],
    new RegExp(`^PMLE_DECPS_ASYNC_PLATEAU_PASS\\|pass=${pass}\\|event=BEGIN\\|`));
  assert.match(markers[(pass - 1) * 2 + 1],
    new RegExp(`^PMLE_DECPS_ASYNC_PLATEAU_PASS\\|pass=${pass}\\|event=END\\|`));
}
for (let pass = 1; pass <= passes; pass++) {
  const begin = lines.findIndex(line => line.startsWith(
    `PMLE_DECPS_ASYNC_PLATEAU_PASS|pass=${pass}|event=BEGIN|`));
  const end = lines.findIndex(line => line.startsWith(
    `PMLE_DECPS_ASYNC_PLATEAU_PASS|pass=${pass}|event=END|`));
  const priorEnd = pass === 1 ? -1 : lines.findIndex(line => line.startsWith(
    `PMLE_DECPS_ASYNC_PLATEAU_PASS|pass=${pass - 1}|event=END|`));
  const segment = lines.slice(begin + 1, end);
  assert.ok(begin > priorEnd && end > begin,
    `plateau pass ${pass} markers are out of order`);
  assert.equal(segment.filter(line =>
    line.startsWith('PMLE_LIVE_REPLAY_TIC|')).length, tics);
  assert.equal(segment.filter(line =>
    line.startsWith('PMLE_LIVE_REPLAY_WINDOW|')).length, windowsPerPass);
  assert.equal(segment.filter(line =>
    line.startsWith('PMLE_LIVE_REPLAY_TICKER|')).length, 1);
}

const samples = lines.filter(line =>
  line.startsWith('PMLE_LIVE_REPLAY_TIC|')).map(line => {
  const match = line.match(
    /^PMLE_LIVE_REPLAY_TIC\|tic=([0-9]+)\|mle_ms=(-?[0-9.]+)\|monotonic_ms=([0-9.]+)\|clock_delta_ms=([0-9.]+)\|clock_suspect=([01])$/);
  assert.ok(match, 'invalid plateau tic row');
  return {
    tic: Number(match[1]),
    wallMs: Number(match[2]),
    monotonicMs: Number(match[3]),
    deltaMs: Number(match[4]),
    suspect: match[5] === '1',
  };
});
assert.equal(samples.length, passes * tics);
for (let pass = 0; pass < passes; pass++) {
  for (let index = 0; index < tics; index++) {
    const sample = samples[pass * tics + index];
    assert.equal(sample.tic, index + 1);
    assert.ok(Number.isFinite(sample.wallMs));
    assert.ok(Number.isFinite(sample.monotonicMs) && sample.monotonicMs >= 0);
    const delta = Math.abs(sample.wallMs - sample.monotonicMs);
    assert.equal(sample.suspect, sample.wallMs <= 0 || delta > 30);
    assert.ok(Math.abs(sample.deltaMs - delta) <= .002);
  }
}
const suspects = samples.filter(sample => sample.suspect);
const exclusionCap = Math.floor(samples.length * .005);
assert.ok(suspects.length <= exclusionCap,
  `plateau clock exclusions exceed 0.5%: ${suspects.length}/${samples.length}`);

const windowRows = lines.filter(line =>
  line.startsWith('PMLE_LIVE_REPLAY_WINDOW|')).map(fields);
assert.equal(windowRows.length, passes * windowsPerPass);
const tickerRows = lines.filter(line =>
  line.startsWith('PMLE_LIVE_REPLAY_TICKER|')).map(fields);
assert.equal(tickerRows.length, passes);

const passResults = [];
for (let pass = 0; pass < passes; pass++) {
  const passSamples = samples.slice(pass * tics, (pass + 1) * tics);
  const valid = passSamples.filter(sample => !sample.suspect);
  const ticker = tickerRows[pass];
  assert.equal(ticker.stream, 'live-dm-2026-07-23');
  assert.equal(Number(ticker.tics), tics);
  const monotonicTps = Number(ticker.monotonic_tps);
  assert.ok(monotonicTps > 0);
  const windows = [];
  for (let index = 0; index < windowsPerPass; index++) {
    const through = Math.min((index + 1) * 100, tics);
    const start = index * 100;
    const count = Math.min(100, tics - start);
    const validWindow = passSamples.slice(start, start + count)
      .filter(sample => !sample.suspect);
    assert.ok(validWindow.length > 0);
    const row = windowRows[pass * windowsPerPass + index];
    assert.equal(Number(row.through_tic), through);
    assert.ok(Number(row.monotonic_tps) > 0);
    windows.push({
      through,
      wallMedian: median(validWindow.map(sample => sample.wallMs)),
      monotonicTps: Number(row.monotonic_tps),
    });
  }
  passResults.push({
    pass: pass + 1,
    wallMedian: median(valid.map(sample => sample.wallMs)),
    monotonicTps,
    exclusions: passSamples.filter(sample => sample.suspect).length,
    windows,
  });
}

const transitions = [];
for (let pass = 1; pass < passes; pass++) {
  const before = passResults[pass - 1];
  const after = passResults[pass];
  const matched = before.windows.map((window, index) => ({
    through: window.through,
    wall: improvement(window.wallMedian, after.windows[index].wallMedian),
    monotonic: (after.windows[index].monotonicTps - window.monotonicTps)
      * 100 / window.monotonicTps,
  }));
  const jointLandings = matched.filter(row => row.wall >= 20
    && row.monotonic >= 20);
  const jointRegressions = matched.filter(row => row.wall <= -20
    && row.monotonic <= -20);
  const result = {
    from: pass,
    to: pass + 1,
    routeWall: improvement(before.wallMedian, after.wallMedian),
    routeMonotonic: (after.monotonicTps - before.monotonicTps)
      * 100 / before.monotonicTps,
    medianWindowWall: median(matched.map(row => row.wall)),
    medianWindowMonotonic: median(matched.map(row => row.monotonic)),
    jointLandings,
    jointRegressions,
  };
  transitions.push(result);
  console.log(
    `PMLE_DECPS_ASYNC_PLATEAU_TRANSITION|from=${result.from}|to=${result.to}`
    + `|route_wall_improvement_pct=${result.routeWall.toFixed(3)}`
    + `|route_monotonic_improvement_pct=${result.routeMonotonic.toFixed(3)}`
    + `|median_window_wall_improvement_pct=${result.medianWindowWall.toFixed(3)}`
    + `|median_window_monotonic_improvement_pct=${result.medianWindowMonotonic.toFixed(3)}`
    + `|joint_landing_windows=${jointLandings.length}`
    + `|joint_regression_windows=${jointRegressions.length}`,
  );
}
for (const result of passResults) {
  console.log(
    `PMLE_DECPS_ASYNC_PLATEAU_PASS_RESULT|pass=${result.pass}`
    + `|wall_p50_ms=${result.wallMedian.toFixed(3)}`
    + `|monotonic_tps=${result.monotonicTps.toFixed(3)}`
    + `|clock_exclusions=${result.exclusions}`,
  );
}

const warmTps = passResults.slice(1).map(result => result.monotonicTps);
const warmMedian = median(warmTps);
const warmSpread = (Math.max(...warmTps) - Math.min(...warmTps))
  * 100 / warmMedian;
const landingTransitions = transitions.filter(result =>
  result.jointLandings.length > 0).length;
const regressionTransitions = transitions.filter(result =>
  result.jointRegressions.length > 0).length;
const plateau = warmSpread <= 10 ? 'STABLE' : 'UNSTABLE';
console.log(
  `PMLE_DECPS_ASYNC_PLATEAU|PASS|passes=${passes}|tics_per_pass=${tics}`
  + `|authority_sha256=${authority}|clock_exclusions=${suspects.length}`
  + `|clock_exclusion_cap=${exclusionCap}`
  + `|landing_transitions=${landingTransitions}`
  + `|regression_transitions=${regressionTransitions}`
  + `|warm_route_tps_spread_pct=${warmSpread.toFixed(3)}`
  + `|plateau=${plateau}|compiler_cpu_attribution=EXTERNAL_CENSUS`
  + '|deopt_attribution=NO_DIRECT_SURFACE',
);

if (selfTest) {
  assert.equal(landingTransitions, 1);
  assert.equal(regressionTransitions, 0);
  assert.equal(plateau, 'STABLE');
  console.log('PASS PMLE-DECPS-ASYNC-PLATEAU-COMPARATOR-SELF-TEST');
}
