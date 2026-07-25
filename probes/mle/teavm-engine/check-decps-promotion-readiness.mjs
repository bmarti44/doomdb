#!/usr/bin/env node

import { createHash } from 'node:crypto';
import { readFileSync } from 'node:fs';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { spawnSync } from 'node:child_process';

const here = dirname(fileURLToPath(import.meta.url));
const root = resolve(here, '../../..');

const candidateSha =
  '5ec18cbe4cff7192d384e81d1010e0133d357d44ff17fa65821e1489c4fd1ee3';
const candidateBytes = 1081335;
const ledgerProvenPredecessorSha =
  '2848ef7a8dc4799de7faa46bcf304f4ac3d351da97be94b144a53f3300607f29';
const tableSha =
  '058cd0df9444131b356762a096fd422d5131ac3aea91163aee056e8ad4965b44';
const oracleSha =
  '2a102cb47626108d37127358ca18a34925709914606e8d89d04be22d0d72da74';
// Keep the retiring SHA out of the repository-wide literal scan itself.
const retiringSha =
  'e485b9418e5845b78e9e1593918d8bbb' +
  '6f3c441c41a43cb8f3faf046e595148b';
const retiringArtifact =
  'doom-mle-authority-' + 'e485b9418e58' + '.js';
const retiringBytes = 1170000 + 1896;
const retiringMochaSha =
  '42b25147133bb5c84c3b19c1511583bb' +
  'd36219fb2a68996244106f40078f943e';
const retiringInputSha =
  '631f3d7657b3b9521ed800d1b4ec518d' +
  '4b6f102e5bf2a9f3e7caf1cb45624ecd';

const paths = {
  candidate:
    'artifacts/performance/pmle-decps-rank/' +
    'authority-candidate-5ec18cbe4cff.js',
  nodeParity:
    'artifacts/performance/pmle-decps-rank/' +
    'node-parity-5ec18cbe4cff-vs-2848ef7a8dc4.log',
  mleRank:
    'artifacts/performance/pmle-decps-rank/' +
    'interpreter-5ec18cbe4cff-5250.log',
  mleRankComparison:
    'artifacts/performance/pmle-decps-rank/' +
    'rank-comparison-2848ef7a-vs-5ec18cbe-2026-07-25.log',
  dualClockPredecessor:
    'artifacts/performance/pmle-decps-rank/' +
    'dual-clock-2848ef7a8dc4-5250.log',
  dualClockCandidate:
    'artifacts/performance/pmle-decps-rank/' +
    'dual-clock-5ec18cbe4cff-5250.log',
  dualClockComparison:
    'artifacts/performance/pmle-decps-rank/' +
    'dual-clock-comparison-2848ef7a-vs-5ec18cbe-2026-07-25.log',
  identityClassification:
    'artifacts/performance/pmle-decps-rank/' +
    'identity-break-classification-2026-07-25.md',
  rebuild:
    'artifacts/performance/pmle-decps-rank/' +
    'rebuild-5ec18cbe4cff.log',
  canonical:
    'artifacts/performance/pmle-differentials/' +
    'canonical-decps-reproducible-5ec18cbe-2026-07-25.log',
  coop:
    'artifacts/performance/pmle-differentials/' +
    'coop-decps-reproducible-5ec18cbe-2026-07-25.log',
  membership:
    'artifacts/performance/pmle-differentials/' +
    'membership-decps-reproducible-5ec18cbe-2026-07-25.log',
  ledger:
    'artifacts/performance/pmle-ledger-every-tic/' +
    'run-decps-reproducible-5ec18cbe-2026-07-25.log',
  ledgerPostflight:
    'artifacts/performance/pmle-ledger-every-tic/' +
    'run-decps-reproducible-5ec18cbe-2026-07-25-postflight.log',
};

