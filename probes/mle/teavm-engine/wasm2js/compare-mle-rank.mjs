import fs from 'node:fs';

const [baselinePath, candidatePath] = process.argv.slice(2);
const selfTest = baselinePath === '--self-test';

function samples(text, prefix, expected) {
  const result = [...text.matchAll(
    new RegExp(`^${prefix}\\|tic=([0-9]+)\\|mle_ms=([0-9.]+)$`, 'gm'),
  )].map(match => ({tic: Number(match[1]), ms: Number(match[2])}));
  if (result.length !== expected) {
    throw new Error(`${prefix}: expected ${expected} samples, found ${result.length}`);
  }
  result.forEach((sample, index) => {
    if (sample.tic !== index + 1 || !Number.isFinite(sample.ms)
        || sample.ms <= 0) {
      throw new Error(`${prefix}: invalid tic sample at ${index + 1}`);
    }
  });
  return result;
}

function one(text, prefix, label) {
  const rows = text.split(/\r?\n/).filter(line => line.startsWith(prefix));
  if (rows.length !== 1) {
    throw new Error(`${label}: expected one ${prefix}, found ${rows.length}`);
  }
  return rows[0];
}

function fields(line, label) {
  const entries = line.split('|').slice(1).map(part => {
    const separator = part.indexOf('=');
    return separator < 1
      ? [part, '']
      : [part.slice(0, separator), part.slice(separator + 1)];
  });
  const names = entries.map(([name]) => name);
  if (new Set(names).size !== names.length) {
    throw new Error(`${label}: duplicate marker field`);
  }
  return Object.fromEntries(entries);
}

function rounded(value) {
  return Math.round(value * 1000) / 1000;
}

function percentile(rows, fraction) {
  const sorted = rows.map(row => row.ms)
    .toSorted((left, right) => left - right);
  return sorted[Math.ceil(sorted.length * fraction) - 1];
}

function rankSummary(text, rows) {
  const line = one(
    text,
    'PMLE_WASM2JS_MLE_RANK|PASS|stream=live-dm-2026-07-23|tics=5250|',
    'wasm2js rank terminal',
  );
  const parsed = fields(line, 'wasm2js rank terminal');
  const observed = {
    p50: Number(parsed.p50_ms),
    p95: Number(parsed.p95_ms),
    p99: Number(parsed.p99_ms),
    max: Number(parsed.max_ms),
    throughput: Number(parsed.throughput_tps),
  };
  if (!Object.values(observed).every(value =>
    Number.isFinite(value) && value > 0)
      || observed.p50 > observed.p95
      || observed.p95 > observed.p99
      || observed.p99 > observed.max
      || observed.p50 !== rounded(percentile(rows, 0.50))
      || observed.p95 !== rounded(percentile(rows, 0.95))
      || observed.p99 !== rounded(percentile(rows, 0.99))
      || observed.max !== rounded(Math.max(...rows.map(row => row.ms)))) {
    throw new Error('wasm2js rank terminal is inconsistent with tic samples');
  }
  return observed;
}

function memoryWindows(text, rows) {
  const matches = [...text.matchAll(
    /^PMLE_WASM2JS_MLE_WINDOW\|through_tic=([0-9]+)\|tics=([0-9]+)\|wall_ms=([0-9.]+)\|memory=linear_memory_bytes=([0-9]+)$/gm,
  )];
  const expected = Math.ceil(rows.length / 100);
  if (matches.length !== expected) {
    throw new Error(
      `wasm2js memory windows: expected ${expected}, found ${matches.length}`,
    );
  }
  let previousMemory = 0;
  const memories = [];
  matches.forEach((match, index) => {
    const through = Number(match[1]);
    const count = Number(match[2]);
    const wall = Number(match[3]);
    const memory = Number(match[4]);
    const expectedThrough = Math.min((index + 1) * 100, rows.length);
    const expectedCount = index === expected - 1 && rows.length % 100 !== 0
      ? rows.length % 100
      : 100;
    if (through !== expectedThrough || count !== expectedCount
        || !Number.isFinite(wall) || wall <= 0
        || !Number.isSafeInteger(memory) || memory <= 0
        || memory < previousMemory) {
      throw new Error(`wasm2js memory window ${index + 1} is invalid`);
    }
    previousMemory = memory;
    memories.push(memory);
  });
  return {minimum: memories[0], maximum: memories.at(-1)};
}

function artifact(text, prefix, label) {
  const parsed = fields(one(text, prefix, label), label);
  if (!/^[0-9a-f]{64}$/.test(parsed.sha256 ?? '')
      || !/^[1-9][0-9]*$/.test(parsed.bytes ?? '')) {
    throw new Error(`${label}: invalid artifact provenance`);
  }
  return {
    sha256: parsed.sha256,
    bytes: Number(parsed.bytes),
    fields: parsed,
  };
}

function median(values) {
  const sorted = values.toSorted((left, right) => left - right);
  const middle = Math.floor(sorted.length / 2);
  return sorted.length % 2 === 0
    ? (sorted[middle - 1] + sorted[middle]) / 2
    : sorted[middle];
}

