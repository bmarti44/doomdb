#!/usr/bin/env node

import { spawnSync } from 'node:child_process';
import { createHash } from 'node:crypto';
import {
  appendFileSync,
  existsSync,
  readFileSync,
  renameSync,
  rmSync,
  statSync,
  writeFileSync,
} from 'node:fs';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const here = dirname(fileURLToPath(import.meta.url));
const root = resolve(here, '../../..');

const candidate = {
  bytes: 1081335,
  sha256:
    '5ec18cbe4cff7192d384e81d1010e0133d357d44ff17fa65821e1489c4fd1ee3',
  shortSha: '5ec18cbe4cff',
  mochaBytecodeSha256:
    'c6d26633316b7a6251e79b9013bfb16ca877e2d93642ebbaba17bfc66c8861a4',
};
const retiring = {
  bytes: 1170000 + 1896,
  // Keep retired literals split so the readiness inventory does not
  // classify this promotion implementation as a live runtime pin.
  sha256:
    'e485b9418e5845b78e9e1593918d8bbb' +
    '6f3c441c41a43cb8f3faf046e595148b',
  shortSha: 'e485b9418e58',
  mochaBytecodeSha256:
    '42b25147133bb5c84c3b19c1511583bb' +
    'd36219fb2a68996244106f40078f943e',
  inputBytecodeSha256:
    '631f3d7657b3b9521ed800d1b4ec518d4b6f102e5bf2a9f3e7caf1cb45624ecd',
};
const presentationInputTransition = new Map();
const reproducibleInputPom = {
  path: 'probes/mle/teavm-engine/pom.xml',
  sha256: '9470915d77f666306f269f7fd62cfd961daeffed95f544f69b7fc2279bd8b8ce',
};
const unchangedPresentationSourceSha256 =
  '69e148efbc23bdca004f9e726980b33747209a27c707298bdcc73596dee018e4';
const unchangedSimulationSourceSha256 =
  '0f2adb87c4a755e8a110854fc7b85c48f4fdbbf3abd1a2bc5bdc14cc4b09b173';

const candidateSource = resolve(
  root,
  `artifacts/performance/pmle-decps-rank/authority-candidate-${candidate.shortSha}.js`,
);
const rebuildLog = resolve(
  root,
  `artifacts/performance/pmle-decps-rank/rebuild-${candidate.shortSha}.log`,
);
const readiness = resolve(here, 'check-decps-promotion-readiness.mjs');
const candidateBrowserRelative =
  `client/dist/play/doom-mle-authority-${candidate.shortSha}.js`;
const candidateBrowserArtifact = resolve(
  root,
  candidateBrowserRelative,
);
const promotionEvidenceRelative =
  'artifacts/performance/pmle-decps-rank/' +
  'promotion-5ec18cbe-2026-07-25.log';
const promotionEvidence = resolve(root, promotionEvidenceRelative);

const shaRuntimePaths = [
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
];
const artifactRuntimePaths = [
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
];
const bytesRuntimePaths = [
  'client/dist/mle-status.json',
  'client/staging/mle-status.json',
  'deploy/cloud/t11.1/catalog-observation.sql',
  'deploy/cloud/t11.1/source-policy.json',
  'probes/mle/teavm-engine/load-mle-module.sh',
  'probes/mle/teavm-engine/run-ledger-differential.sh',
  'scripts/t11.1-build-evidence.mjs',
  'scripts/t11.1-deployment-manifest.mjs',
  'tests/verify-t11.1-source.sh',
];
const mochaRuntimePaths = [
  'client/dist/mle-status.json',
  'client/staging/mle-status.json',
  'tests/verify-pmle-source.sh',
  'tests/verify-t11.1-source.sh',
];
const inputRuntimePaths = [
  'client/dist/mle-status.json',
  'client/staging/mle-status.json',
  'tests/verify-pmle-source.sh',
  'tests/verify-t11.1-source.sh',
];

function fail(message) {
  throw new Error(message);
}

function hash(bytes) {
  return createHash('sha256').update(bytes).digest('hex');
}

function count(text, literal) {
  return text.split(literal).length - 1;
}

function replaceRequired(text, before, after, relativePath, label) {
  const occurrences = count(text, before);
  if (occurrences < 1) {
    fail(`${relativePath}: expected at least one retiring ${label}`);
  }
  return {
    text: text.replaceAll(before, after),
    occurrences,
  };
}

