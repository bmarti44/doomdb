#!/usr/bin/env node
import crypto from 'node:crypto';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../..');
const seedDir = path.join(root, 'sql/seed');
const manifest = JSON.parse(fs.readFileSync(path.join(seedDir, 'seed-manifest.json'), 'utf8'));
const priority = new Map([
  ['wadSources', 10], ['assets', 20], ['assetSources', 30],
  ['paletteTexels', 40], ['colormapTexels', 50], ['sectors', 60],
  ['vertices', 70], ['sidedefs', 80], ['linedefs', 90], ['things', 100],
  ['segs', 110], ['ssectors', 120], ['nodes', 130],
  ['rejectBytes', 140], ['blockmapBytes', 150], ['assetTexels', 160]
]);

if (!Array.isArray(manifest.files) || manifest.files.length === 0) throw new Error('seed manifest has no files');
const seen = new Set();
for (const file of manifest.files) {
  if (!/^[0-9]{3}_[a-z0-9_]+\.sql$/.test(file.path) || file.path.includes('..')) throw new Error(`unsafe seed path: ${file.path}`);
  if (seen.has(file.path)) throw new Error(`duplicate seed path: ${file.path}`);
  if (!priority.has(file.dataset)) throw new Error(`unknown seed dataset: ${file.dataset}`);
  seen.add(file.path);
  const bytes = fs.readFileSync(path.join(seedDir, file.path));
  const actual = crypto.createHash('sha256').update(bytes).digest('hex');
  if (actual !== file.sha256) throw new Error(`seed hash mismatch: ${file.path}`);
}
const diskSql = fs.readdirSync(seedDir).filter(name => name.endsWith('.sql')).sort();
if (diskSql.length !== seen.size || diskSql.some(name => !seen.has(name))) throw new Error('seed SQL files differ from manifest');
manifest.files
  .slice()
  .sort((a, b) => priority.get(a.dataset) - priority.get(b.dataset) || a.path.localeCompare(b.path, 'en'))
  .forEach(file => process.stdout.write(`${file.path}\n`));

