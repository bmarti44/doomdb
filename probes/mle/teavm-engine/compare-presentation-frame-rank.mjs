import fs from 'node:fs';

const marker = 'PMLE_PRESENTATION_FRAME_RANK';

function artifact(text, markerName, label) {
  const rows = text.split(/\r?\n/)
    .filter(line => line.startsWith(`${markerName}|`));
  if (rows.length !== 1) {
    throw new Error(`${label}: expected one ${markerName}, found ${rows.length}`);
  }
  const entries = rows[0].split('|').slice(1).map(field => {
    const separator = field.indexOf('=');
    if (separator < 1) {
      throw new Error(`${label}: malformed artifact field`);
    }
    return [field.slice(0, separator), field.slice(separator + 1)];
  });
  const names = entries.map(([name]) => name);
  if (new Set(names).size !== names.length
      || names.toSorted().join(',') !==
        'bytes,classification,sha256') {
    throw new Error(`${label}: artifact fields are not exact and unique`);
  }
  const fields = Object.fromEntries(entries);
  if (!/^[0-9a-f]{64}$/.test(fields.sha256 ?? '')
      || !/^[1-9][0-9]*$/.test(fields.bytes ?? '')
      || fields.classification !== 'UNPROMOTED_CANDIDATE') {
    throw new Error(`${label}: invalid presentation artifact provenance`);
  }
  const rankIndex = text.split(/\r?\n/)
    .findIndex(line => line.startsWith(`${marker}|`));
  const artifactIndex = text.split(/\r?\n/).indexOf(rows[0]);
  if (rankIndex < 0 || artifactIndex >= rankIndex) {
    throw new Error(`${label}: artifact marker does not precede rank terminal`);
  }
  return fields;
}

function parse(text, label) {
  const rows = text.split(/\r?\n/).filter(line => line.startsWith(`${marker}|`));
  if (rows.length !== 1) {
    throw new Error(`${label}: expected one ${marker}, found ${rows.length}`);
  }
  const entries = rows[0].split('|').slice(1).map(field => {
    const separator = field.indexOf('=');
    return separator < 1
      ? [field, '']
      : [field.slice(0, separator), field.slice(separator + 1)];
  });
  const names = entries.map(([name]) => name);
  if (new Set(names).size !== names.length) {
    throw new Error(`${label}: duplicate marker field`);
  }
  const fields = Object.fromEntries(entries);
  const classifications = ['DIAGNOSTIC_NOT_GATE', 'ACCEPTANCE_GATE']
    .filter(name => Object.hasOwn(fields, name));
  if (classifications.length !== 1) {
    throw new Error(`${label}: missing or ambiguous evidence classification`);
  }
  const samples = Number(fields.samples);
  const warmup = Number(fields.warmup);
  const unique = Number(fields.unique);
  const frontier = Number(fields.frontier);
  if (!Number.isInteger(samples) || ![100, 300].includes(samples)
      || !Number.isInteger(warmup) || warmup !== samples / 10
      || unique !== samples || frontier !== samples + warmup
      || fields.frame_bytes !== '64000') {
    throw new Error(
      `${label}: invalid corpus samples=${fields.samples}`
      + ` warmup=${fields.warmup} frame_bytes=${fields.frame_bytes}`
      + ` unique=${fields.unique} frontier=${fields.frontier}`,
    );
  }
  if (!/^[0-9a-f]{64}$/.test(fields.chain_sha256 ?? '')) {
    throw new Error(`${label}: invalid frame chain`);
  }
  const numbers = {};
  for (const name of [
    'step_p50_ms', 'step_p95_ms',
    'render_p50_ms', 'render_p95_ms', 'render_p99_ms',
    'egress_p50_ms', 'egress_p95_ms',
    'total_p50_ms', 'total_p95_ms', 'total_p99_ms',
    'pipeline_p50_ms', 'pipeline_p95_ms', 'pipeline_p99_ms',
  ]) {
    numbers[name] = Number(fields[name]);
    if (!Number.isFinite(numbers[name]) || numbers[name] <= 0) {
      throw new Error(`${label}: invalid ${name}=${fields[name]}`);
    }
  }
  if (numbers.step_p50_ms > numbers.step_p95_ms
      || numbers.render_p50_ms > numbers.render_p95_ms
      || numbers.render_p95_ms > numbers.render_p99_ms
      || numbers.egress_p50_ms > numbers.egress_p95_ms
      || numbers.total_p50_ms > numbers.total_p95_ms
      || numbers.total_p95_ms > numbers.total_p99_ms
      || numbers.pipeline_p50_ms > numbers.pipeline_p95_ms
      || numbers.pipeline_p95_ms > numbers.pipeline_p99_ms
      || numbers.pipeline_p50_ms < Math.max(
        numbers.step_p50_ms, numbers.total_p50_ms)
      || numbers.pipeline_p95_ms < Math.max(
        numbers.step_p95_ms, numbers.total_p95_ms)) {
    throw new Error(`${label}: non-monotonic or impossible timing record`);
  }
  const recomputed = numbers.pipeline_p95_ms <= 33.333 ? 'PASS' : 'FAIL';
  if (fields.exact_30fps !== recomputed) {
    throw new Error(
      `${label}: exact_30fps=${fields.exact_30fps} recomputed ${recomputed}`,
    );
  }
  return {fields, numbers, classification: classifications[0]};
}

