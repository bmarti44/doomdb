#!/usr/bin/env node
import fs from 'node:fs';
import path from 'node:path';
import process from 'node:process';

const [root, outputDirectory] = process.argv.slice(2);
if (!root || !outputDirectory) {
  throw new Error('usage: ROOT OUTPUT_DIRECTORY');
}

const assetSql = fs.readFileSync(
  path.join(root, 'sql/seed/140_assets.sql'),
  'utf8',
);
const supported = new Set([
  'wall_texture', 'flat', 'sprite_patch', 'ui_patch',
]);
const assets = [];
for (const match of assetSql.matchAll(
  /VALUES \((\d+), '([^']+)', '([^']+)', (\d+), (\d+),/g,
)) {
  if (!supported.has(match[2])) continue;
  assets.push({
    id: Number(match[1]),
    kind: match[2],
    name: match[3],
    width: Number(match[4]),
    height: Number(match[5]),
  });
}

const states = new Map();
const assetsById = new Map();
for (const kind of supported) {
  const selected = assets
    .filter(asset => asset.kind === kind)
    .sort((left, right) => left.id - right.id);
  let elements = 0;
  for (const asset of selected) {
    asset.base = elements;
    elements += asset.width * asset.height;
    assetsById.set(asset.id, asset);
  }
  states.set(kind, {
    elements,
    count: 0,
    bytes: Buffer.alloc(elements * 2),
  });
}

const seedDirectory = path.join(root, 'sql/seed');
const texelFiles = fs.readdirSync(seedDirectory)
  .filter(file => /^160_asset_texels_\d+\.sql$/.test(file))
  .sort();
for (const file of texelFiles) {
  const sql = fs.readFileSync(path.join(seedDirectory, file), 'utf8');
  for (const match of sql.matchAll(
    /VALUES \((\d+), (\d+), (\d+), (-?\d+)\)/g,
  )) {
    const asset = assetsById.get(Number(match[1]));
    if (!asset) continue;
    const x = Number(match[2]);
    const y = Number(match[3]);
    const color = Number(match[4]);
    if (x < 0 || x >= asset.width || y < 0 || y >= asset.height
        || color < -1 || color > 255) {
      throw new Error(`invalid texel ${file}: ${match[0]}`);
    }
    const state = states.get(asset.kind);
    state.bytes.writeUInt16BE(
      color + 1,
      (asset.base + y * asset.width + x) * 2,
    );
    state.count += 1;
  }
}

fs.mkdirSync(outputDirectory, {recursive: true});
for (const [kind, state] of states) {
  if (state.count !== state.elements) {
    throw new Error(
      `${kind} texel count ${state.count} != ${state.elements}`,
    );
  }
  const output = path.join(outputDirectory, `${kind}.bin`);
  fs.writeFileSync(output, state.bytes);
  process.stdout.write(
    `PMLE_RENDER_ASSET_BLOB|PASS|kind=${kind}`
      + `|elements=${state.elements}|bytes=${state.bytes.length}`
      + `|output=${output}\n`,
  );
}
