#!/usr/bin/env node
import {spawnSync} from 'node:child_process';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';

const tics = 5250;
const maximumSuspects = Math.floor(tics * 0.005);
const disagreementLimitMs = 30;
const stream = 'live-dm-2026-07-23';
const identities = Object.freeze({
  predecessor: Object.freeze({
    sha256: '2848ef7a8dc4799de7faa46bcf304f4ac3d351da97be94b144a53f3300607f29',
    bytes: 1081331,
  }),
  candidate: Object.freeze({
    sha256: '5ec18cbe4cff7192d384e81d1010e0133d357d44ff17fa65821e1489c4fd1ee3',
    bytes: 1081335,
  }),
});

function fail(message) {
  throw new Error(message);
}

function unfoldSqlcl(text) {
  const complete = line => {
    if (line.startsWith('PMLE_DECPS_ARTIFACT|')) {
      return /\|phase=dual-clock$/.test(line);
    }
    if (line.startsWith('PMLE_LIVE_REPLAY_TIC|')) {
      return /\|clock_suspect=[01]$/.test(line);
    }
    if (line.startsWith('PMLE_LIVE_REPLAY_CLOCK|')) {
      return /\|verdict=(?:PASS|FAIL)$/.test(line);
    }
    if (line.startsWith('PMLE_LIVE_REPLAY_TICKER|')) {
      return /\|monotonic_tps=[0-9.]+$/.test(line);
    }
    if (line.startsWith('PMLE_LIVE_REPLAY_WINDOW|')) {
      return /\|rejectBytes=[0-9]+$/.test(line);
    }
    return true;
  };
  const physical = text.split(/\r?\n/);
  const logical = [];
  for (let index = 0; index < physical.length; index += 1) {
    let line = physical[index];
    if (line.startsWith('PMLE_') && !complete(line)) {
      while (!complete(line)
          && index + 1 < physical.length
          && !physical[index + 1].startsWith('PMLE_')) {
        line += physical[index + 1];
        index += 1;
      }
    }
    logical.push(line);
  }
  return logical.join('\n');
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

function parse(text, identity, label) {
  const lines = unfoldSqlcl(text).split(/\r?\n/);
  const artifact = exactlyOne(
    lines,
    line => line.startsWith('PMLE_DECPS_ARTIFACT|'),
    `${label} artifact`,
  );
  if (artifact !==
      `PMLE_DECPS_ARTIFACT|sha256=${identity.sha256}|bytes=${identity.bytes}`
        + '|phase=dual-clock') {
    fail(`${label}: artifact identity mismatch`);
  }

  const samplePattern =
    /^PMLE_LIVE_REPLAY_TIC\|tic=([0-9]+)\|mle_ms=(-?[0-9.]+)/
      .source
    + String.raw`\|monotonic_ms=([0-9.]+)\|clock_delta_ms=([0-9.]+)`
    + String.raw`\|clock_suspect=([01])$`;
  const sampleRegex = new RegExp(samplePattern);
  const samples = lines
    .map((line, lineIndex) => {
      const match = line.match(sampleRegex);
      return match === null ? null : {
        lineIndex,
        tic: Number(match[1]),
        wallMs: Number(match[2]),
        monotonicMs: Number(match[3]),
        declaredDeltaMs: Number(match[4]),
        suspect: Number(match[5]),
      };
    })
    .filter(Boolean);
  if (samples.length !== tics) {
    fail(`${label}: expected ${tics} dual-clock samples, found ${samples.length}`);
  }
  for (let index = 0; index < samples.length; index += 1) {
    const row = samples[index];
    const delta = Math.abs(row.wallMs - row.monotonicMs);
    const expectedSuspect = delta > disagreementLimitMs ? 1 : 0;
    if (row.tic !== index + 1
        || !Number.isFinite(row.wallMs)
        || !Number.isFinite(row.monotonicMs)
        || row.monotonicMs < 0
        || Math.abs(delta - row.declaredDeltaMs) > 0.0011
        || row.suspect !== expectedSuspect) {
      fail(`${label}: invalid dual-clock sample at tic ${index + 1}`);
    }
  }
  const suspects = samples.filter(row => row.suspect === 1);
  if (suspects.length > maximumSuspects) {
    fail(
      `${label}: ${suspects.length} clock suspects exceed ${maximumSuspects}`
        + ` (samples=${suspects.map(
          row => `${row.tic}:${row.wallMs}/${row.monotonicMs}`,
        ).join(',')})`,
    );
  }
  const clock = exactlyOne(
    lines,
    line => line.startsWith('PMLE_LIVE_REPLAY_CLOCK|'),
    `${label} clock terminal`,
  );
  if (clock !==
      `PMLE_LIVE_REPLAY_CLOCK|tics=${tics}`
        + `|disagreement_limit_ms=${disagreementLimitMs}`
        + `|suspects=${suspects.length}|maximum_suspects=${maximumSuspects}`
        + '|verdict=PASS') {
    fail(`${label}: clock terminal disagrees with samples`);
  }

  const ticker = exactlyOne(
    lines,
    line => line.startsWith('PMLE_LIVE_REPLAY_TICKER|'),
    `${label} ticker terminal`,
  );
  if (!ticker.startsWith(
    `PMLE_LIVE_REPLAY_TICKER|stream=${stream}|tics=${tics}|`,
  )) {
    fail(`${label}: ticker stream/tic count mismatch`);
  }
  const windows = lines
    .map((line, lineIndex) => {
      const match = line.match(
        /^PMLE_LIVE_REPLAY_WINDOW\|through_tic=([0-9]+)\|tics=([0-9]+)/
          .source
        + String.raw`\|wall_ms=(-?[0-9.]+)`
        + String.raw`\|monotonic_centiseconds=([0-9]+)`
        + String.raw`\|monotonic_tps=([0-9.]+)\|memory=`,
      );
      return match === null ? null : {
        lineIndex,
        through: Number(match[1]),
        count: Number(match[2]),
        centiseconds: Number(match[4]),
        declaredTps: Number(match[5]),
      };
    })
    .filter(Boolean);
  if (windows.length !== 53) {
    fail(`${label}: expected 53 monotonic windows, found ${windows.length}`);
  }
  let windowTics = 0;
  let windowCentiseconds = 0;
  for (let index = 0; index < windows.length; index += 1) {
    const window = windows[index];
    const expectedCount = index === windows.length - 1 ? 50 : 100;
    windowTics += window.count;
    windowCentiseconds += window.centiseconds;
    const calculatedTps = window.count * 100 / window.centiseconds;
    if (window.count !== expectedCount
        || window.through !== windowTics
        || window.centiseconds <= 0
        || Math.abs(calculatedTps - window.declaredTps) > 0.0011) {
      fail(`${label}: invalid monotonic window ${index + 1}`);
    }
  }
  if (windowTics !== tics) {
    fail(`${label}: monotonic windows cover ${windowTics} tics`);
  }
  const artifactLine = lines.indexOf(artifact);
  const clockLine = lines.indexOf(clock);
  const tickerLine = lines.indexOf(ticker);
  if (artifactLine >= samples[0].lineIndex
      || clockLine <= samples[samples.length - 1].lineIndex
      || tickerLine <= clockLine
      || windows[0].lineIndex <= tickerLine) {
    fail(`${label}: artifact, samples, clock, ticker, and windows are out of order`);
  }

  const validWall = samples
    .filter(row => row.suspect === 0)
    .map(row => row.wallMs);
  return {
    suspectTics: suspects.map(row => row.tic),
    validCount: validWall.length,
    p50: nearestRank(validWall, 0.50),
    p95: nearestRank(validWall, 0.95),
    monotonicTps: windowTics * 100 / windowCentiseconds,
    windowCentiseconds,
  };
}

function compare(beforeText, afterText) {
  const before = parse(beforeText, identities.predecessor, 'predecessor');
  const after = parse(afterText, identities.candidate, 'candidate');
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
  const ticsText = values => values.length === 0 ? 'none' : values.join(',');
  return [
    'PMLE_DECPS_DUAL_CLOCK_INTEGRITY|PASS'
      + `|disagreement_limit_ms=${disagreementLimitMs}`
      + `|maximum_suspects=${maximumSuspects}`
      + `|predecessor_suspects=${result.before.suspectTics.length}`
      + `|predecessor_tics=${ticsText(result.before.suspectTics)}`
      + `|candidate_suspects=${result.after.suspectTics.length}`
      + `|candidate_tics=${ticsText(result.after.suspectTics)}`,
    'PMLE_DECPS_DUAL_CLOCK_RANK|PASS'
      + `|tics=${tics}`
      + `|predecessor_sha256=${identities.predecessor.sha256}`
      + `|candidate_sha256=${identities.candidate.sha256}`
      + `|predecessor_valid=${result.before.validCount}`
      + `|candidate_valid=${result.after.validCount}`
      + `|predecessor_p50_ms=${result.before.p50.toFixed(3)}`
      + `|candidate_p50_ms=${result.after.p50.toFixed(3)}`
      + `|p50_delta_pct=${result.p50Delta.toFixed(3)}`
      + `|predecessor_p95_ms=${result.before.p95.toFixed(3)}`
      + `|candidate_p95_ms=${result.after.p95.toFixed(3)}`
      + `|p95_delta_pct=${result.p95Delta.toFixed(3)}`
      + `|predecessor_monotonic_tps=${result.before.monotonicTps.toFixed(3)}`
      + `|candidate_monotonic_tps=${result.after.monotonicTps.toFixed(3)}`
      + '|promotion_limit_pct=5.000',
  ].join('\n');
}

function synthetic(identity, wallValue, suspectTic) {
  const lines = [
    `PMLE_DECPS_ARTIFACT|sha256=${identity.sha256}|bytes=${identity.bytes}`
      + '|phase=dual-clock',
  ];
  for (let tic = 1; tic <= tics; tic += 1) {
    const wall = tic === suspectTic
      ? (suspectTic % 2 === 0 ? -20 : 160)
      : wallValue;
    const monotonic = 100;
    const delta = Math.abs(wall - monotonic);
    lines.push(
      `PMLE_LIVE_REPLAY_TIC|tic=${tic}|mle_ms=${wall}`
        + `|monotonic_ms=${monotonic}|clock_delta_ms=${delta}`
        + `|clock_suspect=${delta > disagreementLimitMs ? 1 : 0}`,
    );
  }
  lines.push(
    `PMLE_LIVE_REPLAY_CLOCK|tics=${tics}`
      + `|disagreement_limit_ms=${disagreementLimitMs}|suspects=1`
      + `|maximum_suspects=${maximumSuspects}|verdict=PASS`,
    `PMLE_LIVE_REPLAY_TICKER|stream=${stream}|tics=${tics}`
      + '|p50_ms=1|p95_ms=1|p99_ms=1|max_ms=1|throughput_tps=1'
      + '|monotonic_centiseconds=52500|monotonic_tps=10',
  );
  for (let start = 0; start < tics; start += 100) {
    const count = Math.min(100, tics - start);
    lines.push(
      `PMLE_LIVE_REPLAY_WINDOW|through_tic=${start + count}|tics=${count}`
        + `|wall_ms=${count * 100}|monotonic_centiseconds=${count * 10}`
        + '|monotonic_tps=10|memory=synthetic',
    );
  }
  return lines.join('\n');
}

function selfTest() {
  const before = synthetic(identities.predecessor, 100, 2);
  const after = synthetic(identities.candidate, 104, 3);
  const result = compare(before, after);
  if (result.p50Delta !== 4 || result.p95Delta !== 4
      || result.before.monotonicTps !== 10
      || result.after.monotonicTps !== 10) {
    fail('dual-clock comparator positive self-test failed');
  }
  const rejected = (beforeMutation, afterMutation, expected) => {
    const directory = fs.mkdtempSync(
      path.join(os.tmpdir(), 'pmle-dual-clock-selftest-'),
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
      if (child.status === 0 || !child.stderr.includes(expected)) {
        fail(`adversarial self-test was not rejected: ${expected}`);
      }
    } finally {
      fs.rmSync(directory, {recursive: true, force: true});
    }
  };
  const same = value => value;
  rejected(
    same,
    value => value.replace('|clock_suspect=0', '|clock_suspect=1'),
    'invalid dual-clock sample',
  );
  rejected(
    same,
    value => value.replace('|monotonic_tps=10|memory=', '|monotonic_tps=9|memory='),
    'invalid monotonic window',
  );
  rejected(
    same,
    value => value.replaceAll(
      '|mle_ms=104|monotonic_ms=100|clock_delta_ms=4|',
      '|mle_ms=106|monotonic_ms=100|clock_delta_ms=6|',
    ),
    'exceeds 5% promotion rule',
  );
  rejected(
    same,
    value => value.replace(identities.candidate.sha256, '0'.repeat(64)),
    'artifact identity mismatch',
  );
  console.log('PASS PMLE-DECPS-DUAL-CLOCK-COMPARATOR-SELF-TEST');
}

if (process.argv[2] === '--self-test') {
  selfTest();
} else {
  if (!process.argv[2] || !process.argv[3]) {
    fail(
      'usage: compare-decps-dual-clock-rank.mjs '
        + 'PREDECESSOR_LOG CANDIDATE_LOG | --self-test',
    );
  }
  console.log(render(compare(
    fs.readFileSync(process.argv[2], 'utf8'),
    fs.readFileSync(process.argv[3], 'utf8'),
  )));
}
