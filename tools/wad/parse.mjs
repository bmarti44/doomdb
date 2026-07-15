#!/usr/bin/env node
import fs from 'node:fs';
import { parseWad, WadError } from './parser.mjs';

function argument(name) {
  const at = process.argv.indexOf(name);
  return at >= 0 ? process.argv[at + 1] : undefined;
}

try {
  const file = argument('--wad');
  const map = argument('--map');
  if (!file || !map) throw new WadError('WAD_USAGE');
  const result = parseWad(fs.readFileSync(file), map.toUpperCase());
  process.stdout.write(`${JSON.stringify(result)}\n`);
} catch (error) {
  const code = error instanceof WadError ? error.code : 'WAD_IO';
  process.stderr.write(`ERROR ${code}\n`);
  process.exitCode = 2;
}