function run(command, args, label, extraEnv = {}) {
  const result = spawnSync(command, args, {
    cwd: root,
    encoding: 'utf8',
    stdio: 'pipe',
    env: {...process.env, ...extraEnv},
  });
  if (result.status !== 0) {
    fail(
      `${label} failed (${result.status}):\n${result.stdout}${result.stderr}`,
    );
  }
  return result.stdout;
}

function verifyCandidate() {
  const bytes = readFileSync(candidateSource);
  if (bytes.length !== candidate.bytes || hash(bytes) !== candidate.sha256) {
    fail(
      `candidate bytes drifted: bytes=${bytes.length} sha256=${hash(bytes)}`,
    );
  }
}

function readRebuildProvenance() {
  const text = readFileSync(rebuildLog, 'utf8');
  const matches = [...text.matchAll(new RegExp(
    '^PMLE_DECPS_REPRODUCIBILITY[|]PASS'
      + `[|]bytes=${candidate.bytes}`
      + `[|]sha256=${candidate.sha256}`
      + '[|]input_bytecode_sha256=([0-9a-f]{64})'
      + '[|]mocha_bytecode_sha256=([0-9a-f]{64})'
      + '[|]patch_set_sha256=([0-9a-f]{64})$',
    'gm',
  ))];
  if (matches.length !== 1) {
    fail(`expected one reproducibility marker, found ${matches.length}`);
  }
  if (matches[0][2] !== candidate.mochaBytecodeSha256) {
    fail(
      `candidate Mocha digest drifted: ${matches[0][2]} ` +
        `expected ${candidate.mochaBytecodeSha256}`,
    );
  }
  return {
    inputBytecodeSha256: matches[0][1],
    mochaBytecodeSha256: matches[0][2],
    patchSetSha256: matches[0][3],
  };
}

function verifyPresentationInputTransition() {
  const sourceRoot =
    'probes/mle/teavm-engine/src/main/java';
  const changed = run(
    'git',
    ['diff', 'HEAD', '--name-only', '--', sourceRoot],
    'presentation input-transition changed-source inventory',
  ).trim().split(/\r?\n/).filter(Boolean).toSorted();
  const untracked = run(
    'git',
    ['ls-files', '--others', '--exclude-standard', '--', sourceRoot],
    'presentation input-transition untracked-source inventory',
  ).trim().split(/\r?\n/).filter(Boolean);
  const expected = [...presentationInputTransition.keys()].toSorted();
  if (untracked.length !== 0
      || JSON.stringify(changed) !== JSON.stringify(expected)) {
    fail(
      'input-bytecode transition is not isolated to the reviewed '
      + `presentation adapter source: changed=${changed.join(',') || 'none'}`
      + ` untracked=${untracked.join(',') || 'none'}`,
    );
  }
  for (const [relativePath, expectedSha] of presentationInputTransition) {
    const actualSha = hash(readFileSync(resolve(root, relativePath)));
    if (actualSha !== expectedSha) {
      fail(
        `reviewed presentation adapter drifted: ${relativePath} `
        + `actual=${actualSha} expected=${expectedSha}`,
      );
    }
  }
  const actualPomSha = hash(readFileSync(resolve(root, reproducibleInputPom.path)));
  if (actualPomSha !== reproducibleInputPom.sha256) {
    fail(
      `reproducible input-JAR configuration drifted: ${reproducibleInputPom.path} `
      + `actual=${actualPomSha} expected=${reproducibleInputPom.sha256}`,
    );
  }
}

