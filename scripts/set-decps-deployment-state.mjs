#!/usr/bin/env node
import assert from 'node:assert/strict';
import {execFileSync} from 'node:child_process';
import fs from 'node:fs';
import path from 'node:path';

const root = path.resolve(new URL('..', import.meta.url).pathname);
const statePath = path.join(
  root,
  'artifacts/performance/pmle-decps-rank/database-deployment-state.json',
);
const versions = JSON.parse(
  fs.readFileSync(path.join(root, 'versions.lock'), 'utf8'),
);
const authoritySha =
  '5ec18cbe4cff7192d384e81d1010e0133d357d44ff17fa65821e1489c4fd1ee3';
const rollbackSha =
  'e485b9418e5845b78e9e1593918d8bbb6f3c441c41a43cb8f3faf046e595148b';
const artifactMarker =
  'PMLE_ARTIFACT|source_bytes=1081335'
  + `|source_sha256=${authoritySha}`
  + '|table_bytes=180272'
  + '|table_sha256=058cd0df9444131b356762a096fd422d5131ac3aea91163aee056e8ad4965b44';
const databaseReadyMarker =
  `PMLE_DECPS_DEPLOY_DATABASE|READY|sha256=${authoritySha}`;
const deploymentPassMarker =
  'PMLE_DECPS_DEPLOY|PASS|bytes=1081335'
  + `|sha256=${authoritySha}|rollback_sha256=${rollbackSha}`;
const rollbackArtifactMarker =
  'PMLE_ARTIFACT|source_bytes=1171896'
  + `|source_sha256=${rollbackSha}`
  + '|table_bytes=180272'
  + '|table_sha256=058cd0df9444131b356762a096fd422d5131ac3aea91163aee056e8ad4965b44';
const rollbackBeginMarker =
  `PMLE_DECPS_DEPLOY_ROLLBACK|BEGIN|sha256=${rollbackSha}`;
const rollbackContractMarker =
  `PMLE_DECPS_ROLLBACK_WORKER_CONTRACT|PASS|sha256=${rollbackSha}`;
const rollbackPassMarker =
  `PMLE_DECPS_DEPLOY_ROLLBACK|PASS|sha256=${rollbackSha}`;
const exactLineOccurrences = (text, marker) =>
  text.split(/\r?\n/).filter(line => line === marker).length;
const hasPassToken = marker => /(?:^|[| ])PASS(?:[| ]|$)/.test(marker);
const finalCapacityEvidence = text => {
  const lines = text.split(/\r?\n/).filter(
    line => line.startsWith('PMLE_DECPS_DEPLOY_CAPACITY|'),
  );
  assert.ok(lines.length > 0, 'intervention state lacks capacity evidence');
  const parsed = lines.map(line => {
    const match = line.match(
      /^PMLE_DECPS_DEPLOY_CAPACITY\|(HELD_CLOSED|UNPROVEN)\|reason=([a-z0-9_]+)$/,
    );
    assert.ok(match, `malformed capacity evidence: ${line}`);
    return {kind: match[1], reason: match[2], line};
  });
  return parsed.at(-1);
};
const assertOrdered = (text, markers, label) => {
  let previous = -1;
  for (const marker of markers) {
    const index = text.indexOf(marker);
    assert.ok(
      index > previous,
      `${label} markers are absent, duplicated, or out of order`,
    );
    previous = index;
  }
};

