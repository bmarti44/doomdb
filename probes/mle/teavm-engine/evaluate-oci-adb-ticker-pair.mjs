#!/usr/bin/env node
import assert from 'node:assert/strict';
import fs from 'node:fs';
import {normalizeDbOutput} from '../../../scripts/lib/db-output.mjs';

const file = process.argv[2];
if (file === undefined) {
  throw new Error('usage: evaluate-oci-adb-ticker-pair.mjs PAIR_LOG');
}

const ticsPerPass = 5250;
const passCount = 2;
const peakWindowEnds = [200, 300, 400, 500, 600, 700, 800];
const minimumTps = 35;
const clockLimitMs = 30;
const maximumSuspects = 26;
const lines = normalizeDbOutput(fs.readFileSync(file, 'utf8'));

const parseFields = line => Object.fromEntries(
  line.split('|').slice(1).map(token => {
    const separator = token.indexOf('=');
    assert.ok(separator > 0, `invalid marker field: ${token}`);
    return [token.slice(0, separator), token.slice(separator + 1)];
  }),
);
const select = prefix => lines.filter(line => line.startsWith(prefix));

const passMarkers = select('PMLE_OCI_ADB_TICKER_PASS|');
assert.equal(passMarkers.length, 4, 'expected two ordered pass marker pairs');
for (let pass = 1; pass <= passCount; pass += 1) {
  assert.match(passMarkers[(pass - 1) * 2],
    new RegExp(`^PMLE_OCI_ADB_TICKER_PASS[|]pass=${pass}[|]event=BEGIN[|]`));
  assert.match(passMarkers[(pass - 1) * 2 + 1],
    new RegExp(`^PMLE_OCI_ADB_TICKER_PASS[|]pass=${pass}[|]event=END[|]`));
}

const samples = select('PMLE_LIVE_REPLAY_TIC|').map(parseFields);
assert.equal(samples.length, passCount * ticsPerPass,
  'ticker pair must retain all per-tic samples');
for (let pass = 0; pass < passCount; pass += 1) {
  for (let index = 0; index < ticsPerPass; index += 1) {
    const sample = samples[pass * ticsPerPass + index];
    assert.equal(Number(sample.tic), index + 1,
      `pass ${pass + 1} tic ordering`);
    const wallMs = Number(sample.mle_ms);
    const monotonicMs = Number(sample.monotonic_ms);
    const recordedDelta = Number(sample.clock_delta_ms);
    assert.ok(Number.isFinite(wallMs) && wallMs > 0);
    assert.ok(Number.isFinite(monotonicMs) && monotonicMs >= 0);
    const delta = Math.abs(wallMs - monotonicMs);
    assert.ok(Math.abs(delta - recordedDelta) <= .002,
      `pass ${pass + 1} tic ${index + 1} clock delta`);
    assert.equal(Number(sample.clock_suspect), delta > clockLimitMs ? 1 : 0,
      `pass ${pass + 1} tic ${index + 1} suspect classification`);
  }
}

const clockRows = select('PMLE_LIVE_REPLAY_CLOCK|').map(parseFields);
assert.equal(clockRows.length, passCount);
const tickerRows = select('PMLE_LIVE_REPLAY_TICKER|').map(parseFields);
assert.equal(tickerRows.length, passCount);
const windowRows = select('PMLE_LIVE_REPLAY_WINDOW|').map(parseFields);
assert.equal(windowRows.length, passCount * 53);

const results = [];
for (let pass = 0; pass < passCount; pass += 1) {
  const clock = clockRows[pass];
  assert.equal(Number(clock.tics), ticsPerPass);
  assert.equal(Number(clock.disagreement_limit_ms), clockLimitMs);
  assert.ok(Number(clock.suspects) <= maximumSuspects);
  assert.equal(clock.verdict, 'PASS');

  const ticker = tickerRows[pass];
  assert.equal(ticker.stream, 'live-dm-2026-07-23');
  assert.equal(Number(ticker.tics), ticsPerPass);
  const routeTps = Number(ticker.monotonic_tps);
  assert.ok(Number.isFinite(routeTps) && routeTps > 0);

  const passWindows = windowRows.slice(pass * 53, (pass + 1) * 53);
  const peak = peakWindowEnds.map(end => {
    const row = passWindows.find(candidate =>
      Number(candidate.through_tic) === end);
    assert.ok(row, `pass ${pass + 1} missing peak window ${end}`);
    assert.equal(Number(row.awakeMonsters), 20,
      `pass ${pass + 1} peak window ${end} awake population`);
    const tps = Number(row.monotonic_tps);
    assert.ok(Number.isFinite(tps) && tps > 0);
    return {end, tps};
  });
  const minimumPeakTps = Math.min(...peak.map(row => row.tps));
  const routePass = routeTps >= minimumTps;
  const peakPass = minimumPeakTps >= minimumTps;
  results.push({routeTps, minimumPeakTps, routePass, peakPass, peak});
  console.log(
    `PMLE_OCI_ADB_TICKER_RESULT|pass=${pass + 1}` +
    `|route_monotonic_tps=${routeTps.toFixed(3)}` +
    `|peak_minimum_monotonic_tps=${minimumPeakTps.toFixed(3)}` +
    `|clock_suspects=${clock.suspects}` +
    `|route_verdict=${routePass ? 'PASS' : 'FAIL'}` +
    `|peak_verdict=${peakPass ? 'PASS' : 'FAIL'}`,
  );
  for (const window of peak) {
    console.log(
      `PMLE_OCI_ADB_PEAK_WINDOW|pass=${pass + 1}` +
      `|through_tic=${window.end}` +
      `|monotonic_tps=${window.tps.toFixed(3)}`,
    );
  }
}

const routePass = results.every(result => result.routePass);
const peakPass = results.every(result => result.peakPass);
const overall = routePass && peakPass;
console.log(
  `PMLE_OCI_ADB_TICKER_GATE|${overall ? 'PASS' : 'FAIL'}` +
  `|authority_sha256=5ec18cbe4cff7192d384e81d1010e0133d357d44ff17fa65821e1489c4fd1ee3` +
  `|passes=${passCount}|tics_per_pass=${ticsPerPass}` +
  `|route_threshold_tps=${minimumTps.toFixed(3)}` +
  `|peak_threshold_tps=${minimumTps.toFixed(3)}` +
  `|route_verdict=${routePass ? 'PASS' : 'FAIL'}` +
  `|peak_verdict=${peakPass ? 'PASS' : 'FAIL'}` +
  `|client_unique_fps=NOT_YET_MEASURED` +
  `|release_verdict=${overall ? 'TICKER_PASS_CLIENT_PENDING' : 'TICKER_FAIL'}`,
);
if (!overall) process.exitCode = 1;
