import fs from 'node:fs';

function extract(text, expectedTics) {
  const marker = 'PMLE_WASM2JS_MLE_PARITY';
  const rows = text.split(/\r?\n/)
    .filter(line => line.startsWith(`${marker}|`));
  if (rows.length !== 1) {
    throw new Error(`expected one ${marker}, found ${rows.length}`);
  }
  const tokens = rows[0].split('|').slice(1);
  if (tokens.shift() !== 'PASS') {
    throw new Error('MLE parity terminal is not PASS');
  }
  const fields = new Map();
  for (const token of tokens) {
    const separator = token.indexOf('=');
    if (separator < 1) throw new Error(`malformed MLE parity token: ${token}`);
    const name = token.slice(0, separator);
    if (fields.has(name)) throw new Error(`duplicate MLE parity field: ${name}`);
    fields.set(name, token.slice(separator + 1));
  }
  if (fields.size !== 3
      || fields.get('tics') !== String(expectedTics)
      || !/^[1-9][0-9]*$/.test(fields.get('canonical_bytes') ?? '')
      || !/^[0-9a-f]{64}$/.test(fields.get('canonical_sha256') ?? '')) {
    throw new Error('malformed MLE parity terminal');
  }
  return Object.fromEntries(fields);
}

if (process.argv[2] === '--self-test') {
  const sha = 'cd'.repeat(32);
  const row = 'PMLE_WASM2JS_MLE_PARITY|PASS|tics=100'
    + `|canonical_bytes=78522|canonical_sha256=${sha}\n`;
  if (extract(row, 100).canonical_sha256 !== sha) {
    throw new Error('MLE parity extractor self-test failed');
  }
  for (const invalid of [
    row + row,
    row.replace('|tics=100', '|tics=99'),
    row.replace(`canonical_sha256=${sha}`, 'canonical_sha256=bad'),
    row.replace('|canonical_bytes=', '|tics=100|canonical_bytes='),
    row.replace('|canonical_bytes=78522', '|extra=1|canonical_bytes=78522'),
  ]) {
    let rejected = false;
    try {
      extract(invalid, 100);
    } catch {
      rejected = true;
    }
    if (!rejected) throw new Error('invalid MLE parity terminal was accepted');
  }
  console.log('PASS PMLE-WASM2JS-MLE-PARITY-EXTRACTOR-SELF-TEST');
} else {
  const [file, expectedText, field = 'canonical_sha256'] =
    process.argv.slice(2);
  const expected = Number(expectedText);
  if (!file || !Number.isInteger(expected) || expected < 0) {
    throw new Error(
      'usage: extract-mle-parity.mjs LOG EXPECTED_TICS [FIELD]',
    );
  }
  const fields = extract(fs.readFileSync(file, 'utf8'), expected);
  if (!Object.hasOwn(fields, field)) {
    throw new Error(`unknown MLE parity field: ${field}`);
  }
  process.stdout.write(fields[field]);
}