function compare(baselineText, candidateText) {
  const baselineArtifact = artifact(
    baselineText,
    'PMLE_PRESENTATION_BASELINE_ARTIFACT',
    'baseline',
  );
  const candidateArtifact = artifact(
    candidateText,
    'PMLE_PRESENTATION_DECPS_ARTIFACT',
    'candidate',
  );
  const baseline = parse(baselineText, 'baseline');
  const candidate = parse(candidateText, 'candidate');
  if (baseline.classification !== 'DIAGNOSTIC_NOT_GATE'
      || candidate.classification !== 'DIAGNOSTIC_NOT_GATE') {
    throw new Error('A/B rank cells are not diagnostic-classified');
  }
  if (baseline.fields.samples !== candidate.fields.samples
      || baseline.fields.warmup !== candidate.fields.warmup) {
    throw new Error('baseline/candidate corpus shape mismatch');
  }
  if (baseline.fields.chain_sha256 !== candidate.fields.chain_sha256) {
    throw new Error('baseline/candidate frame-chain mismatch');
  }
  return {
    baseline,
    candidate,
    baselineArtifact,
    candidateArtifact,
    p50Speedup:
      baseline.numbers.pipeline_p50_ms / candidate.numbers.pipeline_p50_ms,
    p95Speedup:
      baseline.numbers.pipeline_p95_ms / candidate.numbers.pipeline_p95_ms,
  };
}

function validateGate(text) {
  const gateArtifact = artifact(
    text,
    'PMLE_PRESENTATION_DECPS_ARTIFACT',
    'gate',
  );
  const gate = parse(text, 'gate');
  if (gate.classification !== 'ACCEPTANCE_GATE'
      || gate.fields.samples !== '300' || gate.fields.warmup !== '30'
      || gate.fields.exact_30fps !== 'PASS') {
    throw new Error(
      `300-frame gate failed: samples=${gate.fields.samples}`
      + ` warmup=${gate.fields.warmup}`
      + ` exact_30fps=${gate.fields.exact_30fps}`,
    );
  }
  return {...gate, artifact: gateArtifact};
}

