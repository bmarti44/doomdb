import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { auditProduction } from './lib/static-audit.mjs';
import { loadHiddenSeeds } from './lib/hidden-seeds.mjs';
import { validateResult } from './lib/result-validator.mjs';
import { verifyIntegrity } from './lib/integrity.mjs';
import { validateEvaluatorCompose } from './lib/network-policy.mjs';
import { SELF_TEST_SCENARIOS } from './self-test.mjs';

const repoRoot = path.resolve(import.meta.dirname, '..');
const resultPath = process.argv[2];
const nonce = process.argv[3];
if (!resultPath || !nonce) throw new Error('result path and nonce are required');

const manifestPath = path.join(repoRoot, 'evaluator/manifest/test-ids.json');
const manifest = JSON.parse(fs.readFileSync(manifestPath, 'utf8'));
const policy = JSON.parse(fs.readFileSync(path.join(repoRoot, 'evaluator/audit-policy.json'), 'utf8'));
const tests = [];

function record(id, assertions, check) {
  check();
  tests.push({ id, assertions, status: 'passed' });
}

record('T0.4-EVAL-001', 3, () => {
  assert.equal(manifest.schema, 1);
  assert.equal(new Set(manifest.tests.map((test) => test.id)).size, manifest.tests.length);
  assert.ok(manifest.tests.every((test) => Number.isInteger(test.assertions) && test.assertions > 0));
});

record('T0.4-EVAL-002', 7, () => {
  const compose = fs.readFileSync(path.join(repoRoot, 'evaluator/compose.evaluator.yaml'), 'utf8');
  assert.deepEqual(validateEvaluatorCompose(compose), []);
  assert.match(compose, /read_only:\s*true/);
  assert.match(compose, /evaluator:\/workspace\/evaluator:ro/);
  assert.match(compose, /\/held-back:ro/);
  assert.match(compose, /client\/dist:\/production\/client:ro/);
  assert.match(compose, /internal:\s*true/);
  assert.doesNotMatch(compose, /docker\.sock|privileged:\s*true|pid:\s*host/);
  assert.match(compose, /cap_drop:\s*\["ALL"\]/);
});

record('T0.4-EVAL-003', 2, () => {
  const goodPolicy = { ...policy, forbiddenPathSegments: [], productionRoots: ['evaluator/dummy/good/client/src'] };
  const badPolicy = { ...policy, forbiddenPathSegments: [], productionRoots: ['evaluator/dummy/bad/client/src'] };
  assert.deepEqual(auditProduction(repoRoot, goodPolicy), []);
  assert.ok(auditProduction(repoRoot, badPolicy).some((item) => item.id === 'expected-path-read'));
});

record('T0.4-EVAL-004', 3, () => {
  assert.deepEqual(loadHiddenSeeds(undefined), []);
  const scratch = fs.mkdtempSync(path.join(os.tmpdir(), 'doom-hidden-'));
  fs.writeFileSync(path.join(scratch, 'b.json'), '{"seed":2}');
  fs.writeFileSync(path.join(scratch, 'a.json'), '{"seed":1}');
  assert.deepEqual(loadHiddenSeeds(scratch).map((item) => item.name), ['a.json', 'b.json']);
  const outside = path.join(os.tmpdir(), `doom-outside-${process.pid}.json`);
  fs.writeFileSync(outside, '{}');
  fs.symlinkSync(outside, path.join(scratch, 'escape.json'));
  assert.throws(() => loadHiddenSeeds(scratch), /escapes mount|regular file/);
  fs.rmSync(scratch, { recursive: true, force: true });
  fs.rmSync(outside, { force: true });
});

record('T0.4-EVAL-005', 2, () => {
  const mutation = spawnSync(process.execPath, [path.join(repoRoot, 'tools/mutations/run.mjs')], { cwd: repoRoot, encoding: 'utf8' });
  assert.equal(mutation.status, 0, mutation.stderr || mutation.stdout);
  const outcome = JSON.parse(mutation.stdout);
  assert.deepEqual(outcome.outcomes.map((item) => [item.id, item.passed]), [['canary-killed', true], ['canary-survives', true]]);
});

record('T0.4-EVAL-006', 10, () => {
  const config = fs.readFileSync(path.join(repoRoot, 'evaluator/playwright/playwright.config.ts'), 'utf8');
  for (const token of ["forbidOnly: true", "retries: 0", "workers: 1", "updateSnapshots: 'none'", 'width: 1280', 'height: 720', 'deviceScaleFactor: 1', "locale: 'en-US'", "timezoneId: 'UTC'", "colorScheme: 'dark'"]) assert.ok(config.includes(token), token);
});

record('T0.4-EVAL-007', 3, () => {
  const scratch = fs.mkdtempSync(path.join(os.tmpdir(), 'doom-results-'));
  const tinyManifest = path.join(scratch, 'manifest.json');
  const good = path.join(scratch, 'good.json');
  const bad = path.join(scratch, 'bad.json');
  fs.writeFileSync(tinyManifest, JSON.stringify({ tests: [{ id: 'dummy', assertions: 1 }] }));
  fs.writeFileSync(good, JSON.stringify({ nonce: 'n', totalAssertions: 1, tests: [{ id: 'dummy', assertions: 1, status: 'passed' }] }));
  fs.writeFileSync(bad, JSON.stringify({ nonce: 'n', totalAssertions: 0, tests: [{ id: 'dummy', assertions: 0, status: 'passed' }] }));
  assert.deepEqual(validateResult(tinyManifest, good, 'n'), { passed: 1, total: 1, assertions: 1 });
  assert.throws(() => validateResult(tinyManifest, bad, 'n'), /zero assertions/);
  assert.ok(fs.existsSync(path.join(repoRoot, 'evaluator/dummy/good/client/src/app.ts')) && fs.existsSync(path.join(repoRoot, 'evaluator/dummy/bad/client/src/app.ts')));
  fs.rmSync(scratch, { recursive: true, force: true });
});

record('T0.4-EVAL-008', 13, () => {
  assert.equal(SELF_TEST_SCENARIOS.length, 13);
  assert.equal(new Set(SELF_TEST_SCENARIOS).size, 13);
  assert.deepEqual(verifyIntegrity(repoRoot), []);
});

const totalAssertions = tests.reduce((sum, test) => sum + test.assertions, 0);
fs.writeFileSync(resultPath, JSON.stringify({ schema: 1, nonce, tests, totalAssertions }));