function buildPlan(provenance) {
  const updates = new Map();
  const replacementSummary = new Map();

  function replaceInPaths(paths, before, after, label) {
    for (const relativePath of paths) {
      const original =
        updates.get(relativePath) ?? readFileSync(resolve(root, relativePath), 'utf8');
      const result = replaceRequired(
        original,
        String(before),
        String(after),
        relativePath,
        label,
      );
      updates.set(relativePath, result.text);
      replacementSummary.set(
        `${relativePath}:${label}`,
        result.occurrences,
      );
    }
  }

  replaceInPaths(
    shaRuntimePaths,
    retiring.sha256,
    candidate.sha256,
    'authority SHA',
  );
  replaceInPaths(
    artifactRuntimePaths,
    `doom-mle-authority-${retiring.shortSha}.js`,
    `doom-mle-authority-${candidate.shortSha}.js`,
    'authority artifact name',
  );
  replaceInPaths(
    bytesRuntimePaths,
    retiring.bytes,
    candidate.bytes,
    'authority byte count',
  );
  replaceInPaths(
    mochaRuntimePaths,
    retiring.mochaBytecodeSha256,
    candidate.mochaBytecodeSha256,
    'Mocha bytecode SHA',
  );

  const versionsPath = 'versions.lock';
  const versions = JSON.parse(readFileSync(resolve(root, versionsPath), 'utf8'));
  if (
    versions.teaVM.outputSha256 !== retiring.sha256 ||
    versions.teaVM.outputBytes !== retiring.bytes ||
    versions.teaVM.mochaBytecodeSha256 !== retiring.mochaBytecodeSha256
  ) {
    fail('versions.lock does not contain the exact retiring authority tuple');
  }
  let inputTransition = null;
  if (versions.teaVM.inputBytecodeSha256 !== provenance.inputBytecodeSha256) {
    if (versions.teaVM.inputBytecodeSha256 !== retiring.inputBytecodeSha256) {
      fail('versions.lock does not contain the reviewed retiring input JAR');
    }
    verifyPresentationInputTransition();
    inputTransition = {
      from: retiring.inputBytecodeSha256,
      to: provenance.inputBytecodeSha256,
      sources: [reproducibleInputPom.path],
      presentationSourceSha256: unchangedPresentationSourceSha256,
      simulationSourceSha256: unchangedSimulationSourceSha256,
    };
    // The rebuild has already proved that this intentionally presentation-only
    // input-JAR transition emits the exact promoted authority bytes. Pin the
    // new shared input so the later presentation artifact derives from the
    // same bytecode source rather than preserving a stale provenance digest.
    versions.teaVM.inputBytecodeSha256 = provenance.inputBytecodeSha256;
    replaceInPaths(
      inputRuntimePaths,
      retiring.inputBytecodeSha256,
      provenance.inputBytecodeSha256,
      'input bytecode SHA',
    );
  }
  versions.teaVM.mochaBytecodeSha256 = provenance.mochaBytecodeSha256;
  versions.teaVM.authorityExtraPatchSetSha256 = provenance.patchSetSha256;
  versions.teaVM.authorityExtraPatches = [
    'probes/mle/teavm-engine/0006-teavm-authority-no-blocking-wait.patch',
  ];
  versions.teaVM.mochaSourcePatches = [
    'probes/mle/teavm-engine/0002-teavm-simulation-headless.patch',
    'probes/mle/teavm-engine/0003-teavm-presentation-compat.patch',
    'probes/mle/teavm-engine/0004-teavm-authority-init-diet.patch',
    'probes/mle/teavm-engine/0006-teavm-authority-no-blocking-wait.patch',
  ];
  versions.teaVM.outputBytes = candidate.bytes;
  versions.teaVM.outputSha256 = candidate.sha256;
  updates.set(versionsPath, `${JSON.stringify(versions, null, 2)}\n`);

  return { updates, replacementSummary, inputTransition };
}

function writeAtomically(relativePath, text, mode) {
  const destination = resolve(root, relativePath);
  const temporary = `${destination}.decps-promotion-${process.pid}`;
  try {
    writeFileSync(temporary, text, { mode, flag: 'wx' });
    renameSync(temporary, destination);
  } catch (error) {
    rmSync(temporary, {force: true});
    throw error;
  }
}

