import assert from 'node:assert/strict';

export const sqlclWideOutput = [
  'set heading off feedback off pagesize 0 linesize 32767',
  'set trimspool on tab off',
].join('\n');

export function normalizeDbOutput(input) {
  const physical = String(input).replaceAll('\r\n', '\n').replaceAll('\r', '\n')
    .split('\n');
  const logical = [];
  for (const raw of physical) {
    const line = raw.trimEnd();
    if (line.trim() === '' || /^Session altered\.$/.test(line.trim())) continue;
    if (/^[A-Z][A-Z0-9_]*[|]/.test(line)) {
      logical.push(line);
    } else if (logical.length > 0 && !/^(ORA-|SP2-|PLS-)/.test(line.trim())) {
      // Historical SQLcl evidence may be hard-wrapped despite the wide-output
      // contract. Continuations are concatenated exactly; marker values never
      // contain intentional physical newlines.
      logical[logical.length - 1] += line.trim();
    } else {
      logical.push(line.trim());
    }
  }
  return logical;
}

export function oneDbRecord(input, prefix) {
  assert.match(prefix, /^[A-Z][A-Z0-9_]*[|]$/);
  const matches = normalizeDbOutput(input).filter(line => line.startsWith(prefix));
  assert.equal(matches.length, 1,
    `expected exactly one ${prefix} record, found ${matches.length}`);
  return matches[0];
}

export function selfTestDbOutput() {
  const wrapped = [
    'Session altered.\r',
    '\r',
    'PMLE_FIXTURE|PASS|sha=0123456789abcdef0123456789abcdef0123456789abcdef0123\r',
    '456789abcdef|bytes=1081335\r',
  ].join('\n');
  assert.equal(oneDbRecord(wrapped, 'PMLE_FIXTURE|'),
    'PMLE_FIXTURE|PASS|sha=0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef|bytes=1081335');
  assert.throws(() => oneDbRecord(
    'PMLE_FIXTURE|PASS|n=1\nPMLE_FIXTURE|PASS|n=2\n', 'PMLE_FIXTURE|'));
  assert.deepEqual(normalizeDbOutput('ORA-00060: deadlock\n'), [
    'ORA-00060: deadlock',
  ]);
}

