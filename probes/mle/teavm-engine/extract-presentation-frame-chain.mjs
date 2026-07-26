import fs from 'node:fs';
import {
  oneDbRecord,
  selfTestDbOutput,
} from '../../../scripts/lib/db-output.mjs';

function extract(text, marker) {
  const row = oneDbRecord(text, `${marker}|`);
  const entries = row.split('|').slice(1).map(field => {
    const separator = field.indexOf('=');
    return separator < 1
      ? [field, '']
      : [field.slice(0, separator), field.slice(separator + 1)];
  });
  const names = entries.map(([name]) => name);
  if (new Set(names).size !== names.length) {
    throw new Error(`${marker} has a duplicate field`);
  }
  const fields = new Map(entries);
  const chain = fields.get('chain_sha256');
  if (!/^[0-9a-f]{64}$/.test(chain ?? '')) {
    throw new Error(`${marker} has an invalid chain_sha256`);
  }
  return chain;
}

if (process.argv[2] === '--self-test') {
  selfTestDbOutput();
  const chain = 'ab'.repeat(32);
  const valid = `noise\nMARKER|PASS|chain_sha256=${chain.slice(0,48)}\n` +
    `${chain.slice(48)}|frontier=110\n`;
  if (extract(valid, 'MARKER') !== chain) throw new Error('valid self-test failed');
  for (const invalid of [
    `${valid}MARKER|PASS|chain_sha256=${chain}\n`,
    `MARKER|PASS|chain_sha256=abc|chain_sha256=${chain}\n`,
    'MARKER|PASS|chain_sha256=abc\n',
    'noise only\n',
  ]) {
    let rejected = false;
    try {
      extract(invalid, 'MARKER');
    } catch {
      rejected = true;
    }
    if (!rejected) throw new Error('adversarial self-test was accepted');
  }
  console.log('PASS PMLE-PRESENTATION-FRAME-CHAIN-EXTRACTOR-SELF-TEST');
} else {
  const [, , file, marker] = process.argv;
  if (!file || !marker) {
    throw new Error(
      'usage: node extract-presentation-frame-chain.mjs FILE MARKER',
    );
  }
  process.stdout.write(extract(fs.readFileSync(file, 'utf8'), marker));
}
