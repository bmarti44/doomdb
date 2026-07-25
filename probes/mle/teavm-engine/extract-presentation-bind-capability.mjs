import fs from 'node:fs';

const marker = 'PMLE_PRESENTATION_BIND_INSTALL';

function extractFields(text) {
  const rows = text.split(/\r?\n/)
    .filter(line => line.startsWith(`${marker}|`));
  if (rows.length !== 1) {
    throw new Error(`expected exactly one ${marker}, found ${rows.length}`);
  }
  const entries = rows[0].split('|').slice(1).map(token => {
    const separator = token.indexOf('=');
    return separator < 1
      ? [token, '']
      : [token.slice(0, separator), token.slice(separator + 1)];
  });
  const names = entries.map(([name]) => name);
  if (new Set(names).size !== names.length) {
    throw new Error('duplicate presentation bind capability field');
  }
  const fields = Object.fromEntries(entries);
  if (!Object.hasOwn(fields, 'PASS')
      || fields.transports !==
        'direct_uint8array_blob_insert,persistent_returning_oracle_blob'
      || !['YES', 'NO'].includes(fields.direct_supported)
      || ![
        'explicit_db_type_blob',
        'implicit_target_blob',
        'UNSUPPORTED',
      ].includes(fields.direct_mode)
      || (fields.direct_supported === 'YES'
        && fields.direct_mode === 'UNSUPPORTED')
      || (fields.direct_supported === 'NO'
        && fields.direct_mode !== 'UNSUPPORTED')
      || fields.frame_bytes !== '64000'
      || fields.imports !== '1'
      || !/^[1-9][0-9]*$/.test(fields.source_bytes ?? '')
      || !/^[0-9a-f]{64}$/.test(fields.source_sha256 ?? '')
      || !/^[0-9a-f]{64}$/.test(fields.engine_sha256 ?? '')) {
    throw new Error('malformed presentation bind capability marker');
  }
  return fields;
}

function extract(text) {
  const fields = extractFields(text);
  return fields.direct_supported === 'YES'
    ? 'direct_uint8array_blob_insert'
    : 'persistent_returning_oracle_blob';
}

if (process.argv[2] === '--self-test') {
  const sha = 'ab'.repeat(32);
  const row = `${marker}|PASS`
    + '|transports=direct_uint8array_blob_insert,persistent_returning_oracle_blob'
    + '|direct_supported=YES|direct_mode=implicit_target_blob'
    + '|frame_bytes=64000|imports=1|source_bytes=123'
    + `|source_sha256=${sha}|engine_sha256=${sha}\n`;
  if (extract(row) !== 'direct_uint8array_blob_insert'
      || extractFields(row).direct_mode !== 'implicit_target_blob'
      || extract(row.replace(
        'direct_supported=YES|direct_mode=implicit_target_blob',
        'direct_supported=NO|direct_mode=UNSUPPORTED',
      )) !== 'persistent_returning_oracle_blob') {
    throw new Error('presentation bind capability selection failed');
  }
  for (const invalid of [
    row + row,
    row.replace('direct_supported=YES', 'direct_supported=MAYBE'),
    row.replace(
      '|direct_supported=YES|',
      '|direct_supported=NO|direct_supported=YES|',
    ),
    row.replace(`|source_sha256=${sha}`, '|source_sha256=abc'),
    row.replace(
      'direct_supported=YES|direct_mode=implicit_target_blob',
      'direct_supported=NO|direct_mode=implicit_target_blob',
    ),
  ]) {
    let rejected = false;
    try {
      extract(invalid);
    } catch {
      rejected = true;
    }
    if (!rejected) {
      throw new Error('invalid presentation bind capability was accepted');
    }
  }
  console.log('PASS PMLE-PRESENTATION-BIND-CAPABILITY-SELF-TEST');
} else {
  const modeOnly = process.argv[2] === '--mode';
  const file = process.argv[modeOnly ? 3 : 2];
  if (!file) {
    throw new Error(
      'usage: extract-presentation-bind-capability.mjs ' +
        '[--mode] INSTALL_LOG',
    );
  }
  const text = fs.readFileSync(file, 'utf8');
  process.stdout.write(
    modeOnly ? extractFields(text).direct_mode : extract(text),
  );
}