if (process.argv.length === 3 && process.argv[2] === '--self-test') {
  const deployment =
    `${artifactMarker}\n${databaseReadyMarker}\n${deploymentPassMarker}\n`;
  assert.equal(
    exactLineOccurrences(deployment, databaseReadyMarker),
    1,
  );
  assert.equal(
    exactLineOccurrences(deployment, deploymentPassMarker),
    1,
  );
  assertOrdered(
    deployment,
    [artifactMarker, databaseReadyMarker, deploymentPassMarker],
    'self-test deployment',
  );
  const rollback =
    `${rollbackBeginMarker}\n${rollbackArtifactMarker}\n`
    + `${rollbackContractMarker}\n${rollbackPassMarker}\n`;
  assertOrdered(
    rollback,
    [
      rollbackBeginMarker,
      rollbackArtifactMarker,
      rollbackContractMarker,
      rollbackPassMarker,
    ],
    'self-test rollback',
  );
  assert.throws(
    () => assertOrdered(
      `${rollbackPassMarker}\n${rollbackArtifactMarker}\n`,
      [rollbackArtifactMarker, rollbackPassMarker],
      'self-test rollback adversarial',
    ),
    /out of order/,
  );
  assert.equal(exactLineOccurrences(`${artifactMarker}\n`, artifactMarker), 1);
  assert.equal(
    exactLineOccurrences(`${artifactMarker}\n${artifactMarker}\n`, artifactMarker),
    2,
  );
  assert.equal(
    exactLineOccurrences(
      `${artifactMarker.replace(authoritySha, `0${authoritySha.slice(1)}`)}\n`,
      artifactMarker,
    ),
    0,
  );
  assert.equal(hasPassToken('PMLE_GATE|PASS|value=1'), true);
  assert.equal(hasPassToken('PMLE_GATE|BYPASS|value=1'), false);
  assert.deepEqual(
    finalCapacityEvidence(
      'PMLE_DECPS_DEPLOY_CAPACITY|HELD_CLOSED|reason=first\n'
      + 'PMLE_DECPS_DEPLOY_CAPACITY|UNPROVEN|reason=last\n',
    ),
    {
      kind: 'UNPROVEN',
      reason: 'last',
      line: 'PMLE_DECPS_DEPLOY_CAPACITY|UNPROVEN|reason=last',
    },
  );
  assert.throws(
    () => finalCapacityEvidence(
      'PMLE_DECPS_DEPLOY_CAPACITY|HELD_CLOSED|reason=valid\n'
      + 'PMLE_DECPS_DEPLOY_CAPACITY|UNKNOWN|reason=invalid\n',
    ),
    /malformed capacity evidence/,
  );
  process.stdout.write('PASS PMLE-DECPS-DEPLOYMENT-STATE-SELF-TEST\n');
  process.exit(0);
}

assert.equal(
  versions.teaVM.outputSha256,
  authoritySha,
  'deployment state may change only after de-CPS source promotion',
);

const args = new Map();
const allowedArgs = new Set(['state', 'evidence', 'evidence-commit']);
for (let index = 2; index < process.argv.length; index += 1) {
  const token = process.argv[index];
  if (!token.startsWith('--') || index + 1 >= process.argv.length) {
    throw new Error(
      'usage: set-decps-deployment-state.mjs --state STATE '
      + '--evidence RELATIVE_PATH [--evidence-commit SHA]',
    );
  }
  const name = token.slice(2);
  if (!allowedArgs.has(name)) {
    throw new Error(`unsupported argument: --${name}`);
  }
  if (args.has(name)) {
    throw new Error(`duplicate argument: --${name}`);
  }
  args.set(name, process.argv[++index]);
}
const state = args.get('state');
const evidencePath = args.get('evidence');
if (!state) {
  throw new Error('deployment state is required');
}
if (!evidencePath || /[\0\r\n]/.test(evidencePath)
    || path.isAbsolute(evidencePath)
    || evidencePath.split('/').includes('..')) {
  throw new Error('deployment-state evidence must be a repository-relative path');
}
const absoluteEvidence = path.join(root, evidencePath);
const readEvidence = () => fs.readFileSync(absoluteEvidence, 'utf8');
const record = {
  schema: 1,
  authoritySha256: authoritySha,
  state,
  evidence: evidencePath,
};

