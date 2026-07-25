import fs from 'node:fs';

function artifact(text, marker, rankMarker, label) {
  const lines = text.split(/\r?\n/);
  const rows = lines.filter(line => line.startsWith(`${marker}|`));
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
  const rankIndex = lines.findIndex(
    line => line.startsWith(`${rankMarker}|`),
  );
  if (rankIndex < 0 || lines.indexOf(rows[0]) >= rankIndex) {
    throw new Error(`${label}: artifact marker does not precede rank terminal`);
  }
  return fields;
}

function row(text, marker, label) {
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
    throw new Error(`${label}: missing or ambiguous classification`);
  }
  const samples = Number(fields.samples);
  const warmup = Number(fields.warmup);
  if (![100, 300].includes(samples) || warmup !== samples / 10
      || Number(fields.unique) !== samples
      || Number(fields.frontier) !== samples + warmup
      || fields.frame_bytes !== '64000'
      || !/^[0-9a-f]{64}$/.test(fields.chain_sha256 ?? '')) {
    throw new Error(`${label}: invalid exact-frame corpus`);
  }
  const bindTiming = fields.transport !== undefined;
  const timingNames = bindTiming
    ? [
      'step_p50_ms', 'step_p95_ms',
      'persist_p50_ms', 'persist_p95_ms', 'persist_p99_ms',
      'pipeline_p50_ms', 'pipeline_p95_ms', 'pipeline_p99_ms',
    ]
    : [
      'step_p50_ms', 'step_p95_ms',
      'render_p50_ms', 'render_p95_ms', 'render_p99_ms',
      'egress_p50_ms', 'egress_p95_ms',
      'total_p50_ms', 'total_p95_ms', 'total_p99_ms',
      'pipeline_p50_ms', 'pipeline_p95_ms', 'pipeline_p99_ms',
    ];
  const timings = Object.fromEntries(
    timingNames.map(name => [name, Number(fields[name])]),
  );
  if (!Object.values(timings)
      .every(value => Number.isFinite(value) && value > 0)) {
    throw new Error(`${label}: invalid timing record`);
  }
  const pipelineP50 = timings.pipeline_p50_ms;
  const pipelineP95 = timings.pipeline_p95_ms;
  const pipelineP99 = timings.pipeline_p99_ms;
  const invalidOrdering = bindTiming
    ? (
      timings.step_p50_ms > timings.step_p95_ms
      || timings.persist_p50_ms > timings.persist_p95_ms
      || timings.persist_p95_ms > timings.persist_p99_ms
      || pipelineP50 > pipelineP95 || pipelineP95 > pipelineP99
      || pipelineP50 < Math.max(
        timings.step_p50_ms, timings.persist_p50_ms)
      || pipelineP95 < Math.max(
        timings.step_p95_ms, timings.persist_p95_ms)
    )
    : (
      timings.step_p50_ms > timings.step_p95_ms
      || timings.render_p50_ms > timings.render_p95_ms
      || timings.render_p95_ms > timings.render_p99_ms
      || timings.egress_p50_ms > timings.egress_p95_ms
      || timings.total_p50_ms > timings.total_p95_ms
      || timings.total_p95_ms > timings.total_p99_ms
      || pipelineP50 > pipelineP95 || pipelineP95 > pipelineP99
      || pipelineP50 < Math.max(
        timings.step_p50_ms, timings.total_p50_ms)
      || pipelineP95 < Math.max(
        timings.step_p95_ms, timings.total_p95_ms)
    );
  if (invalidOrdering) {
    throw new Error(`${label}: non-monotonic or impossible timing record`);
  }
  const verdict = pipelineP95 <= 33.333 ? 'PASS' : 'FAIL';
  if (fields.exact_30fps !== verdict) {
    throw new Error(`${label}: false exact_30fps verdict`);
  }
  if (
    (fields.transport === 'direct_uint8array_blob_insert'
      && !['explicit_db_type_blob', 'implicit_target_blob']
        .includes(fields.direct_mode))
    || (fields.transport === 'persistent_returning_oracle_blob'
      && fields.direct_mode !== 'UNSUPPORTED')
  ) {
    throw new Error(`${label}: transport/capability mode mismatch`);
  }
  let temporaryLobs;
  if (fields.transport !== undefined) {
    if (fields.commit_per_frame !== 'YES') {
      throw new Error(`${label}: frame persistence is not commit-qualified`);
    }
    const before = Number(fields.temporary_lobs_before);
    const after = Number(fields.temporary_lobs_after);
    const delta = Number(fields.temporary_lobs_delta);
    if (![before, after, delta].every(Number.isInteger)
        || before < 0 || after < 0 || delta !== after - before) {
      throw new Error(`${label}: invalid temporary-LOB telemetry`);
    }
    temporaryLobs = {before, after, delta};
  }
  return {
    fields,
    classification: classifications[0],
    pipelineP50,
    pipelineP95,
    pipelineP99,
    timings,
    temporaryLobs,
  };
}

