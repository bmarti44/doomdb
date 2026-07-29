#!/usr/bin/env node

import fs from 'node:fs';

const [artifactPath, requiredExport] = process.argv.slice(2);
if (!artifactPath || !requiredExport) {
  throw new Error(
    'usage: verify-native-byte-array-view.mjs ARTIFACT REQUIRED_EXPORT');
}
const source = fs.readFileSync(artifactPath, 'utf8');
if (!source.includes(requiredExport)) {
  throw new Error(`missing native-view export: ${requiredExport}`);
}

// @JSByRef on the native method parameter must pass TeaVM's primitive-array
// typed backing directly. Fail the build if TeaVM reintroduces an argument
// conversion or the zero-copy view shape disappears.
const viewPattern =
  /new Uint8Array\(([A-Za-z_$][A-Za-z0-9_$]*)\.buffer,\s*\1\.byteOffset,\s*\1\.byteLength\)/;
if (!viewPattern.test(source)) {
  throw new Error('TeaVM @JSByRef primitive-array native-view shape is absent');
}
process.stdout.write(
  `PMLE_NATIVE_BYTE_ARRAY_VIEW_FENCE|PASS|export=${requiredExport}\n`);
