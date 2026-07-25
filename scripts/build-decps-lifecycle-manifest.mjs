#!/usr/bin/env node
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';

const root = path.resolve(new URL('..', import.meta.url).pathname);
const authoritySha =
  '5ec18cbe4cff7192d384e81d1010e0133d357d44ff17fa65821e1489c4fd1ee3';
const artifactMarker =
  'PMLE_ARTIFACT|source_bytes=1081335'
  + `|source_sha256=${authoritySha}`
  + '|table_bytes=180272'
  + '|table_sha256=058cd0df9444131b356762a096fd422d5131ac3aea91163aee056e8ad4965b44';
const databaseReadyMarker =
  `PMLE_DECPS_DEPLOY_DATABASE|READY|sha256=${authoritySha}`;
const deploymentPassMarker =
  'PMLE_DECPS_DEPLOY|PASS|bytes=1081335'
  + `|sha256=${authoritySha}`
  + '|rollback_sha256=e485b9418e5845b78e9e1593918d8bbb6f3c441c41a43cb8f3faf046e595148b';
const stateRelative =
  'artifacts/performance/pmle-decps-rank/database-deployment-state.json';
const statePath = path.join(root, stateRelative);
const gateNames = ['recovery', 'admission', 'lifecycle', 'finalSoak'];
const exactLineOccurrences = (text, marker) =>
  text.split(/\r?\n/).filter(line => line === marker).length;
const hasPassToken = marker => /(?:^|[| ])PASS(?:[| ]|$)/.test(marker);
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
  const gateMarker = 'PMLE_GATE|PASS|value=1';
  const deployment =
    `${artifactMarker}\n${databaseReadyMarker}\n${deploymentPassMarker}\n`;
  const gateEvidence = `${artifactMarker}\n${gateMarker}\n`;
  assert.equal(exactLineOccurrences(deployment, databaseReadyMarker), 1);
  assert.equal(exactLineOccurrences(deployment, deploymentPassMarker), 1);
  assert.equal(exactLineOccurrences(gateEvidence, artifactMarker), 1);
  assert.equal(exactLineOccurrences(gateEvidence, gateMarker), 1);
  assert.equal(hasPassToken(gateMarker), true);
  assertOrdered(
    deployment,
    [artifactMarker, databaseReadyMarker, deploymentPassMarker],
    'self-test deployment',
  );
  assertOrdered(
    gateEvidence,
    [artifactMarker, gateMarker],
    'self-test gate',
  );
  assert.throws(
    () => assertOrdered(
      `${gateMarker}\n${artifactMarker}\n`,
      [artifactMarker, gateMarker],
      'self-test gate adversarial',
    ),
    /out of order/,
  );
  for (const invalid of [
    gateMarker,
    `${artifactMarker}\n${artifactMarker}\n${gateMarker}`,
    `${artifactMarker.replace(authoritySha, `0${authoritySha.slice(1)}`)}\n`
      + gateMarker,
  ]) {
    assert.notEqual(
      exactLineOccurrences(invalid, artifactMarker),
      1,
      'artifact-binding adversarial fixture was accepted',
    );
  }
  assert.equal(hasPassToken('PMLE_GATE|BYPASS|value=1'), false);
  process.stdout.write('PASS PMLE-DECPS-LIFECYCLE-MANIFEST-SELF-TEST\n');
  process.exit(0);
}

const args = new Map();
for (let index = 2; index < process.argv.length; index += 1) {
  const token = process.argv[index];
  if (!token.startsWith('--') || index + 1 >= process.argv.length) {
    throw new Error(
      'usage: build-decps-lifecycle-manifest.mjs --output RELATIVE_PATH '
      + gateNames.map(name =>
        `--${name}-evidence RELATIVE_PATH --${name}-marker MARKER`).join(' '),
    );
  }
  const name = token.slice(2);
  if (args.has(name)) {
    throw new Error(`duplicate argument: --${name}`);
  }
  args.set(name, process.argv[++index]);
}
const allowedArgs = new Set([
  'output',
  ...gateNames.flatMap(name => [`${name}-evidence`, `${name}-marker`]),
]);
for (const name of args.keys()) {
  if (!allowedArgs.has(name)) {
    throw new Error(`unsupported argument: --${name}`);
  }
}
for (const name of allowedArgs) {
  if (!args.has(name)) {
    throw new Error(`missing required argument: --${name}`);
  }
}