function compare(rawText, bindText) {
  const rawArtifact = artifact(
    rawText,
    'PMLE_PRESENTATION_DECPS_ARTIFACT',
    'PMLE_PRESENTATION_FRAME_RANK',
    'raw',
  );
  const bindArtifact = artifact(
    bindText,
    'PMLE_PRESENTATION_BIND_ARTIFACT',
    'PMLE_PRESENTATION_BIND_RANK',
    'bind',
  );
  const raw = row(rawText, 'PMLE_PRESENTATION_FRAME_RANK', 'raw');
  const bind = row(bindText, 'PMLE_PRESENTATION_BIND_RANK', 'bind');
  const supportedTransports = [
    'direct_uint8array_blob_insert',
    'persistent_returning_oracle_blob',
  ];
  if (raw.classification !== 'DIAGNOSTIC_NOT_GATE'
      || bind.classification !== 'DIAGNOSTIC_NOT_GATE'
      || !supportedTransports.includes(bind.fields.transport)) {
    throw new Error('transport A/B cells are not comparable diagnostics');
  }
  for (const field of ['samples', 'warmup', 'frame_bytes', 'chain_sha256']) {
    if (raw.fields[field] !== bind.fields[field]) {
      throw new Error(`transport A/B ${field} mismatch`);
    }
  }
  for (const field of ['sha256', 'bytes']) {
    if (rawArtifact[field] !== bindArtifact[field]) {
      throw new Error(`transport A/B artifact ${field} mismatch`);
    }
  }
  return {raw, bind, artifact: bindArtifact};
}

function validateGate(text) {
  const gateArtifact = artifact(
    text,
    'PMLE_PRESENTATION_BIND_ARTIFACT',
    'PMLE_PRESENTATION_BIND_RANK',
    'bind gate',
  );
  const gate = row(text, 'PMLE_PRESENTATION_BIND_RANK', 'bind gate');
  const supportedTransports = [
    'direct_uint8array_blob_insert',
    'persistent_returning_oracle_blob',
  ];
  if (gate.classification !== 'ACCEPTANCE_GATE'
      || gate.fields.samples !== '300' || gate.fields.warmup !== '30'
      || !supportedTransports.includes(gate.fields.transport)
      || gate.fields.exact_30fps !== 'PASS'
      || gate.temporaryLobs?.delta !== 0) {
    throw new Error('300-frame bind acceptance gate failed');
  }
  return {...gate, artifact: gateArtifact};
}

