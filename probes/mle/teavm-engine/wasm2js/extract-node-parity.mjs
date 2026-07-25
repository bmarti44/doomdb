import fs from 'node:fs';

function extract(text, expectedTics) {
  const prefix = 'PASS PMLE-WASM2JS-NODE-PARITY ';
  const rows = text.split(/\r?\n/).filter(line => line.startsWith(prefix));
  if (rows.length !== 1) {
    throw new Error(`expected one wasm2js Node parity terminal, found ${rows.length}`);
  }
  const fields = new Map();
  for (const token of rows[0].slice(prefix.length).split(' ')) {
    const separator = token.indexOf('=');
    if (separator < 1) throw new Error(`malformed parity token: ${token}`);
    const name = token.slice(0, separator);
    if (fields.has(name)) throw new Error(`duplicate parity field: ${name}`);
    fields.set(name, token.slice(separator + 1));
  }
  if (fields.get('tics') !== String(expectedTics)
      || fields.get('checkpoints') !== String(expectedTics + 1)
      || !/^[1-9][0-9]*$/.test(fields.get('canonical_bytes') ?? '')
      || !/^[0-9a-f]{64}$/.test(fields.get('canonical_sha256') ?? '')
      || !/^[0-9a-f]{64}$/.test(fields.get('fixture_sha256') ?? '')
      || !/^[0-9a-f]{64}$/.test(fields.get('stream_sha256') ?? '')
      || !/^[0-9a-f]{64}$/.test(fields.get('oracle_sha256') ?? '')) {
    throw new Error('malformed or wrong-length wasm2js Node parity terminal');
  }
  return Object.fromEntries(fields);
}

if (process.argv[2] === '--self-test') {
  const sha = 'ab'.repeat(32);
  const row = 'PASS PMLE-WASM2JS-NODE-PARITY tics=100 checkpoints=101'
    + ` canonical_bytes=78522 canonical_sha256=${sha}`
    + ` fixture_sha256=${sha} stream_sha256=${sha} oracle_sha256=${sha}\n`;
  if (extract(row, 100).canonical_sha256 !== sha) {
    throw new Error('wasm2js Node parity extractor self-test failed');
  }
  for (const invalid of [
    row + row,
    row.replace('tics=100', 'tics=99'),
    row.replace(`canonical_sha256=${sha}`, 'canonical_sha256=bad'),
    row.replace(' checkpoints=101', ' tics=100 checkpoints=101'),
  ]) {
    let rejected = false;
    try {
      extract(invalid, 100);
    } catch {
      rejected = true;
    }
    if (!rejected) throw new Error('invalid parity terminal was accepted');
  }
  console.log('PASS PMLE-WASM2JS-NODE-PARITY-EXTRACTOR-SELF-TEST');
} else {
  const [file, expectedText, field = 'canonical_sha256'] =
    process.argv.slice(2);
  const expected = Number(expectedText);
  if (!file || !Number.isInteger(expected) || expected < 0) {
    throw new Error(
      'usage: extract-node-parity.mjs LOG EXPECTED_TICS [FIELD]',
    );
  }
  const fields = extract(fs.readFileSync(file, 'utf8'), expected);
  if (!Object.hasOwn(fields, field)) {
    throw new Error(`unknown parity field: ${field}`);
  }
  process.stdout.write(fields[field]);
}