const repositoryRelative = (value, label) => {
  if (!value || /[\0\r\n]/.test(value) || path.isAbsolute(value)
      || value.split(/[\\/]/).includes('..')) {
    throw new Error(`${label} must be a repository-relative path`);
  }
  const normalized = path.normalize(value);
  const absolute = path.resolve(root, normalized);
  if (absolute !== root && !absolute.startsWith(`${root}${path.sep}`)) {
    throw new Error(`${label} escapes the repository`);
  }
  return {relative: normalized, absolute};
};

const versions = JSON.parse(
  fs.readFileSync(path.join(root, 'versions.lock'), 'utf8'),
);
assert.equal(
  versions.teaVM.outputSha256,
  authoritySha,
  'lifecycle manifest requires the promoted de-CPS source pin',
);
const deploymentState = JSON.parse(fs.readFileSync(statePath, 'utf8'));
assert.equal(deploymentState.authoritySha256, authoritySha);
assert.equal(
  deploymentState.state,
  'DATABASE_DEPLOYED_LIFECYCLE_RERUN_PENDING',
  'lifecycle evidence may be assembled only for a deployed-pending authority',
);
const predecessorEvidence = repositoryRelative(
  deploymentState.evidence,
  'deployment predecessor evidence',
);
const predecessorText = fs.readFileSync(predecessorEvidence.absolute, 'utf8');
assert.equal(
  exactLineOccurrences(predecessorText, databaseReadyMarker),
  1,
  'deployment predecessor must contain exactly one database-ready marker',
);
assert.equal(
  exactLineOccurrences(predecessorText, deploymentPassMarker),
  1,
  'deployment predecessor must contain exactly one terminal PASS',
);
assert.equal(
  exactLineOccurrences(predecessorText, artifactMarker),
  1,
  'deployment predecessor must contain exactly one promoted artifact tuple',
);
assertOrdered(
  predecessorText,
  [artifactMarker, databaseReadyMarker, deploymentPassMarker],
  'deployment predecessor',
);
assert.doesNotMatch(
  predecessorText,
  /^PMLE_DECPS_DEPLOY_(?:ROLLBACK\|FAIL|CAPACITY\|HELD_CLOSED)\|/m,
  'deployment predecessor contains failed or held-capacity evidence',
);

const output = repositoryRelative(args.get('output'), 'output');
if (fs.existsSync(output.absolute)) {
  throw new Error(`lifecycle manifest already exists: ${output.relative}`);
}
const gates = {};
for (const name of gateNames) {
  const evidence = repositoryRelative(
    args.get(`${name}-evidence`),
    `${name} evidence`,
  );
  const marker = args.get(`${name}-marker`);
  if (!marker || /[\r\n]/.test(marker) || !hasPassToken(marker)) {
    throw new Error(`${name} marker must be one PASS line`);
  }
  const text = fs.readFileSync(evidence.absolute, 'utf8');
  assert.equal(
    exactLineOccurrences(text, artifactMarker),
    1,
    `${name} evidence must bind exactly one promoted artifact tuple`,
  );
  const occurrences = exactLineOccurrences(text, marker);
  assert.equal(
    occurrences,
    1,
    `${name} marker must occur exactly once in ${evidence.relative}`,
  );
  assertOrdered(text, [artifactMarker, marker], `${name} evidence`);
  gates[name] = {
    state: 'PASS',
    evidence: evidence.relative,
    marker,
  };
}

const manifest = {
  schema: 1,
  authoritySha256: authoritySha,
  predecessor: {
    state: deploymentState.state,
    evidence: deploymentState.evidence,
  },
  gates,
};
fs.mkdirSync(path.dirname(output.absolute), {recursive: true});
const temporary = `${output.absolute}.tmp`;
fs.writeFileSync(temporary, `${JSON.stringify(manifest, null, 2)}\n`, {
  mode: 0o644,
});
fs.renameSync(temporary, output.absolute);
process.stdout.write(
  `PMLE_DECPS_LIFECYCLE_MANIFEST|PASS|authority_sha256=${authoritySha}`
  + `|gates=${gateNames.join(',')}|output=${output.relative}\n`,
);
