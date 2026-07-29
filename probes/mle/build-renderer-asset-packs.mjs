#!/usr/bin/env node
import fs from 'node:fs';
import path from 'node:path';
import process from 'node:process';

const root = path.resolve(process.argv[2] ?? '.');
const output = path.resolve(
  process.argv[3]
    ?? path.join(root, 'probes/mle/target/free-live-renderer/assets-v1'),
);
const seed = path.join(root, 'sql/seed');
const manifest = JSON.parse(
  fs.readFileSync(path.join(seed, 'seed-manifest.json'), 'utf8'),
);
if (manifest.schema !== 1 || !Array.isArray(manifest.assets)
    || !Array.isArray(manifest.files)) {
  throw new Error('invalid seed manifest');
}

const kinds = ['wall_texture', 'flat', 'sprite_patch', 'ui_patch'];
const parts = new Map(kinds.map(kind => [kind, []]));
const imageAssets = manifest.assets
  .filter(asset => kinds.includes(asset.kind))
  .sort((left, right) => left.assetId - right.assetId);
const assetById = new Map(
  manifest.assets.map(asset => [asset.assetId, asset]),
);
const texelFiles = manifest.files
  .filter(file => file.dataset === 'assetTexels')
  .sort((left, right) => left.path.localeCompare(right.path));
const seen = new Set();

const rowPattern =
  /INTO AT \(A, X, Y, C\) VALUES \((\d+), (\d+), (\d+), (-?\d+)\)/g;
for (const file of texelFiles) {
  const text = fs.readFileSync(path.join(seed, file.path), 'ascii');
  const first = rowPattern.exec(text);
  rowPattern.lastIndex = 0;
  if (!first) throw new Error(`no texels in ${file.path}`);
  const asset = assetById.get(Number(first[1]));
  if (!asset) throw new Error(`unknown asset in ${file.path}`);
  if (!kinds.includes(asset.kind)) continue;
  const encoded = Buffer.alloc(asset.width * asset.height * 2);
  let count = 0;
  for (const match of text.matchAll(rowPattern)) {
    const [assetId, x, y, color] = match.slice(1).map(Number);
    if (assetId !== asset.assetId
        || x !== count % asset.width
        || y !== Math.floor(count / asset.width)
        || color < -1 || color > 255) {
      throw new Error(`invalid texel order in ${file.path} at ${count}`);
    }
    encoded.writeUInt16BE(color + 1, count * 2);
    count += 1;
  }
  if (count !== asset.width * asset.height || count !== file.rowCount) {
    throw new Error(`texel count mismatch in ${file.path}: ${count}`);
  }
  if (seen.has(asset.assetId)) {
    throw new Error(`duplicate texel partition for asset ${asset.assetId}`);
  }
  seen.add(asset.assetId);
  parts.get(asset.kind).push(encoded);
}
if (seen.size !== imageAssets.length) {
  throw new Error(
    `asset/texel partition mismatch ${imageAssets.length}/${seen.size}`,
  );
}

fs.mkdirSync(output, {recursive: true});
for (const kind of kinds) {
  const packed = Buffer.concat(parts.get(kind));
  fs.writeFileSync(path.join(output, `${kind}.bin`), packed);
  process.stdout.write(
    `PMLE_RENDERER_ASSET_PACK|PASS|kind=${kind}|bytes=${packed.length}\n`,
  );
}