function windows(values) {
  const result = [];
  for (let start = 0; start < values.length; start += 100) {
    result.push({
      through: Math.min(start + 100, values.length),
      median: median(values.slice(start, start + 100).map(row => row.ms)),
    });
  }
  return result;
}

function compare(baselineText, candidateText) {
  const expected = 5250;
  const baselineSamples = samples(
    baselineText,
    'PMLE_LIVE_REPLAY_TIC',
    expected,
  );
  const candidateSamples = samples(
    candidateText,
    'PMLE_WASM2JS_MLE_TIC',
    expected,
  );
  const baselineArtifact = artifact(
    baselineText,
    'PMLE_DECPS_ARTIFACT|',
    'de-CPS baseline artifact',
  );
  if (baselineArtifact.sha256 !==
      '5ec18cbe4cff7192d384e81d1010e0133d357d44ff17fa65821e1489c4fd1ee3'
      || baselineArtifact.bytes !== 1081335
      || baselineArtifact.fields.phase !== 'interpreter') {
    throw new Error('de-CPS baseline artifact is not the approved rank parent');
  }
  const baselineLines = baselineText.split(/\r?\n/);
  const baselineArtifactIndex = baselineLines.findIndex(
    line => line.startsWith('PMLE_DECPS_ARTIFACT|'),
  );
  const baselineSampleIndexes = baselineLines
    .map((line, index) => line.startsWith('PMLE_LIVE_REPLAY_TIC|')
      ? index : -1)
    .filter(index => index >= 0);
  const baselineTickerPrefix =
    `PMLE_LIVE_REPLAY_TICKER|stream=live-dm-2026-07-23|tics=${expected}|`;
  const baselineTickerIndexes = baselineLines
    .map((line, index) => line.startsWith(baselineTickerPrefix) ? index : -1)
    .filter(index => index >= 0);
  if (baselineArtifactIndex < 0
      || baselineArtifactIndex >= baselineSampleIndexes[0]
      || baselineTickerIndexes.length !== 1
      || baselineTickerIndexes[0] <= baselineSampleIndexes.at(-1)) {
    throw new Error('de-CPS baseline artifact, samples, and terminal are out of order');
  }
  const candidateArtifact = artifact(
    candidateText,
    'PMLE_WASM2JS_MLE_ARTIFACT|',
    'wasm2js candidate artifact',
  );
  if (candidateArtifact.fields.classification !== 'UNPROMOTED_CANDIDATE') {
    throw new Error('wasm2js candidate lacks its unpromoted classification');
  }
  rankSummary(candidateText, candidateSamples);
  const memory = memoryWindows(candidateText, candidateSamples);
  const parityLine = one(
    candidateText,
    'PMLE_WASM2JS_MLE_PARITY|PASS|tics=100|',
    'wasm2js MLE parity',
  );
  const rankLine = one(
    candidateText,
    'PMLE_WASM2JS_MLE_RANK|PASS|stream=live-dm-2026-07-23|tics=5250|',
    'wasm2js rank terminal',
  );
  const candidateLines = candidateText.split(/\r?\n/);
  const candidateArtifactIndex = candidateLines.findIndex(
    line => line.startsWith('PMLE_WASM2JS_MLE_ARTIFACT|'),
  );
  const parityIndex = candidateLines.indexOf(parityLine);
  const rankIndex = candidateLines.indexOf(rankLine);
  const candidateSampleIndexes = candidateLines
    .map((line, index) => line.startsWith('PMLE_WASM2JS_MLE_TIC|')
      ? index : -1)
    .filter(index => index >= 0);
  const memoryWindowIndexes = candidateLines
    .map((line, index) => line.startsWith('PMLE_WASM2JS_MLE_WINDOW|')
      ? index : -1)
    .filter(index => index >= 0);
  if (candidateArtifactIndex < 0
      || candidateArtifactIndex >= parityIndex
      || parityIndex >= candidateSampleIndexes[0]
      || rankIndex <= candidateSampleIndexes.at(-1)
      || memoryWindowIndexes.some(index => index <= rankIndex)) {
    throw new Error(
      'wasm2js artifact, parity, samples, terminal, and windows are out of order',
    );
  }
  const baseline = windows(baselineSamples);
  const candidate = windows(candidateSamples);
  const peakIndex = baseline.reduce(
    (best, row, index) => row.median > baseline[best].median ? index : best,
    0,
  );
  const quietIndex = baseline.reduce(
    (best, row, index) => row.median < baseline[best].median ? index : best,
    0,
  );
  const result = {
    peak: {
      through: baseline[peakIndex].through,
      speedup: baseline[peakIndex].median / candidate[peakIndex].median,
    },
    quiet: {
      through: baseline[quietIndex].through,
      speedup: baseline[quietIndex].median / candidate[quietIndex].median,
    },
  };
  const minimum = Math.min(result.peak.speedup, result.quiet.speedup);
  const verdict = minimum >= 2
    ? 'INTEGRATE_COMPLETE_PARITY_BATTERY'
    : (minimum < 1.5
      ? 'REJECT_GENERATED_SHAPE'
      : 'ESCALATE_HYBRID_OR_CAPACITY_DECISION');
  return {
    ...result,
    minimum,
    verdict,
    candidateArtifact,
    memory,
  };
}