if (state === 'SOURCE_PINNED_DATABASE_DEPLOYMENT_PENDING') {
  if (args.has('evidence-commit')) {
    throw new Error('source-pinned state cannot carry a lifecycle evidence commit');
  }
  const evidence = readEvidence();
  for (const marker of [
    rollbackBeginMarker,
    rollbackArtifactMarker,
    rollbackContractMarker,
    rollbackPassMarker,
  ]) {
    assert.equal(
      exactLineOccurrences(evidence, marker),
      1,
      `source-pinned state requires exactly one ${marker}`,
    );
  }
  assertOrdered(
    evidence,
    [
      rollbackBeginMarker,
      rollbackArtifactMarker,
      rollbackContractMarker,
      rollbackPassMarker,
    ],
    'verified rollback',
  );
  assert.doesNotMatch(
    evidence,
    /^PMLE_DECPS_DEPLOY_(?:ROLLBACK\|FAIL|CAPACITY\|HELD_CLOSED)\|/m,
    'source-pinned state cannot reuse failed or held-capacity evidence',
  );
} else if (state === 'DATABASE_DEPLOYED_LIFECYCLE_RERUN_PENDING') {
  if (args.has('evidence-commit')) {
    throw new Error('deployed-pending state cannot carry a lifecycle evidence commit');
  }
  const evidence = readEvidence();
  assert.equal(
    exactLineOccurrences(evidence, artifactMarker),
    1,
    'database-deployed state requires exactly one promoted artifact tuple',
  );
  assert.equal(
    exactLineOccurrences(
      evidence,
      `PMLE_DECPS_DEPLOY_DATABASE|READY|sha256=${authoritySha}`,
    ),
    1,
    'database-deployed state requires exactly one database-ready marker',
  );
  assertOrdered(
    evidence,
    [artifactMarker, databaseReadyMarker],
    'database-deployed state',
  );
  assert.doesNotMatch(
    evidence,
    /^PMLE_DECPS_DEPLOY_(?:ROLLBACK\|FAIL|CAPACITY\|HELD_CLOSED)\|/m,
    'database-deployed state cannot reuse failed or held-capacity evidence',
  );
} else if (state === 'INTERVENTION_REQUIRED_CAPACITY_HELD_CLOSED') {
  if (args.has('evidence-commit')) {
    throw new Error('intervention state cannot carry a lifecycle evidence commit');
  }
  const capacity = finalCapacityEvidence(readEvidence());
  assert.equal(
    capacity.kind,
    'HELD_CLOSED',
    'final capacity evidence does not prove a closed hold',
  );
  record.interventionReason = capacity.reason;
} else if (state === 'INTERVENTION_REQUIRED_CAPACITY_UNPROVEN') {
  if (args.has('evidence-commit')) {
    throw new Error('intervention state cannot carry a lifecycle evidence commit');
  }
  const capacity = finalCapacityEvidence(readEvidence());
  assert.equal(
    capacity.kind,
    'UNPROVEN',
    'final capacity evidence does not preserve uncertainty',
  );
  record.interventionReason = capacity.reason;
} else if (state === 'DATABASE_DEPLOYED_LIFECYCLE_QUALIFIED') {
  const commit = args.get('evidence-commit');
  if (!/^[0-9a-f]{40}$/.test(commit ?? '')) {
    throw new Error('qualified lifecycle state requires a full evidence commit');
  }
  const committed = relative => execFileSync(
    'git',
    ['show', `${commit}:${relative}`],
    {cwd: root, encoding: 'utf8'},
  );
  const committedVersions = JSON.parse(committed('versions.lock'));
  assert.equal(
    committedVersions.teaVM.outputSha256,
    authoritySha,
    'lifecycle evidence commit does not pin the deployed authority',
  );
  const currentState = JSON.parse(fs.readFileSync(statePath, 'utf8'));
  assert.equal(
    currentState.state,
    'DATABASE_DEPLOYED_LIFECYCLE_RERUN_PENDING',
    'only the deployed-pending state may become lifecycle-qualified',
  );
  const committedState = JSON.parse(committed(
    path.relative(root, statePath),
  ));
  assert.equal(
    committedState.state,
    'DATABASE_DEPLOYED_LIFECYCLE_RERUN_PENDING',
    'evidence commit does not preserve the deployed-pending predecessor',
  );
  const deploymentEvidence = committed(committedState.evidence);
  assert.equal(
    exactLineOccurrences(deploymentEvidence, databaseReadyMarker),
    1,
    'evidence commit lacks exactly one database-ready marker',
  );
  assert.equal(
    exactLineOccurrences(deploymentEvidence, deploymentPassMarker),
    1,
    'evidence commit lacks exactly one terminal database deployment PASS',
  );
  assert.equal(
    exactLineOccurrences(deploymentEvidence, artifactMarker),
    1,
    'evidence commit lacks exactly one promoted artifact tuple',
  );
  assertOrdered(
    deploymentEvidence,
    [artifactMarker, databaseReadyMarker, deploymentPassMarker],
    'qualified deployment evidence',
  );
  assert.doesNotMatch(
    deploymentEvidence,
    /^PMLE_DECPS_DEPLOY_(?:ROLLBACK\|FAIL|CAPACITY\|HELD_CLOSED)\|/m,
    'evidence commit contains failed or held-capacity deployment evidence',
  );
  const manifest = JSON.parse(committed(evidencePath));
  assert.equal(manifest.schema, 1, 'unsupported lifecycle manifest schema');
  assert.equal(manifest.authoritySha256, authoritySha);
  assert.deepEqual(
    manifest.predecessor,
    {
      state: 'DATABASE_DEPLOYED_LIFECYCLE_RERUN_PENDING',
      evidence: committedState.evidence,
    },
    'lifecycle manifest predecessor does not match committed deployment state',
  );
  const requiredGates = [
    'recovery',
    'admission',
    'lifecycle',
    'finalSoak',
  ];
  assert.deepEqual(
    Object.keys(manifest.gates ?? {}).sort(),
    requiredGates.toSorted(),
    'lifecycle manifest must contain exactly the four required gates',
  );
  for (const gate of requiredGates) {
    const entry = manifest.gates?.[gate];
    assert.equal(entry?.state, 'PASS', `${gate} is not PASS`);
    if (!entry.evidence || !entry.marker) {
      throw new Error(`${gate} lacks evidence/marker provenance`);
    }
    if (path.isAbsolute(entry.evidence)
        || /[\0\r\n]/.test(entry.evidence)
        || entry.evidence.split(/[\\/]/).includes('..')
        || /[\r\n]/.test(entry.marker)
        || !hasPassToken(entry.marker)) {
      throw new Error(`${gate} evidence provenance is malformed`);
    }
    const gateEvidence = committed(entry.evidence);
    assert.equal(
      exactLineOccurrences(gateEvidence, artifactMarker),
      1,
      `${gate} evidence must bind exactly one promoted artifact tuple`,
    );
    assert.equal(
      exactLineOccurrences(gateEvidence, entry.marker),
      1,
      `${gate} marker must occur as exactly one complete line in committed evidence`,
    );
    assertOrdered(
      gateEvidence,
      [artifactMarker, entry.marker],
      `${gate} committed evidence`,
    );
  }
  record.evidenceCommit = commit;
} else {
  throw new Error(`unsupported deployment state: ${state}`);
}

fs.mkdirSync(path.dirname(statePath), {recursive: true});
const temporary = `${statePath}.tmp`;
fs.writeFileSync(temporary, `${JSON.stringify(record, null, 2)}\n`, {
  mode: 0o644,
});
fs.renameSync(temporary, statePath);
process.stdout.write(
  `PMLE_DECPS_DEPLOYMENT_STATE|PASS|state=${state}`
  + `|authority_sha256=${authoritySha}|evidence=${evidencePath}\n`,
);
