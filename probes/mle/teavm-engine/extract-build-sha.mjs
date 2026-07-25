import fs from 'node:fs';

function extract(text, marker, field, kind = 'sha256') {
  const rows = text.split(/\r?\n/)
    .filter(line => line.startsWith(`${marker} `));
  if (rows.length !== 1) {
    throw new Error(`expected exactly one ${marker}, found ${rows.length}`);
  }
  const values = rows[0].split(/\s+/).slice(2)
    .filter(token => token.startsWith(`${field}=`))
    .map(token => token.slice(field.length + 1));
  const valid = kind === 'sha256'
    ? value => /^[0-9a-f]{64}$/.test(value)
    : kind === 'token'
      ? value => /^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$/.test(value)
      : kind === 'integer'
        ? value => /^[1-9][0-9]*$/.test(value)
        : null;
  if (valid === null) {
    throw new Error(`unsupported extraction kind: ${kind}`);
  }
  if (values.length !== 1 || !valid(values[0])) {
    throw new Error(`${marker} has invalid or ambiguous ${field}`);
  }
  return values[0];
}

if (process.argv[2] === '--self-test') {
  const sha = '12'.repeat(32);
  const marker = 'PASS BUILD';
  const valid = `${marker} bytes=1 input_sha=${sha} other=ok\n`;
  if (extract(valid, marker, 'input_sha') !== sha) {
    throw new Error('valid build SHA extraction failed');
  }
  const tokenMarker = `${marker} classification=UNPROMOTED_CANDIDATE `
    + 'candidate_reason=decps-promotion-rebuild\n';
  if (extract(tokenMarker, marker, 'classification', 'token')
      !== 'UNPROMOTED_CANDIDATE'
      || extract(tokenMarker, marker, 'candidate_reason', 'token')
      !== 'decps-promotion-rebuild'
      || extract(valid, marker, 'bytes', 'integer') !== '1') {
    throw new Error('valid typed build-field extraction failed');
  }
  for (const invalid of [
    `${valid}${valid}`,
    `${marker} bytes=1 input_sha=abc\n`,
    `${marker} bytes=1 other=${sha}\n`,
    `${marker} input_sha=${sha} input_sha=${sha}\n`,
  ]) {
    let rejected = false;
    try {
      extract(invalid, marker, 'input_sha');
    } catch {
      rejected = true;
    }
    if (!rejected) throw new Error('invalid build marker was accepted');
  }
  for (const invalid of [
    `${tokenMarker}${tokenMarker}`,
    `${marker} classification=bad/value\n`,
    `${marker} classification=OK classification=OK\n`,
  ]) {
    let rejected = false;
    try {
      extract(invalid, marker, 'classification', 'token');
    } catch {
      rejected = true;
    }
    if (!rejected) throw new Error('invalid build token was accepted');
  }
  for (const invalid of [
    `${marker} bytes=0\n`,
    `${marker} bytes=-1\n`,
    `${marker} bytes=1.5\n`,
    `${marker} bytes=1 bytes=2\n`,
  ]) {
    let rejected = false;
    try {
      extract(invalid, marker, 'bytes', 'integer');
    } catch {
      rejected = true;
    }
    if (!rejected) throw new Error('invalid build integer was accepted');
  }
  let unsupportedRejected = false;
  try {
    extract(tokenMarker, marker, 'classification', 'anything');
  } catch {
    unsupportedRejected = true;
  }
  if (!unsupportedRejected) {
    throw new Error('unsupported extraction kind was accepted');
  }
  console.log('PASS PMLE-BUILD-SHA-EXTRACTOR-SELF-TEST');
} else {
  const [, , file, marker, field, kind = 'sha256'] = process.argv;
  if (!file || !marker || !field) {
    throw new Error(
      'usage: extract-build-sha.mjs FILE MARKER FIELD [sha256|token|integer]',
    );
  }
  process.stdout.write(
    extract(fs.readFileSync(file, 'utf8'), marker, field, kind),
  );
}
