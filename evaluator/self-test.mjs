import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { auditProduction } from './lib/static-audit.mjs';
import { guardTestSources } from './playwright/guard-source.mjs';
import { verifyIntegrity } from './lib/integrity.mjs';
import { validateEvaluatorCompose } from './lib/network-policy.mjs';
import { validateResult } from './lib/result-validator.mjs';

export const SELF_TEST_SCENARIOS = [
  'delete-test', 'rename-id', 'only', 'skip-fixme', 'remove-assertion',
  'edit-fixture', 'edit-golden', 'child-exit-zero', 'forge-pass',
  'zero-discovery', 'production-expected-read', 'unapproved-egress',
  'integrity-baseline'
];

const isMain = process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url);

function writeResult(file, nonce, tests, totalAssertions = tests.reduce((sum, test) => sum + test.assertions, 0)) {
  fs.writeFileSync(file, JSON.stringify({ nonce, tests, totalAssertions }));
}

function expectFailure(label, pattern, action) {
  assert.throws(action, pattern, `${label} did not fail for the intended guard`);
}

function integrityCopy(repoRoot) {
  const scratch = fs.mkdtempSync(path.join(os.tmpdir(), 'doom-integrity-'));
  const manifest = JSON.parse(fs.readFileSync(path.join(repoRoot, 'evaluator/integrity.json'), 'utf8'));
  for (const relative of Object.keys(manifest.files)) {
    const destination = path.join(scratch, relative);
    fs.mkdirSync(path.dirname(destination), { recursive: true });
    fs.copyFileSync(path.join(repoRoot, relative), destination);
  }
  fs.mkdirSync(path.join(scratch, 'evaluator'), { recursive: true });
  fs.copyFileSync(path.join(repoRoot, 'evaluator/integrity.json'), path.join(scratch, 'evaluator/integrity.json'));
  return scratch;
}

export function runSelfTest(repoRoot = path.resolve(import.meta.dirname, '..')) {
  const scratch = fs.mkdtempSync(path.join(os.tmpdir(), 'doom-self-test-'));
  const manifest = path.join(scratch, 'manifest.json');
  const result = path.join(scratch, 'result.json');
  fs.writeFileSync(manifest, JSON.stringify({ tests: [{ id: 'a', assertions: 1 }, { id: 'b', assertions: 2 }] }));
  const goodTests = [{ id: 'a', assertions: 1, status: 'passed' }, { id: 'b', assertions: 2, status: 'passed' }];

  writeResult(result, 'nonce', [goodTests[0]], 1);
  expectFailure('delete test', /missing approved tests/, () => validateResult(manifest, result, 'nonce'));

  writeResult(result, 'nonce', [{ ...goodTests[0], id: 'renamed' }, goodTests[1]]);
  expectFailure('rename id', /unknown or renamed test id/, () => validateResult(manifest, result, 'nonce'));

  const sourceRoot = path.join(scratch, 'sources');
  fs.mkdirSync(sourceRoot);
  fs.writeFileSync(path.join(sourceRoot, 'only.test.ts'), "test.only('x', () => expect(1).toBe(1));");
  assert.ok(guardTestSources(sourceRoot).some((item) => item.reason === '.only'), '.only guard did not fire');

  fs.writeFileSync(path.join(sourceRoot, 'skip.test.ts'), "test.skip('x', () => {}); test.fixme('y', () => {});");
  const skipFailures = guardTestSources(sourceRoot);
  assert.ok(skipFailures.some((item) => item.reason === 'skip/fixme'), 'skip/fixme guard did not fire');

  writeResult(result, 'nonce', [{ ...goodTests[0], assertions: 0 }, goodTests[1]], 2);
  expectFailure('remove assertion', /zero assertions/, () => validateResult(manifest, result, 'nonce'));

  const fixtureCopy = integrityCopy(repoRoot);
  fs.appendFileSync(path.join(fixtureCopy, 'evaluator/fixtures/visible-seed.json'), ' ');
  assert.ok(verifyIntegrity(fixtureCopy).some((item) => item.includes('fixtures/visible-seed.json: hash mismatch')), 'fixture edit guard did not fire');
  fs.rmSync(fixtureCopy, { recursive: true, force: true });

  const goldenCopy = integrityCopy(repoRoot);
  fs.appendFileSync(path.join(goldenCopy, 'evaluator/goldens/foundation.txt'), 'tamper');
  assert.ok(verifyIntegrity(goldenCopy).some((item) => item.includes('goldens/foundation.txt: hash mismatch')), 'golden edit guard did not fire');
  fs.rmSync(goldenCopy, { recursive: true, force: true });

  const childCopy = fs.mkdtempSync(path.join(os.tmpdir(), 'doom-child-'));
  fs.cpSync(path.join(repoRoot, 'evaluator'), path.join(childCopy, 'evaluator'), { recursive: true });
  fs.cpSync(path.join(repoRoot, 'tools'), path.join(childCopy, 'tools'), { recursive: true });
  fs.writeFileSync(path.join(childCopy, 'evaluator/foundation-child.mjs'), 'process.exit(0);\n');
  const child = spawnSync(process.execPath, [path.join(childCopy, 'evaluator/run-foundation.mjs'), 'T0.4'], { cwd: childCopy, encoding: 'utf8' });
  assert.notEqual(child.status, 0, 'child replacement forged success');
  assert.match(child.stderr, /produced no machine result/, 'child replacement failed for an incidental reason');
  fs.rmSync(childCopy, { recursive: true, force: true });

  writeResult(result, 'forged', goodTests);
  expectFailure('forged pass', /result nonce mismatch/, () => validateResult(manifest, result, 'nonce'));

  writeResult(result, 'nonce', [], 0);
  expectFailure('zero discovery', /zero discovered tests/, () => validateResult(manifest, result, 'nonce'));

  const badPolicy = JSON.parse(fs.readFileSync(path.join(repoRoot, 'evaluator/audit-policy.json'), 'utf8'));
  badPolicy.forbiddenPathSegments = [];
  badPolicy.productionRoots = ['evaluator/dummy/bad/client/src'];
  assert.ok(auditProduction(repoRoot, badPolicy).some((item) => item.id === 'expected-path-read'), 'production expected-output read was not rejected');

  const compose = fs.readFileSync(path.join(repoRoot, 'evaluator/compose.evaluator.yaml'), 'utf8').replace('internal: true', 'internal: false');
  assert.ok(validateEvaluatorCompose(compose).some((item) => item.includes('egress')), 'unapproved egress was not rejected');

  assert.deepEqual(verifyIntegrity(repoRoot), [], 'reviewed baseline integrity is not green');
  fs.rmSync(scratch, { recursive: true, force: true });
  return SELF_TEST_SCENARIOS.length;
}

if (isMain) {
  const count = runSelfTest();
  process.stdout.write(`PASS T0.4-EVALUATOR-SELF-TEST (${count}/${count} attacks rejected)\n`);
}
