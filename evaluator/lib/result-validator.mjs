import fs from 'node:fs';

export function validateResult(manifestPath, resultPath, expectedNonce) {
  const manifest = JSON.parse(fs.readFileSync(manifestPath, 'utf8'));
  const result = JSON.parse(fs.readFileSync(resultPath, 'utf8'));
  if (!Array.isArray(manifest.tests) || manifest.tests.length === 0) throw new Error('zero approved tests');
  if (result.nonce !== expectedNonce) throw new Error('result nonce mismatch');
  if (!Array.isArray(result.tests) || result.tests.length === 0) throw new Error('zero discovered tests');
  const expected = new Map(manifest.tests.map((test) => [test.id, test.assertions]));
  if (expected.size !== manifest.tests.length) throw new Error('duplicate approved test id');
  const seen = new Set();
  let passedAssertions = 0;
  for (const test of result.tests) {
    if (seen.has(test.id)) throw new Error(`duplicate result id: ${test.id}`);
    seen.add(test.id);
    if (!expected.has(test.id)) throw new Error(`unknown or renamed test id: ${test.id}`);
    if (test.status !== 'passed') throw new Error(`test did not pass: ${test.id}`);
    if (!Number.isInteger(test.assertions) || test.assertions <= 0) throw new Error(`zero assertions: ${test.id}`);
    if (test.assertions !== expected.get(test.id)) throw new Error(`assertion count mismatch: ${test.id}`);
    passedAssertions += test.assertions;
  }
  if (seen.size !== expected.size) throw new Error('missing approved tests');
  const expectedAssertions = [...expected.values()].reduce((sum, count) => sum + count, 0);
  if (passedAssertions !== expectedAssertions || result.totalAssertions !== expectedAssertions) throw new Error('total assertion count mismatch');
  return { passed: expected.size, total: expected.size, assertions: expectedAssertions };
}