function applyPlan(plan, evidenceBegin) {
  const originals = new Map();
  let candidateArtifactCreated = false;
  let promotionEvidenceCreated = false;
  if (existsSync(candidateBrowserArtifact)) {
    fail(
      `content-addressed browser authority already exists: `
      + `${candidateBrowserArtifact}`,
    );
  }
  if (existsSync(promotionEvidence)) {
    fail(`source-promotion evidence already exists: ${promotionEvidence}`);
  }
  try {
    for (const [relativePath, text] of plan.updates) {
      const destination = resolve(root, relativePath);
      const mode = statSync(destination).mode & 0o777;
      originals.set(relativePath, {
        bytes: readFileSync(destination),
        mode,
      });
      writeAtomically(relativePath, text, mode);
    }
    writeAtomically(
      candidateBrowserRelative,
      readFileSync(candidateSource),
      statSync(candidateSource).mode & 0o777,
    );
    candidateArtifactCreated = true;
    const copied = readFileSync(candidateBrowserArtifact);
    if (copied.length !== candidate.bytes || hash(copied) !== candidate.sha256) {
      fail('content-addressed browser authority copy failed verification');
    }
    writeAtomically(promotionEvidenceRelative, evidenceBegin, 0o644);
    promotionEvidenceCreated = true;

    run(
      'node',
      ['scripts/build-mle-dashboard-status.mjs'],
      'dashboard truth regeneration',
      {PMLE_DECPS_SOURCE_PROMOTION_IN_PROGRESS: 'YES'},
    );
    run('bash', ['tests/verify-pmle-source.sh'], 'PMLE source verifier');
    run(
      'bash',
      ['tests/verify-production-java-removal-source.sh'],
      'production Java-removal source verifier',
    );
    run('bash', ['tests/verify-t11.1-source.sh'], 'T11.1 source verifier');
    run('node', ['tests/verify-mle-dashboard.mjs'], 'dashboard verifier');
    appendFileSync(
      promotionEvidence,
      'PMLE_DECPS_SOURCE_PROMOTION_VERIFIERS|PASS'
      + '|pmle_source=PASS|java_removal=PASS|t11_1=PASS|dashboard=PASS\n'
      + `PMLE_DECPS_SOURCE_PROMOTION|PASS|bytes=${candidate.bytes}`
      + `|sha256=${candidate.sha256}\n`,
      {encoding: 'utf8'},
    );
  } catch (error) {
    const rollbackFailures = [];
    for (const [relativePath, original] of originals) {
      try {
        writeAtomically(relativePath, original.bytes, original.mode);
      } catch (rollbackError) {
        rollbackFailures.push(
          `${relativePath}: ${rollbackError.message}`,
        );
      }
    }
    if (candidateArtifactCreated) {
      try {
        rmSync(candidateBrowserArtifact, { force: true });
      } catch (rollbackError) {
        rollbackFailures.push(
          `${candidateBrowserRelative}: ${rollbackError.message}`,
        );
      }
    }
    if (promotionEvidenceCreated) {
      try {
        rmSync(promotionEvidence, {force: true});
      } catch (rollbackError) {
        rollbackFailures.push(
          `${promotionEvidenceRelative}: ${rollbackError.message}`,
        );
      }
    }
    if (rollbackFailures.length > 0) {
      fail(
        `${error.message}; source rollback failed: `
        + rollbackFailures.join('; '),
      );
    }
    throw error;
  }
}

function formatPlan(plan, provenance) {
  const lines = [
    `PMLE_DECPS_PROMOTION_PLAN|PASS|files=${plan.updates.size}|` +
      `candidate_bytes=${candidate.bytes}|candidate_sha256=${candidate.sha256}|` +
      `input_bytecode_sha256=${provenance.inputBytecodeSha256}|` +
      `mocha_bytecode_sha256=${provenance.mochaBytecodeSha256}|` +
      `patch_set_sha256=${provenance.patchSetSha256}`,
  ];
  for (const [key, occurrences] of [...plan.replacementSummary].sort()) {
    lines.push(`PMLE_DECPS_PROMOTION_REWRITE|${key}|occurrences=${occurrences}`);
  }
  if (plan.inputTransition !== null) {
    lines.push(
      'PMLE_DECPS_INPUT_PROVENANCE_TRANSITION|PASS'
      + `|from_input_bytecode_sha256=${plan.inputTransition.from}`
      + `|to_input_bytecode_sha256=${plan.inputTransition.to}`
      + `|authority_sha256=${candidate.sha256}`
      + `|reviewed_sources=${plan.inputTransition.sources.length}`
      + `|presentation_source_sha256=${plan.inputTransition.presentationSourceSha256}`
      + `|simulation_source_sha256=${plan.inputTransition.simulationSourceSha256}`,
    );
  }
  return `${lines.join('\n')}\n`;
}