if (selfTest) {
  const baselineArtifact = 'PMLE_DECPS_ARTIFACT'
    + '|sha256=5ec18cbe4cff7192d384e81d1010e0133d357d44ff17fa65821e1489c4fd1ee3'
    + '|bytes=1081335|phase=interpreter';
  const baselineSamples = Array.from({length: 5250}, (_, index) =>
    `PMLE_LIVE_REPLAY_TIC|tic=${index + 1}|mle_ms=${
      index < 100 ? 100 : 20}`);
  const baseline = [
    baselineArtifact,
    ...baselineSamples,
    'PMLE_LIVE_REPLAY_TICKER|stream=live-dm-2026-07-23'
      + '|tics=5250|p50_ms=20|p95_ms=20',
  ].join('\n');
  const candidateSamples = Array.from({length: 5250}, (_, index) =>
    `PMLE_WASM2JS_MLE_TIC|tic=${index + 1}|mle_ms=${
      index < 100 ? 40 : 8}`);
  const candidateWindows = Array.from({length: 53}, (_, index) => {
      const through = Math.min((index + 1) * 100, 5250);
      const count = index === 52 ? 50 : 100;
      return `PMLE_WASM2JS_MLE_WINDOW|through_tic=${through}|tics=${count}`
        + `|wall_ms=${count * 8}|memory=linear_memory_bytes=65536`;
    });
  const candidate = [
    'PMLE_WASM2JS_MLE_ARTIFACT|sha256=' + 'cd'.repeat(32)
      + '|bytes=123456|classification=UNPROMOTED_CANDIDATE',
    'PMLE_WASM2JS_MLE_PARITY|PASS|tics=100|canonical_bytes=1'
      + '|canonical_sha256=' + 'ab'.repeat(32),
    ...candidateSamples,
    'PMLE_WASM2JS_MLE_RANK|PASS|stream=live-dm-2026-07-23'
      + '|tics=5250|p50_ms=8|p95_ms=8|p99_ms=40|max_ms=40'
      + '|throughput_tps=100',
    ...candidateWindows,
  ].join('\n');
  const result = compare(baseline, candidate);
  if (result.verdict !== 'INTEGRATE_COMPLETE_PARITY_BATTERY'
      || result.peak.speedup !== 2.5
      || result.quiet.speedup !== 2.5) {
    throw new Error('wasm2js MLE rank comparator self-test failed');
  }
  let rejected = false;
  try {
    compare(baseline, candidate.replace('|p95_ms=8|', '|p95_ms=9|'));
  } catch {
    rejected = true;
  }
  if (!rejected) {
    throw new Error('wasm2js comparator accepted a false terminal percentile');
  }
  rejected = false;
  try {
    compare(baseline, candidate.replace(
      '|through_tic=5250|tics=50|wall_ms=400'
        + '|memory=linear_memory_bytes=65536',
      '|through_tic=5250|tics=50|wall_ms=400'
        + '|memory=linear_memory_bytes=32768',
    ));
  } catch {
    rejected = true;
  }
  if (!rejected) {
    throw new Error('wasm2js comparator accepted shrinking linear memory');
  }
  rejected = false;
  try {
    const lines = candidate.split('\n');
    const rankIndex = lines.findIndex(
      line => line.startsWith('PMLE_WASM2JS_MLE_RANK|'),
    );
    const rank = lines.splice(rankIndex, 1)[0];
    lines.splice(2, 0, rank);
    compare(baseline, lines.join('\n'));
  } catch {
    rejected = true;
  }
  if (!rejected) {
    throw new Error('wasm2js comparator accepted out-of-order rank evidence');
  }
  console.log('PASS PMLE-WASM2JS-MLE-RANK-COMPARATOR-SELF-TEST');
} else {
  if (!baselinePath || !candidatePath) {
    throw new Error(
      'usage: compare-mle-rank.mjs DECPS_BASELINE_LOG WASM2JS_MLE_LOG',
    );
  }
  const result = compare(
    fs.readFileSync(baselinePath, 'utf8'),
    fs.readFileSync(candidatePath, 'utf8'),
  );
  console.log(
    `PMLE_WASM2JS_MLE_DECISION|PASS|peak_through_tic=${result.peak.through}`
    + `|candidate_sha256=${result.candidateArtifact.sha256}`
    + `|candidate_bytes=${result.candidateArtifact.bytes}`
    + `|linear_memory_min_bytes=${result.memory.minimum}`
    + `|linear_memory_max_bytes=${result.memory.maximum}`
    + `|peak_speedup=${result.peak.speedup.toFixed(4)}`
    + `|quiet_through_tic=${result.quiet.through}`
    + `|quiet_speedup=${result.quiet.speedup.toFixed(4)}`
    + `|minimum_speedup=${result.minimum.toFixed(4)}`
    + `|verdict=${result.verdict}`,
  );
}