if (process.argv[2] === '--self-test') {
  const chain = 'ef'.repeat(32);
  const raw = `PMLE_PRESENTATION_FRAME_RANK|DIAGNOSTIC_NOT_GATE`
    + `|samples=100|warmup=10|frame_bytes=64000|unique=100`
    + `|step_p50_ms=5|step_p95_ms=7`
    + `|render_p50_ms=20|render_p95_ms=30|render_p99_ms=35`
    + `|egress_p50_ms=5|egress_p95_ms=6`
    + `|total_p50_ms=30|total_p95_ms=40|total_p99_ms=45`
    + `|pipeline_p50_ms=40|pipeline_p95_ms=50|pipeline_p99_ms=60`
    + `|exact_30fps=FAIL|chain_sha256=${chain}|frontier=110\n`;
  const bind = `PMLE_PRESENTATION_BIND_RANK|DIAGNOSTIC_NOT_GATE`
    + `|transport=persistent_returning_oracle_blob|samples=100|warmup=10`
    + `|direct_mode=UNSUPPORTED`
    + `|commit_per_frame=YES`
    + `|frame_bytes=64000|unique=100`
    + `|step_p50_ms=5|step_p95_ms=7`
    + `|persist_p50_ms=10|persist_p95_ms=15|persist_p99_ms=18`
    + `|pipeline_p50_ms=20`
    + `|pipeline_p95_ms=30|pipeline_p99_ms=32|exact_30fps=PASS`
    + `|temporary_lobs_before=0|temporary_lobs_after=0`
    + `|temporary_lobs_delta=0`
    + `|chain_sha256=${chain}|frontier=110\n`;
  const artifactSha = 'ab'.repeat(32);
  const withArtifact = (marker, body) =>
    `${marker}|sha256=${artifactSha}|bytes=123456`
    + `|classification=UNPROMOTED_CANDIDATE\n${body}`;
  const rawEvidence = withArtifact(
    'PMLE_PRESENTATION_DECPS_ARTIFACT', raw);
  const bindEvidence = withArtifact(
    'PMLE_PRESENTATION_BIND_ARTIFACT', bind);
  const result = compare(rawEvidence, bindEvidence);
  if (result.raw.pipelineP95 / result.bind.pipelineP95 !== 5 / 3) {
    throw new Error('transport speedup self-test failed');
  }
  let rejected = false;
  try {
    compare(
      rawEvidence,
      bindEvidence.replace('exact_30fps=PASS', 'exact_30fps=FAIL'),
    );
  } catch {
    rejected = true;
  }
  if (!rejected) throw new Error('false bind verdict was accepted');
  rejected = false;
  try {
    row(bind.replace(
      '|exact_30fps=PASS|',
      '|exact_30fps=FAIL|exact_30fps=PASS|',
    ), 'PMLE_PRESENTATION_BIND_RANK', 'duplicate-self-test');
  } catch {
    rejected = true;
  }
  if (!rejected) throw new Error('duplicate transport field was accepted');
  rejected = false;
  try {
    row(bind.replace('pipeline_p99_ms=32', 'pipeline_p99_ms=29'),
      'PMLE_PRESENTATION_BIND_RANK', 'ordering-self-test');
  } catch {
    rejected = true;
  }
  if (!rejected) throw new Error('non-monotonic timing was accepted');
  validateGate(withArtifact('PMLE_PRESENTATION_BIND_ARTIFACT', bind
    .replace('DIAGNOSTIC_NOT_GATE', 'ACCEPTANCE_GATE')
    .replaceAll('100', '300')
    .replaceAll('warmup=10', 'warmup=30')
    .replaceAll('frontier=110', 'frontier=330')));
  rejected = false;
  try {
    validateGate(withArtifact('PMLE_PRESENTATION_BIND_ARTIFACT', bind
      .replace('DIAGNOSTIC_NOT_GATE', 'ACCEPTANCE_GATE')
      .replaceAll('100', '300')
      .replaceAll('warmup=10', 'warmup=30')
      .replaceAll('frontier=110', 'frontier=330')
      .replace('temporary_lobs_after=0', 'temporary_lobs_after=1')
      .replace('temporary_lobs_delta=0', 'temporary_lobs_delta=1')));
  } catch {
    rejected = true;
  }
  if (!rejected) throw new Error('temporary-LOB growth was accepted');
  rejected = false;
  try {
    validateGate(bind
      .replace('DIAGNOSTIC_NOT_GATE', 'ACCEPTANCE_GATE')
      .replaceAll('100', '300')
      .replaceAll('warmup=10', 'warmup=30')
      .replaceAll('frontier=110', 'frontier=330'));
  } catch {
    rejected = true;
  }
  if (!rejected) throw new Error('unbound transport gate was accepted');
  rejected = false;
  try {
    validateGate(withArtifact('PMLE_PRESENTATION_BIND_ARTIFACT', bind
      .replace('DIAGNOSTIC_NOT_GATE', 'ACCEPTANCE_GATE')
      .replaceAll('100', '300')
      .replaceAll('warmup=10', 'warmup=30')
      .replaceAll('frontier=110', 'frontier=330'))
      .replace('|bytes=123456|', '|bytes=1|bytes=123456|'));
  } catch {
    rejected = true;
  }
  if (!rejected) {
    throw new Error('duplicate transport artifact field was accepted');
  }
  console.log('PASS PMLE-PRESENTATION-TRANSPORT-COMPARATOR-SELF-TEST');
} else if (process.argv[2] === '--gate') {
  const gateFile = process.argv[3];
  if (!gateFile) {
    throw new Error(
      'usage: compare-presentation-transport-rank.mjs --gate BIND_GATE_LOG',
    );
  }
  const gate = validateGate(fs.readFileSync(gateFile, 'utf8'));
  console.log(
    `PMLE_PRESENTATION_BIND_300_FRAME_GATE|PASS`
    + `|pipeline_p50_ms=${gate.pipelineP50}`
    + `|pipeline_p95_ms=${gate.pipelineP95}`
    + `|pipeline_p99_ms=${gate.pipelineP99}`
    + `|artifact_sha256=${gate.artifact.sha256}`
    + `|commit_per_frame=${gate.fields.commit_per_frame}`
    + `|temporary_lobs_before=${gate.temporaryLobs.before}`
    + `|temporary_lobs_after=${gate.temporaryLobs.after}`
    + `|temporary_lobs_delta=${gate.temporaryLobs.delta}`
    + `|chain_sha256=${gate.fields.chain_sha256}`,
  );
} else {
  const [, , rawFile, bindFile] = process.argv;
  if (!rawFile || !bindFile) {
    throw new Error(
      'usage: compare-presentation-transport-rank.mjs RAW_LOG BIND_LOG',
    );
  }
  const result = compare(
    fs.readFileSync(rawFile, 'utf8'),
    fs.readFileSync(bindFile, 'utf8'),
  );
  console.log(
    `PMLE_PRESENTATION_TRANSPORT_AB|PASS`
    + `|raw_pipeline_p50_ms=${result.raw.pipelineP50}`
    + `|raw_pipeline_p95_ms=${result.raw.pipelineP95}`
    + `|bind_pipeline_p50_ms=${result.bind.pipelineP50}`
    + `|bind_pipeline_p95_ms=${result.bind.pipelineP95}`
    + `|bind_transport=${result.bind.fields.transport}`
    + `|artifact_sha256=${result.artifact.sha256}`
    + `|p50_speedup=${(result.raw.pipelineP50 / result.bind.pipelineP50).toFixed(4)}`
    + `|p95_speedup=${(result.raw.pipelineP95 / result.bind.pipelineP95).toFixed(4)}`
    + `|bind_exact_30fps=${result.bind.fields.exact_30fps}`
    + `|bind_temporary_lobs_delta=${result.bind.temporaryLobs.delta}`
    + `|chain_sha256=${result.bind.fields.chain_sha256}`,
  );
}