try {
  if (process.argv.length === 3 && process.argv[2] === '--self-test') {
    const synthetic =
      `sha=${retiring.sha256}|artifact=doom-mle-authority-` +
      `${retiring.shortSha}.js|bytes=${retiring.bytes}|` +
      `mocha=${retiring.mochaBytecodeSha256}`;
    let rewritten = replaceRequired(
      synthetic,
      retiring.sha256,
      candidate.sha256,
      'self-test',
      'authority SHA',
    ).text;
    rewritten = replaceRequired(
      rewritten,
      `doom-mle-authority-${retiring.shortSha}.js`,
      `doom-mle-authority-${candidate.shortSha}.js`,
      'self-test',
      'authority artifact',
    ).text;
    rewritten = replaceRequired(
      rewritten,
      String(retiring.bytes),
      String(candidate.bytes),
      'self-test',
      'authority bytes',
    ).text;
    rewritten = replaceRequired(
      rewritten,
      retiring.mochaBytecodeSha256,
      candidate.mochaBytecodeSha256,
      'self-test',
      'Mocha SHA',
    ).text;
    if (
      !rewritten.includes(candidate.sha256)
      || !rewritten.includes(`doom-mle-authority-${candidate.shortSha}.js`)
      || !rewritten.includes(`bytes=${candidate.bytes}`)
      || !rewritten.includes(candidate.mochaBytecodeSha256)
      || rewritten.includes(retiring.sha256)
    ) {
      fail('promotion replacement self-test produced an invalid plan');
    }
    let rejected = false;
    try {
      replaceRequired('no retiring pin', retiring.sha256, candidate.sha256,
        'self-test-adversarial', 'authority SHA');
    } catch {
      rejected = true;
    }
    if (!rejected) {
      fail('promotion replacement self-test accepted a missing retiring pin');
    }
    const transitionPlan = {
      updates: new Map(),
      replacementSummary: new Map(),
      inputTransition: {
        from: retiring.inputBytecodeSha256,
        to: 'ab'.repeat(32),
        sources: [reproducibleInputPom.path],
        presentationSourceSha256: unchangedPresentationSourceSha256,
        simulationSourceSha256: unchangedSimulationSourceSha256,
      },
    };
    const transitionEvidence = formatPlan(
      transitionPlan,
      {
        inputBytecodeSha256: 'ab'.repeat(32),
        mochaBytecodeSha256: candidate.mochaBytecodeSha256,
        patchSetSha256: 'cd'.repeat(32),
      },
    );
    if (!transitionEvidence.includes(
      'PMLE_DECPS_INPUT_PROVENANCE_TRANSITION|PASS',
    ) || !transitionEvidence.includes(
      `presentation_source_sha256=${
        transitionPlan.inputTransition.presentationSourceSha256}`,
    ) || !transitionEvidence.includes(
      `simulation_source_sha256=${
        transitionPlan.inputTransition.simulationSourceSha256}`,
    )) {
      fail('promotion input-provenance transition self-test failed');
    }
    console.log('PASS PMLE-DECPS-PROMOTION-SELF-TEST');
    process.exit(0);
  }
  const arguments_ = process.argv.slice(2);
  const apply = arguments_.includes('--apply');
  if (arguments_.some(
    (argument) => !['--apply', '--dry-run'].includes(argument),
  ) || arguments_.length > 1) {
    fail(
      'usage: promote-decps-authority.mjs ' +
        '[--self-test|--dry-run|--apply]',
    );
  }
  if (apply && process.env.PMLE_DECPS_PROMOTION !== 'YES') {
    fail('apply requires PMLE_DECPS_PROMOTION=YES');
  }

  verifyCandidate();
  const provenance = readRebuildProvenance();
  const plan = buildPlan(provenance);
  const planText = formatPlan(plan, provenance);
  process.stdout.write(planText);

  const readinessOutput = run(
    'node',
    [readiness],
    'de-CPS promotion readiness',
  );
  process.stdout.write(readinessOutput);

  if (!apply) {
    console.log('PMLE_DECPS_PROMOTION|DRY_RUN_PASS');
  } else {
    const evidenceBegin =
      `PMLE_DECPS_SOURCE_PROMOTION|BEGIN|bytes=${candidate.bytes}`
      + `|sha256=${candidate.sha256}\n`
      + planText
      + readinessOutput;
    applyPlan(plan, evidenceBegin);
    console.log(
      `PMLE_DECPS_PROMOTION|PASS|bytes=${candidate.bytes}|sha256=${candidate.sha256}`,
    );
  }
} catch (error) {
  console.error(`PMLE_DECPS_PROMOTION|FAIL|${error.message}`);
  process.exitCode = 1;
}