// These files describe completed measurements. Promotion must never rewrite them.
const historicalRetiringRefs = new Set([
  'artifacts/performance/pmle-decps-rank/REPORT.md',
  'artifacts/performance/pmle-decps-rank/node-parity-2848ef7a8dc4.log',
  'artifacts/performance/pmle-differentials/canonical-warm-restore-e485-2026-07-24.log',
  'artifacts/performance/pmle-differentials/coop-warm-restore-e485-2026-07-24.log',
  'artifacts/performance/pmle-differentials/membership-warm-restore-e485-2026-07-24.log',
  'artifacts/performance/pmle-ledger-every-tic/run-decps-2848ef7a-2026-07-24-postflight.log',
  'artifacts/performance/pmle-ledger-every-tic/run-decps-reproducible-5ec18cbe-2026-07-25-postflight.log',
  'artifacts/performance/pmle-warm-restore-ab/REPORT.md',
  'artifacts/performance/pmle-worker-soak/checkpoint-cadence-decision-2026-07-24.md',
  'probes/mle/teavm-engine/run-decps-promotion-gates.sh',
  'probes/mle/teavm-engine/run-ledger-component-ab.sh',
  'probes/mle/teavm-engine/deploy-decps-authority.sh',
  'probes/mle/teavm-engine/attest-decps-ledger-postflight.sh',
  'probes/mle/teavm-engine/run-decps-simple-jit.sh',
  'scripts/build-decps-lifecycle-manifest.mjs',
  'scripts/set-decps-deployment-state.mjs',
]);

// These are live packaging, deployment, runtime, fixture, or verification pins.
const runtimeRetiringRefs = new Set([
  'client/dist/mle-status.json',
  'client/dist/play/teavm-browser.js',
  'client/src/teavm-browser.ts',
  'client/staging/mle-status.json',
  'client/staging/teavm-browser.js',
  'deploy/cloud/t11.1/catalog-observation.sql',
  'deploy/cloud/t11.1/source-policy.json',
  'probes/mle/teavm-engine/benchmark-warm-restore-mle.sql',
  'probes/mle/teavm-engine/load-mle-module.sh',
  'probes/mle/teavm-engine/membership-recovery-differential.sql',
  'probes/mle/teavm-engine/package-browser-assets.sh',
  'probes/mle/teavm-engine/run-ledger-differential.sh',
  'scripts/t11.1-deployment-manifest.mjs',
  'sql/sim/088_mle_match_runtime.sql',
  'tests/verify-pmle-source.sh',
  'tests/verify-t11.1-source.sh',
  'versions.lock',
]);

const historicalRetiringArtifactRefs = new Set([
  'probes/mle/teavm-engine/deploy-decps-authority.sh',
  'probes/mle/teavm-engine/run-ledger-component-ab.sh',
]);

const runtimeRetiringArtifactRefs = new Set([
  'client/dist/play/teavm-browser.js',
  'client/src/teavm-browser.ts',
  'client/staging/teavm-browser.js',
  'probes/mle/teavm-engine/load-mle-module.sh',
  'probes/mle/teavm-engine/load-tic0-checkpoint-bank.sh',
  'probes/mle/teavm-engine/package-browser-assets.sh',
  'probes/mle/teavm-engine/profile-checkpoint-node.mjs',
  'probes/mle/teavm-engine/profile-command-stream-node.mjs',
  'probes/mle/teavm-engine/run-javascript-candidate-parity.mjs',
  'probes/mle/teavm-engine/wasm2js/run-node-parity.mjs',
]);

const historicalRetiringByteRefs = new Set([
  'artifacts/performance/pmle-differentials/canonical-warm-restore-e485-2026-07-24.log',
  'artifacts/performance/pmle-differentials/coop-warm-restore-e485-2026-07-24.log',
  'artifacts/performance/pmle-differentials/membership-warm-restore-e485-2026-07-24.log',
  'artifacts/performance/pmle-ledger-every-tic/run-decps-2848ef7a-2026-07-24-postflight.log',
  'artifacts/performance/pmle-ledger-every-tic/run-decps-reproducible-5ec18cbe-2026-07-25-postflight.log',
  'probes/mle/teavm-engine/deploy-decps-authority.sh',
  'probes/mle/teavm-engine/attest-decps-ledger-postflight.sh',
  'scripts/set-decps-deployment-state.mjs',
]);

const runtimeRetiringByteRefs = new Set([
  'client/dist/mle-status.json',
  'client/staging/mle-status.json',
  'deploy/cloud/t11.1/catalog-observation.sql',
  'deploy/cloud/t11.1/source-policy.json',
  'probes/mle/teavm-engine/load-mle-module.sh',
  'probes/mle/teavm-engine/run-ledger-differential.sh',
  'scripts/t11.1-build-evidence.mjs',
  'scripts/t11.1-deployment-manifest.mjs',
  'tests/verify-t11.1-source.sh',
  'versions.lock',
]);

