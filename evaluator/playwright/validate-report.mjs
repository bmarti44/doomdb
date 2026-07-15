import fs from 'node:fs';

export function validatePlaywrightReport(report, approved) {
  const observed = new Map();
  const failures = [];
  const visit = (suite) => {
    for (const spec of suite.specs || []) {
      const match = /^\[([^\]]+)\]/.exec(spec.title || '');
      if (!match) {
        failures.push(`missing test id: ${spec.title || '<untitled>'}`);
        continue;
      }
      const id = match[1];
      if (observed.has(id)) failures.push(`duplicate test id: ${id}`);
      const tests = spec.tests || [];
      if (tests.length !== 1) failures.push(`${id}: expected exactly one Chromium test`);
      const test = tests[0] || {};
      if (test.projectName !== 'chromium') failures.push(`${id}: unexpected project`);
      if (test.expectedStatus !== 'passed' || test.status !== 'expected') failures.push(`${id}: skip, fixme, or failure`);
      if ((test.results || []).length !== 1 || test.results[0]?.status !== 'passed') failures.push(`${id}: retry or non-pass result`);
      const annotation = (test.annotations || []).find((item) => item.type === 'doom-assertions');
      const assertions = Number(annotation?.description);
      if (!Number.isInteger(assertions) || assertions <= 0) failures.push(`${id}: missing assertion count annotation`);
      observed.set(id, assertions);
    }
    for (const child of suite.suites || []) visit(child);
  };
  for (const suite of report.suites || []) visit(suite);
  if ((report.errors || []).length) failures.push('top-level Playwright errors');
  const expected = new Map(approved.tests.map((test) => [test.id, test.assertions]));
  if (observed.size === 0) failures.push('zero discovered tests');
  for (const [id, count] of expected) {
    if (!observed.has(id)) failures.push(`missing approved test: ${id}`);
    else if (observed.get(id) !== count) failures.push(`${id}: assertion count mismatch`);
  }
  for (const id of observed.keys()) if (!expected.has(id)) failures.push(`unknown test id: ${id}`);
  if (failures.length) throw new Error(failures.join('\n'));
  return { passed: observed.size, total: expected.size };
}

if (process.argv[1]?.endsWith('validate-report.mjs')) {
  if (process.argv.length !== 4) throw new Error('usage: validate-report.mjs REPORT.json MANIFEST.json');
  const summary = validatePlaywrightReport(JSON.parse(fs.readFileSync(process.argv[2], 'utf8')), JSON.parse(fs.readFileSync(process.argv[3], 'utf8')));
  process.stdout.write(`${JSON.stringify(summary)}\n`);
}
