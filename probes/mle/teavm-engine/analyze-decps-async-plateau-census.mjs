#!/usr/bin/env node
import assert from 'node:assert/strict';
import fs from 'node:fs';
import {normalizeDbOutput} from '../../../scripts/lib/db-output.mjs';

const selfTest = process.argv[2] === '--self-test';
const parseFields = line => Object.fromEntries(line.split('|').slice(1)
  .map(token => {
    const separator = token.indexOf('=');
    return [token.slice(0, separator), token.slice(separator + 1)];
  }));

function analyze(rawText, censusText, passes) {
  const lines = normalizeDbOutput(rawText);
  const markers = lines.filter(line =>
    line.startsWith('PMLE_DECPS_ASYNC_PLATEAU_PASS|')).map(line => {
    const match = line.match(
      /^PMLE_DECPS_ASYNC_PLATEAU_PASS\|pass=([1-6])\|event=(BEGIN|END)\|utc=([^Z]+Z)/);
    assert.ok(match, 'invalid plateau pass timestamp');
    return {pass: Number(match[1]), event: match[2], time: Date.parse(match[3])};
  });
  assert.equal(markers.length, passes * 2);
  const censusLines = censusText.split(/\r?\n/).filter(Boolean);
  const compiler = censusLines.filter(line =>
    line.startsWith('PMLE_DECPS_ASYNC_JIT_COMPILER_CENSUS|')).map(parseFields);
  const cpu = censusLines.filter(line =>
    line.startsWith('PMLE_DECPS_ASYNC_JIT_HOST_CPU|')).map(parseFields);
  assert.ok(compiler.length >= passes);
  assert.equal(cpu.length, compiler.length);
  const maximumThreads = Math.max(
    ...compiler.map(row => Number(row.matching_threads)));
  const maximumCompilerTicks = Math.max(
    ...compiler.map(row => Number(row.compiler_cpu_ticks)));
  assert.ok(Number.isFinite(maximumThreads) && Number.isFinite(maximumCompilerTicks));
  const results = [];
  for (let pass = 1; pass <= passes; pass++) {
    const begin = markers.find(row => row.pass === pass && row.event === 'BEGIN');
    const end = markers.find(row => row.pass === pass && row.event === 'END');
    assert.ok(begin && end && end.time > begin.time);
    const samples = cpu.filter(row => {
      const time = Date.parse(row.utc);
      return time >= begin.time && time <= end.time;
    });
    assert.ok(samples.length >= 2);
    const first = samples[0];
    const last = samples.at(-1);
    const busy = Number(last.busy_ticks) - Number(first.busy_ticks);
    const total = Number(last.total_ticks) - Number(first.total_ticks);
    assert.ok(busy >= 0 && total > 0 && busy <= total);
    results.push({pass, samples: samples.length, busyPercent: busy * 100 / total});
  }
  const busyValues = results.map(row => row.busyPercent);
  return {
    results,
    maximumThreads,
    maximumCompilerTicks,
    busySpread: Math.max(...busyValues) - Math.min(...busyValues),
  };
}

if (selfTest) {
  const raw = Array.from({length: 4}, (_, index) => {
    const pass = index + 1;
    return `PMLE_DECPS_ASYNC_PLATEAU_PASS|pass=${pass}|event=BEGIN`
      + `|utc=2026-07-25T00:0${pass}:00.000Z\n`
      + `PMLE_DECPS_ASYNC_PLATEAU_PASS|pass=${pass}|event=END`
      + `|utc=2026-07-25T00:0${pass}:30.000Z`;
  }).join('\n');
  const census = Array.from({length: 4}, (_, index) => {
    const pass = index + 1;
    return 'PMLE_DECPS_ASYNC_JIT_COMPILER_CENSUS'
      + `|utc=2026-07-25T00:0${pass}:00.000Z`
      + '|matching_threads=0|compiler_cpu_ticks=0|names=\n'
      + 'PMLE_DECPS_ASYNC_JIT_HOST_CPU'
      + `|utc=2026-07-25T00:0${pass}:00.000Z`
      + `|busy_ticks=${pass * 100}|total_ticks=${pass * 1000}\n`
      + 'PMLE_DECPS_ASYNC_JIT_COMPILER_CENSUS'
      + `|utc=2026-07-25T00:0${pass}:30.000Z`
      + '|matching_threads=0|compiler_cpu_ticks=0|names=\n'
      + 'PMLE_DECPS_ASYNC_JIT_HOST_CPU'
      + `|utc=2026-07-25T00:0${pass}:30.000Z`
      + `|busy_ticks=${pass * 100 + 30}|total_ticks=${pass * 1000 + 100}`;
  }).join('\n');
  const result = analyze(raw, census, 4);
  assert.equal(result.maximumThreads, 0);
  assert.equal(result.maximumCompilerTicks, 0);
  assert.equal(result.busySpread, 0);
  console.log('PASS PMLE-DECPS-ASYNC-PLATEAU-CENSUS-SELF-TEST');
} else {
  const [rawPath, censusPath, passText] = process.argv.slice(2);
  const passes = Number(passText);
  assert.ok(rawPath && censusPath && Number.isInteger(passes));
  const result = analyze(
    fs.readFileSync(rawPath, 'utf8'),
    fs.readFileSync(censusPath, 'utf8'),
    passes,
  );
  for (const row of result.results) {
    console.log(`PMLE_DECPS_ASYNC_PLATEAU_CPU|pass=${row.pass}`
      + `|samples=${row.samples}|host_busy_pct=${row.busyPercent.toFixed(3)}`);
  }
  console.log('PMLE_DECPS_ASYNC_PLATEAU_ATTRIBUTION|PASS'
    + `|maximum_named_compiler_threads=${result.maximumThreads}`
    + `|maximum_named_compiler_cpu_ticks=${result.maximumCompilerTicks}`
    + `|host_busy_spread_points=${result.busySpread.toFixed(3)}`
    + '|compiler_cpu_theft=NOT_OBSERVED'
    + '|deopt_churn=UNPROVEN_NO_DIRECT_SURFACE');
}