const historicalRetiringMochaRefs = new Set([
  'PLAN.md',
  'artifacts/performance/pmle-browser-replica/presentation-pin-lineage-2026-07-24.md',
  'artifacts/performance/pmle-init-diet/promotion-a942cd2d-2026-07-23.log',
  'artifacts/performance/pmle-live-tic/full-ab-2026-07-24/REPORT.md',
  'artifacts/performance/pmle-live-tic/full-ab-2026-07-24/build-sha256.txt',
  'artifacts/performance/pmle-live-tic/full-ab-2026-07-24/full-build.log',
  'artifacts/performance/pmle-worker-soak/checkpoint-index-map-build-2026-07-24.log',
  'artifacts/performance/pmle-worker-soak/checkpoint-index-map-promotion-build-2026-07-24.log',
  'probes/mle/teavm-engine/REPORT.md',
]);

const runtimeRetiringMochaRefs = new Set([
  'client/dist/mle-status.json',
  'client/staging/mle-status.json',
  'tests/verify-pmle-source.sh',
  'tests/verify-t11.1-source.sh',
  'versions.lock',
]);
const historicalRetiringInputRefs = new Set([
  'artifacts/performance/pmle-decps-rank/REPORT.md',
  'probes/mle/teavm-engine/promote-decps-authority.mjs',
]);
const runtimeRetiringInputRefs = new Set([
  'client/dist/mle-status.json',
  'client/staging/mle-status.json',
  'tests/verify-pmle-source.sh',
  'tests/verify-t11.1-source.sh',
  'versions.lock',
]);

function fail(message) {
  throw new Error(message);
}

function read(relativePath) {
  return readFileSync(resolve(root, relativePath), 'utf8');
}

function strictLines(text, prefix) {
  return text
    .split(/\r?\n/)
    .filter((line) => line.startsWith(prefix));
}

function exactlyOne(text, prefix, label) {
  const lines = strictLines(text, prefix);
  if (lines.length !== 1) {
    fail(`${label}: expected exactly one ${prefix} line, found ${lines.length}`);
  }
  return lines[0];
}

function requireParts(line, parts, label) {
  for (const part of parts) {
    if (!line.includes(part)) {
      fail(`${label}: marker is missing ${part}`);
    }
  }
}

function exactlyOneRegex(text, pattern, label) {
  const matches = [...text.matchAll(pattern)];
  if (matches.length !== 1) {
    fail(`${label}: expected exactly one matching record, found ${matches.length}`);
  }
  return matches[0];
}

function verifyArtifactBinding(text, label) {
  const line = exactlyOne(text, 'PMLE_ARTIFACT|', label);
  requireParts(
    line,
    [
      `source_bytes=${candidateBytes}`,
      `source_sha256=${candidateSha}`,
      'table_bytes=180272',
      `table_sha256=${tableSha}`,
    ],
    label,
  );
  return line;
}

function requireOrder(text, lines, label) {
  let previous = -1;
  for (const line of lines) {
    const index = text.indexOf(line);
    if (index < 0 || index <= previous) {
      fail(`${label}: evidence markers are absent, duplicated, or out of order`);
    }
    previous = index;
  }
}