if (process.argv[2] === '--self-test') {
  const chain = 'cd'.repeat(32);
  const row = (p50, p95, verdict, samples = 100,
    classification = 'DIAGNOSTIC_NOT_GATE') =>
    `${marker}|${classification}|samples=${samples}|warmup=${samples / 10}`
    + `|frame_bytes=64000|unique=${samples}|step_p50_ms=5|step_p95_ms=5`
    + `|render_p50_ms=${p50 - 10}|render_p95_ms=${p95 - 10}`
    + `|render_p99_ms=${p95 - 9}|egress_p50_ms=5|egress_p95_ms=5`
    + `|total_p50_ms=${p50 - 5}|total_p95_ms=${p95 - 5}`
    + `|total_p99_ms=${p95 + 1}|pipeline_p50_ms=${p50}`
    + `|pipeline_p95_ms=${p95}|pipeline_p99_ms=${p95 + 6}`
    + `|exact_30fps=${verdict}|chain_sha256=${chain}`
    + `|frontier=${samples + samples / 10}\n`;
  const provenance = (name, body, sha) =>
    `${name}|sha256=${sha.repeat(32)}|bytes=123456`
    + `|classification=UNPROMOTED_CANDIDATE\n${body}`;
  const baseline = body => provenance(
    'PMLE_PRESENTATION_BASELINE_ARTIFACT', body, 'ab');
  const candidate = body => provenance(
    'PMLE_PRESENTATION_DECPS_ARTIFACT', body, 'cd');
  const result = compare(
    baseline(row(80, 100, 'FAIL')),
    candidate(row(20, 30, 'PASS')),
  );
  if (result.p50Speedup !== 4 || result.p95Speedup !== 100 / 30) {
    throw new Error('valid comparator self-test failed');
  }
  let rejected = false;
  try {
    compare(
      baseline(row(80, 100, 'FAIL')),
      candidate(row(20, 34, 'PASS')),
    );
  } catch {
    rejected = true;
  }
  if (!rejected) throw new Error('false 30 FPS verdict was accepted');
  rejected = false;
  try {
    parse(row(20, 30, 'PASS').replace(
      '|exact_30fps=PASS|',
      '|exact_30fps=FAIL|exact_30fps=PASS|',
    ), 'duplicate-self-test');
  } catch {
    rejected = true;
  }
  if (!rejected) throw new Error('duplicate frame-rank field was accepted');
  rejected = false;
  try {
    parse(row(20, 30, 'PASS')
      .replace('pipeline_p99_ms=36', 'pipeline_p99_ms=29'),
    'ordering-self-test');
  } catch {
    rejected = true;
  }
  if (!rejected) throw new Error('non-monotonic frame timing was accepted');
  validateGate(candidate(
    row(20, 30, 'PASS', 300, 'ACCEPTANCE_GATE')));
  rejected = false;
  try {
    validateGate(candidate(
      row(20, 30, 'PASS', 300, 'ACCEPTANCE_GATE'))
      .replace(
        'PMLE_PRESENTATION_DECPS_ARTIFACT',
        'REMOVED_PRESENTATION_ARTIFACT',
      ));
  } catch {
    rejected = true;
  }
  if (!rejected) throw new Error('unbound frame gate was accepted');
  rejected = false;
  try {
    validateGate(candidate(
      row(20, 30, 'PASS', 300, 'ACCEPTANCE_GATE'))
      .replace('|bytes=123456|', '|bytes=1|bytes=123456|'));
  } catch {
    rejected = true;
  }
  if (!rejected) throw new Error('duplicate frame artifact field was accepted');
  console.log('PASS PMLE-PRESENTATION-FRAME-RANK-COMPARATOR-SELF-TEST');
} else {
  if (process.argv[2] === '--gate') {
    const gateFile = process.argv[3];
    if (!gateFile) {
      throw new Error(
        'usage: node compare-presentation-frame-rank.mjs --gate GATE_LOG',
      );
    }
    const gate = validateGate(fs.readFileSync(gateFile, 'utf8'));
    console.log(
      `PMLE_PRESENTATION_300_FRAME_GATE|PASS`
      + `|pipeline_p50_ms=${gate.numbers.pipeline_p50_ms}`
      + `|pipeline_p95_ms=${gate.numbers.pipeline_p95_ms}`
      + `|pipeline_p99_ms=${gate.numbers.pipeline_p99_ms}`
      + `|artifact_sha256=${gate.artifact.sha256}`
      + `|chain_sha256=${gate.fields.chain_sha256}`,
    );
    process.exit(0);
  }
  const [, , baselineFile, candidateFile] = process.argv;
  if (!baselineFile || !candidateFile) {
    throw new Error(
      'usage: node compare-presentation-frame-rank.mjs BASELINE CANDIDATE',
    );
  }
  const result = compare(
    fs.readFileSync(baselineFile, 'utf8'),
    fs.readFileSync(candidateFile, 'utf8'),
  );
  console.log(
    `PMLE_PRESENTATION_DECPS_AB|PASS`
    + `|baseline_pipeline_p50_ms=${result.baseline.numbers.pipeline_p50_ms}`
    + `|baseline_pipeline_p95_ms=${result.baseline.numbers.pipeline_p95_ms}`
    + `|candidate_pipeline_p50_ms=${result.candidate.numbers.pipeline_p50_ms}`
    + `|candidate_pipeline_p95_ms=${result.candidate.numbers.pipeline_p95_ms}`
    + `|p50_speedup=${result.p50Speedup.toFixed(4)}`
    + `|p95_speedup=${result.p95Speedup.toFixed(4)}`
    + `|candidate_exact_30fps=${result.candidate.fields.exact_30fps}`
    + `|candidate_sha256=${result.candidateArtifact.sha256}`
    + `|chain_sha256=${result.candidate.fields.chain_sha256}`,
  );
}