function unfoldHistoricalTicker(text) {
  const physical = text.split(/\r?\n/);
  const logical = [];
  for (let index = 0; index < physical.length; index += 1) {
    let line = physical[index];
    if (line.startsWith('PMLE_LIVE_REPLAY_TICKER|')) {
      while (!/\|throughput_tps=[0-9.]+$/.test(line)
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

function verifyLedgerPostflight(postflight) {
  const terminated = exactlyOne(
    postflight,
    'PMLE_DECPS_LEDGER_WRAPPER|TERMINATED_ENVIRONMENT_VERIFIED|',
    'ledger-postflight',
  );
  if (terminated !==
      'PMLE_DECPS_LEDGER_WRAPPER|TERMINATED_ENVIRONMENT_VERIFIED'
      + '|wrapper_pid=53541|launcher_pid=53640') {
    fail('ledger-postflight: malformed terminated-process marker');
  }
  const restored = exactlyOne(
    postflight,
    'PMLE_ARTIFACT|',
    'ledger-postflight',
  );
  if (restored !==
      `PMLE_ARTIFACT|source_bytes=${retiringBytes}`
      + `|source_sha256=${retiringSha}|table_bytes=180272`
      + `|table_sha256=${tableSha}`) {
    fail('ledger-postflight: malformed restored-artifact marker');
  }
  const pool = exactlyOne(
    postflight,
    'PMLE_DECPS_LEDGER_POOL|PASS|',
    'ledger-postflight',
  );
  if (pool !== 'PMLE_DECPS_LEDGER_POOL|PASS|slots=2|ready=2|bound=0') {
    fail('ledger-postflight: malformed restored-pool marker');
  }
  const alertMatch = exactlyOneRegex(
    postflight,
    /^PMLE_ALERT_WINDOW\|PASS\|label=DECPS_LEDGER\|new_ora_incidents=0\|bytes=([0-9]+)$/gm,
    'ledger-postflight',
  );
  const alert = alertMatch[0];
  const pass = exactlyOne(
    postflight,
    'PMLE_DECPS_LEDGER_POSTFLIGHT|PASS|',
    'ledger-postflight',
  );
  if (pass !==
      `PMLE_DECPS_LEDGER_POSTFLIGHT|PASS|authority_sha256=${retiringSha}`
      + '|slots=2|alert_offset=823833'
      + '|alert_started_utc=2026-07-25T07:02:32Z'
      + '|ledger_started_utc=2026-07-25T07:02:45Z') {
    fail('ledger-postflight: malformed terminal marker');
  }
  requireOrder(
    postflight,
    [terminated, restored, pool, alert, pass],
    'ledger-postflight',
  );
}

function selfTest() {
  const marker = 'PASS_MARKER|PASS|value=1';
  if (exactlyOne(`${marker}\n`, 'PASS_MARKER|', 'self-test') !== marker) {
    fail('self-test: exact marker extraction changed');
  }
  for (const bad of ['', `${marker}\n${marker}\n`, ` ${marker}\n`]) {
    let rejected = false;
    try {
      exactlyOne(bad, 'PASS_MARKER|', 'self-test-adversarial');
    } catch {
      rejected = true;
    }
    if (!rejected) {
      fail('self-test: malformed, duplicate, or wrapped marker was accepted');
    }
  }
  requireOrder('FIRST\nSECOND\n', ['FIRST', 'SECOND'], 'self-test-order');
  let orderRejected = false;
  try {
    requireOrder(
      'SECOND\nFIRST\n',
      ['FIRST', 'SECOND'],
      'self-test-order-adversarial',
    );
  } catch {
    orderRejected = true;
  }
  if (!orderRejected) {
    fail('self-test: out-of-order evidence was accepted');
  }
  const postflight = [
    'PMLE_DECPS_LEDGER_WRAPPER|TERMINATED_ENVIRONMENT_VERIFIED'
      + '|wrapper_pid=53541|launcher_pid=53640',
    `PMLE_ARTIFACT|source_bytes=${retiringBytes}`
      + `|source_sha256=${retiringSha}|table_bytes=180272`
      + `|table_sha256=${tableSha}`,
    'PMLE_DECPS_LEDGER_POOL|PASS|slots=2|ready=2|bound=0',
    'PMLE_ALERT_WINDOW|PASS|label=DECPS_LEDGER'
      + '|new_ora_incidents=0|bytes=123',
    `PMLE_DECPS_LEDGER_POSTFLIGHT|PASS|authority_sha256=${retiringSha}`
      + '|slots=2|alert_offset=823833'
      + '|alert_started_utc=2026-07-25T07:02:32Z'
      + '|ledger_started_utc=2026-07-25T07:02:45Z',
  ].join('\n');
  verifyLedgerPostflight(postflight);
  for (const bad of [
    postflight.replace(
      'PMLE_ALERT_WINDOW|PASS|label=DECPS_LEDGER',
      'PMLE_ALERT_WINDOW|FAIL|label=DECPS_LEDGER',
    ),
    postflight.split('\n').toReversed().join('\n'),
    `${postflight}\n${postflight.split('\n')[4]}`,
    postflight.replace(
      'PMLE_DECPS_LEDGER_POOL|PASS|slots=2|ready=2|bound=0',
      'PMLE_DECPS_LEDGER_POOL|PASS|slots=2|ready=2|bound=0|bound=1',
    ),
  ]) {
    let rejected = false;
    try {
      verifyLedgerPostflight(bad);
    } catch {
      rejected = true;
    }
    if (!rejected) {
      fail('self-test: invalid ledger postflight was accepted');
    }
  }
  console.log('PMLE_DECPS_PROMOTION_SELFTEST|PASS');
}

function literalReferencePaths(literal) {
  const scan = spawnSync(
    'rg',
    [
      '-l',
      '--hidden',
      '--fixed-strings',
      literal,
      '-g',
      '!.git/**',
      '-g',
      '!**/node_modules/**',
      '-g',
      '!**/target/**',
      '-g',
      '!**/build/**',
      '.',
    ],
    { cwd: root, encoding: 'utf8' },
  );
  if (scan.status !== 0 && scan.status !== 1) {
    fail(`retiring-reference scan failed: ${scan.stderr.trim()}`);
  }
  return new Set(
    scan.stdout
      .split(/\r?\n/)
      .map((path) => path.replace(/^\.\//, ''))
      .filter(Boolean),
  );
}

function verifyInventory(found, runtime, historical, label) {
  const classified = new Set([
    ...historical,
    ...runtime,
  ]);
  const unknown = [...found].filter((path) => !classified.has(path)).sort();
  const missing = [...classified].filter((path) => !found.has(path)).sort();
  if (unknown.length > 0) {
    fail(`unclassified ${label} references: ${unknown.join(', ')}`);
  }
  if (missing.length > 0) {
    fail(`stale ${label} inventory entries: ${missing.join(', ')}`);
  }
}

function scanRetiringReferences() {
  verifyInventory(
    literalReferencePaths(retiringSha),
    runtimeRetiringRefs,
    historicalRetiringRefs,
    'retiring-SHA',
  );
  verifyInventory(
    literalReferencePaths(retiringArtifact),
    runtimeRetiringArtifactRefs,
    historicalRetiringArtifactRefs,
    'retiring-artifact',
  );
  verifyInventory(
    literalReferencePaths(String(retiringBytes)),
    runtimeRetiringByteRefs,
    historicalRetiringByteRefs,
    'retiring-byte-count',
  );
  verifyInventory(
    literalReferencePaths(retiringMochaSha),
    runtimeRetiringMochaRefs,
    historicalRetiringMochaRefs,
    'retiring-Mocha-SHA',
  );
  verifyInventory(
    literalReferencePaths(retiringInputSha),
    runtimeRetiringInputRefs,
    historicalRetiringInputRefs,
    'retiring-input-bytecode-SHA',
  );
  console.log(
    'PMLE_DECPS_PROMOTION_INVENTORY|PASS|' +
      `runtime_rewrite=${runtimeRetiringRefs.size}|` +
      `historical_preserve=${historicalRetiringRefs.size}|` +
      `artifact_runtime_rewrite=${runtimeRetiringArtifactRefs.size}|` +
      `artifact_historical_preserve=${historicalRetiringArtifactRefs.size}|` +
      `byte_runtime_rewrite=${runtimeRetiringByteRefs.size}|` +
      `byte_historical_preserve=${historicalRetiringByteRefs.size}|` +
      `mocha_runtime_rewrite=${runtimeRetiringMochaRefs.size}|` +
      `mocha_historical_preserve=${historicalRetiringMochaRefs.size}|` +
      `input_runtime_rewrite=${runtimeRetiringInputRefs.size}|` +
      `input_historical_preserve=${historicalRetiringInputRefs.size}`,
  );
}

function verifyCandidate() {
  const bytes = readFileSync(resolve(root, paths.candidate));
  const sha = createHash('sha256').update(bytes).digest('hex');
  if (bytes.length !== candidateBytes || sha !== candidateSha) {
    fail(
      `candidate mismatch: bytes=${bytes.length} sha256=${sha}; ` +
        `expected bytes=${candidateBytes} sha256=${candidateSha}`,
    );
  }
  console.log(
    `PMLE_DECPS_PROMOTION_CANDIDATE|PASS|bytes=${bytes.length}|sha256=${sha}`,
  );
}

function verifyCompletedDifferentials() {
  const canonical = read(paths.canonical);
  const canonicalArtifact = verifyArtifactBinding(canonical, 'canonical');
  const canonicalPass = exactlyOne(
    canonical,
    'PMLE_TEAVM_MULTIPLAYER|PASS|',
    'canonical',
  );
  requireParts(
    canonicalPass,
    ['players=4', 'tics=330', 'deep_every=50'],
    'canonical',
  );
  requireOrder(canonical, [canonicalArtifact, canonicalPass], 'canonical');

  const coop = read(paths.coop);
  const coopArtifact = verifyArtifactBinding(coop, 'coop');
  const coopPass = exactlyOne(
    coop,
    'PMLE_TEAVM_COOP_DIFFERENTIAL|PASS|',
    'coop',
  );
  requireParts(
    coopPass,
    ['players=2', 'skill=1', 'tics=762', 'deep_every=1'],
    'coop',
  );
  requireOrder(coop, [coopArtifact, coopPass], 'coop');

  const membership = read(paths.membership);
  const membershipArtifact = verifyArtifactBinding(membership, 'membership');
  const membershipPass = exactlyOne(
    membership,
    'PMLE_TEAVM_MEMBERSHIP_RECOVERY_DIFFERENTIAL|PASS|',
    'membership',
  );
  requireOrder(
    membership,
    [membershipArtifact, membershipPass],
    'membership',
  );
  requireParts(
    membershipPass,
    [
      'players=2',
      'leave_tic=41',
      'checkpoint_tic=60',
      'rejoin_tic=61',
      'final_tic=100',
      'deep_every=1',
      `mle_sha256=${candidateSha}`,
      `ojvm_jar_sha256=${oracleSha}`,
    ],
    'membership',
  );

  console.log(
    'PMLE_DECPS_PROMOTION_DIFFERENTIALS|PASS|' +
      'canonical=330|coop=762|membership=100',
  );
}

function verifyRankEvidence() {
  const parity = read(paths.nodeParity);
  const parityPass = exactlyOne(
    parity,
    'PASS PMLE-JAVASCRIPT-CANDIDATE-PARITY ',
    'node-parity',
  );
  requireParts(
    parityPass,
    [
      'tics=5250',
      'checkpoints=5251',
      `candidate_sha256=${candidateSha}`,
      `oracle_sha256=${ledgerProvenPredecessorSha}`,
    ],
    'node-parity',
  );

  const rank = read(paths.mleRank);
  const artifact = exactlyOne(
    rank,
    'PMLE_DECPS_ARTIFACT|',
    'direct-mle-rank',
  );
  requireParts(
    artifact,
    [`sha256=${candidateSha}`, `bytes=${candidateBytes}`, 'phase=interpreter'],
    'direct-mle-rank',
  );
  // This historical SYSTIMESTAMP-only cell and its paired comparator remain
  // corroboration. Promotion truth comes from the independently rerun,
  // dual-clock cells below.
  const normalizedRank = unfoldHistoricalTicker(rank);
  const ticker = exactlyOne(
    normalizedRank,
    'PMLE_LIVE_REPLAY_TICKER|',
    'direct-mle-rank',
  );
  const tickerMatch = ticker.match(
    /^PMLE_LIVE_REPLAY_TICKER\|stream=live-dm-2026-07-23\|tics=5250\|p50_ms=([0-9.]+)\|p95_ms=([0-9.]+)\|p99_ms=([0-9.]+)\|max_ms=([0-9.]+)\|throughput_tps=([0-9.]+)(?:\|monotonic_centiseconds=[0-9]+\|monotonic_tps=[0-9.]+)?$/,
  );
  if (tickerMatch === null) {
    fail('direct-mle-rank: malformed ticker terminal');
  }
  requireOrder(
    normalizedRank,
    [artifact, ticker],
    'direct-mle-rank',
  );
  const comparison = read(paths.mleRankComparison);
  const clock = exactlyOne(
    comparison,
    'PMLE_DECPS_RANK_CLOCK_INTEGRITY|PASS|',
    'direct-mle-rank-comparison',
  );
  requireParts(
    clock,
    [
      'maximum_exclusions=26',
      'predecessor_excluded=1',
      'predecessor_tics=4016',
      'candidate_excluded=7',
      'candidate_tics=192,492,957,2119,3207,3536,4062',
    ],
    'direct-mle-rank-comparison',
  );
  const scored = exactlyOne(
    comparison,
    'PMLE_DECPS_RANK_COMPARISON|PASS|',
    'direct-mle-rank-comparison',
  );
  requireParts(
    scored,
    [
      'tics=5250',
      `predecessor_sha256=${ledgerProvenPredecessorSha}`,
      `candidate_sha256=${candidateSha}`,
      'predecessor_valid=5249',
      'candidate_valid=5243',
      'predecessor_p50_ms=36.644',
      'candidate_p50_ms=37.877',
      'p50_delta_pct=3.365',
      'predecessor_p95_ms=142.665',
      'candidate_p95_ms=143.588',
      'p95_delta_pct=0.647',
      'promotion_limit_pct=5.000',
    ],
    'direct-mle-rank-comparison',
  );
  requireOrder(
    comparison,
    [clock, scored],
    'direct-mle-rank-comparison',
  );

  const dualClockComparison = read(paths.dualClockComparison).trim();
  const regenerated = spawnSync(
    process.execPath,
    [
      resolve(root, 'probes/mle/teavm-engine/compare-decps-dual-clock-rank.mjs'),
      resolve(root, paths.dualClockPredecessor),
      resolve(root, paths.dualClockCandidate),
    ],
    {encoding: 'utf8'},
  );
  if (regenerated.status !== 0) {
    fail(`dual-clock rank regeneration failed: ${regenerated.stderr.trim()}`);
  }
  if (regenerated.stdout.trim() !== dualClockComparison) {
    fail('dual-clock rank evidence does not reproduce from the raw cells');
  }
  const dualIntegrity = exactlyOne(
    dualClockComparison,
    'PMLE_DECPS_DUAL_CLOCK_INTEGRITY|PASS|',
    'dual-clock-rank-comparison',
  );
  requireParts(
    dualIntegrity,
    ['disagreement_limit_ms=30', 'maximum_suspects=26'],
    'dual-clock-rank-comparison',
  );
  const dualRank = exactlyOne(
    dualClockComparison,
    'PMLE_DECPS_DUAL_CLOCK_RANK|PASS|',
    'dual-clock-rank-comparison',
  );
  requireParts(
    dualRank,
    [
      'tics=5250',
      `predecessor_sha256=${ledgerProvenPredecessorSha}`,
      `candidate_sha256=${candidateSha}`,
      'promotion_limit_pct=5.000',
    ],
    'dual-clock-rank-comparison',
  );
  const dualMatch = dualRank.match(
    /\|candidate_valid=([0-9]+).*?\|candidate_p50_ms=([0-9.]+)/
      .source
      + String.raw`\|p50_delta_pct=(-?[0-9.]+)`
      + String.raw`.*?\|candidate_p95_ms=([0-9.]+)`
      + String.raw`\|p95_delta_pct=(-?[0-9.]+)`
      + String.raw`.*?\|candidate_monotonic_tps=([0-9.]+)`,
  );
  if (dualMatch === null
      || Math.abs(Number(dualMatch[3])) > 5
      || Math.abs(Number(dualMatch[5])) > 5) {
    fail('dual-clock rank terminal is malformed or exceeds the 5% rule');
  }
  requireOrder(
    dualClockComparison,
    [dualIntegrity, dualRank],
    'dual-clock-rank-comparison',
  );

  const identity = read(paths.identityClassification);
  exactlyOne(
    identity,
    'PMLE_DECPS_IDENTITY_BREAK_CLASSIFICATION|PASS|',
    'identity-break-classification',
  );
  requireParts(
    identity,
    [
      'changed_class=org.teavm.classlib.java.nio.charset.impl.UTF16Decoder',
      'classification=TEAVM_GENERATED_CLASSLIB_ORDERING',
      'semantic_inheritance=REJECTED',
    ],
    'identity-break-classification',
  );
  console.log(
    'PMLE_DECPS_PROMOTION_RANK|PASS|node_tics=5250|'
      + `canonical_checkpoints=5251|valid_mle_samples=${dualMatch[1]}`
      + `|mle_p50_ms=${dualMatch[2]}|mle_p95_ms=${dualMatch[4]}`
      + `|p50_delta_pct=${dualMatch[3]}|p95_delta_pct=${dualMatch[5]}`
      + `|monotonic_tps=${dualMatch[6]}|clock_source=DUAL_GET_TIME_PRIMARY`,
  );
}

function verifyLedgerTerminal() {
  const active = spawnSync(
    'pgrep',
    ['-f', '[r]un-decps-ledger|[b]uild-ledger-differential'],
    { encoding: 'utf8' },
  );
  if (active.status === 0) {
    fail(`ledger wrapper is still active (pid=${active.stdout.trim().replace(/\s+/g, ',')})`);
  }
  if (active.status !== 1) {
    fail(`ledger process check failed: ${active.stderr.trim()}`);
  }
  const ledger = read(paths.ledger);
  const pair = exactlyOne(
    ledger,
    'PMLE_CANDIDATE_PAIR|',
    'ledger',
  );
  requireParts(
    pair,
    [
      'classification=UNPROMOTED_CANDIDATE',
      `authority_sha256=${candidateSha}`,
      `table_sha256=${tableSha}`,
      `ojvm_jar_sha256=${oracleSha}`,
    ],
    'ledger',
  );
  const ledgerArtifact = verifyArtifactBinding(ledger, 'ledger');
  const pass = exactlyOne(
    ledger,
    'PMLE_TEAVM_LEDGER_DIFFERENTIAL|PASS|',
    'ledger',
  );
  requireParts(pass, ['tics=13272', 'deep_every=1'], 'ledger');
  const runtime = exactlyOne(
    ledger,
    'PMLE_LEDGER_RUNTIME|',
    'ledger',
  );
  requireParts(runtime, ['elapsed_seconds=', 'ended_utc='], 'ledger');
  const provenance = exactlyOne(
    ledger,
    'PMLE_LEDGER_PROVENANCE|CONFIRMED|',
    'ledger',
  );
  requireParts(
    provenance,
    ['executions=1', 'terminal_markers=1'],
    'ledger',
  );
  requireOrder(
    ledger,
    [pair, ledgerArtifact, pass, runtime, provenance],
    'ledger',
  );
  verifyLedgerPostflight(read(paths.ledgerPostflight));
  console.log(
    'PMLE_DECPS_PROMOTION_LEDGER|PASS|tics=13272|deep_every=1|' +
      'executions=1|terminal_markers=1|postflight=PASS',
  );
}

function verifyReproducibility() {
  const rebuild = read(paths.rebuild);
  const build = exactlyOne(
    rebuild,
    'PASS PMLE-TEAVM-SIMULATION-BUILD ',
    'reproducibility-build',
  );
  requireParts(
    build,
    [
      `bytes=${candidateBytes}`,
      `sha256=${candidateSha}`,
      'classification=UNPROMOTED_CANDIDATE',
      'candidate_reason=decps-promotion-rebuild',
    ],
    'reproducibility-build',
  );
  const terminal = exactlyOne(
    rebuild,
    'PMLE_DECPS_REPRODUCIBILITY|PASS|',
    'reproducibility-build',
  );
  requireOrder(rebuild, [build, terminal], 'reproducibility-build');
  const match = terminal.match(new RegExp(
    '^PMLE_DECPS_REPRODUCIBILITY[|]PASS'
      + `[|]bytes=${candidateBytes}`
      + `[|]sha256=${candidateSha}`
      + '[|]input_bytecode_sha256=([0-9a-f]{64})'
      + '[|]mocha_bytecode_sha256=([0-9a-f]{64})'
      + '[|]patch_set_sha256=([0-9a-f]{64})$',
  ));
  if (match === null) {
    fail('reproducibility-build: malformed terminal marker');
  }
  const patchBytes = readFileSync(
    resolve(root, 'probes/mle/teavm-engine/0006-teavm-authority-no-blocking-wait.patch'),
  );
  const patchSha = createHash('sha256').update(patchBytes).digest('hex');
  const expectedPatchSetSha = createHash('sha256')
    .update(`${patchSha}  0006-teavm-authority-no-blocking-wait.patch\n`)
    .digest('hex');
  if (match[3] !== expectedPatchSetSha) {
    fail(
      `reproducibility-build: patch-set mismatch ${match[3]} ` +
        `expected ${expectedPatchSetSha}`,
    );
  }
  requireParts(
    build,
    [
      `input_bytecode_sha256=${match[1]}`,
      `mocha_bytecode_sha256=${match[2]}`,
      `patch_set_sha256=${match[3]}`,
    ],
    'reproducibility-build',
  );
  console.log(
    'PMLE_DECPS_PROMOTION_REPRODUCIBILITY|PASS|' +
      `input_bytecode_sha256=${match[1]}|mocha_bytecode_sha256=${match[2]}|` +
      `patch_set_sha256=${match[3]}`,
  );
}

try {
  selfTest();
  verifyCandidate();
  verifyCompletedDifferentials();
  verifyRankEvidence();
  scanRetiringReferences();
  verifyLedgerTerminal();
  verifyReproducibility();
  console.log(
    `PMLE_DECPS_PROMOTION_READINESS|PASS|candidate_sha256=${candidateSha}`,
  );
} catch (error) {
  console.error(`PMLE_DECPS_PROMOTION_READINESS|NOT_READY|${error.message}`);
  process.exitCode = 1;
}
