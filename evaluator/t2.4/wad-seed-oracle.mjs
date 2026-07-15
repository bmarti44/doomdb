import crypto from 'node:crypto';
import { spawnSync } from 'node:child_process';

export const sha256 = (value) => crypto.createHash('sha256').update(value).digest('hex');

export function readPinnedWad(archive) {
  const result = spawnSync('unzip', ['-p', archive, 'freedoom-0.13.0/freedoom1.wad'], {
    encoding: null,
    maxBuffer: 64 * 1024 * 1024,
  });
  if (result.status !== 0 || result.stderr.length !== 0) throw new Error(`cannot extract pinned WAD: ${result.stderr}`);
  return result.stdout;
}

export function directory(wad) {
  const count = wad.readUInt32LE(4);
  const directoryOffset = wad.readUInt32LE(8);
  const occurrences = new Map();
  return Array.from({ length: count }, (_, index) => {
    const at = directoryOffset + index * 16;
    const name = wad.toString('ascii', at + 8, at + 16).replace(/\0.*$/s, '');
    const occurrence = occurrences.get(name) ?? 0;
    occurrences.set(name, occurrence + 1);
    const offset = wad.readUInt32LE(at);
    const size = wad.readUInt32LE(at + 4);
    const bytes = wad.subarray(offset, offset + size);
    return { index, name, occurrence, offset, size, sha256: sha256(bytes), bytes };
  });
}

export function last(rows, name) {
  const row = [...rows].reverse().find((candidate) => candidate.name === name);
  if (!row) throw new Error(`missing lump ${name}`);
  return row;
}

export function mapRows(rows, marker = 'E1M1') {
  const start = rows.findIndex((row) => row.name === marker);
  const end = rows.findIndex((row, index) => index > start && /^E\dM\d$/.test(row.name));
  if (start < 0 || end < 0) throw new Error(`cannot confine ${marker}`);
  return rows.slice(start, end);
}

export function patchImage(bytes) {
  const width = bytes.readUInt16LE(0);
  const height = bytes.readUInt16LE(2);
  const pixels = new Int16Array(width * height).fill(-1);
  for (let x = 0; x < width; x += 1) {
    let at = bytes.readUInt32LE(8 + x * 4);
    let previousTop = -1;
    while (bytes[at] !== 255) {
      let top = bytes[at];
      const length = bytes[at + 1];
      if (top <= previousTop) top += previousTop;
      previousTop = top;
      at += 3;
      for (let y = 0; y < length; y += 1) if (top + y < height) pixels[(top + y) * width + x] = bytes[at + y];
      at += length + 1;
    }
  }
  return { width, height, pixels };
}

export function textureDefinitions(rows) {
  const pnamesBytes = last(rows, 'PNAMES').bytes;
  const pnames = Array.from({ length: pnamesBytes.readUInt32LE(0) }, (_, index) =>
    pnamesBytes.toString('ascii', 4 + index * 8, 12 + index * 8).replace(/\0.*$/s, ''));
  const textures = new Map();
  for (const lumpName of ['TEXTURE1', 'TEXTURE2']) {
    const bytes = last(rows, lumpName).bytes;
    for (let index = 0; index < bytes.readUInt32LE(0); index += 1) {
      let at = bytes.readUInt32LE(4 + index * 4);
      const name = bytes.toString('ascii', at, at + 8).replace(/\0.*$/s, '');
      const width = bytes.readUInt16LE(at + 12);
      const height = bytes.readUInt16LE(at + 14);
      const patchCount = bytes.readUInt16LE(at + 20);
      at += 22;
      const patches = [];
      for (let patch = 0; patch < patchCount; patch += 1) {
        patches.push({ x: bytes.readInt16LE(at), y: bytes.readInt16LE(at + 2), name: pnames[bytes.readUInt16LE(at + 4)] });
        at += 10;
      }
      textures.set(name, { name, width, height, patches });
    }
  }
  return textures;
}

export function composedTexture(rows, name) {
  const definition = textureDefinitions(rows).get(name);
  if (!definition) throw new Error(`missing texture ${name}`);
  const pixels = new Int16Array(definition.width * definition.height).fill(-1);
  for (const placement of definition.patches) {
    const patch = patchImage(last(rows, placement.name).bytes);
    for (let y = 0; y < patch.height; y += 1) for (let x = 0; x < patch.width; x += 1) {
      const targetX = x + placement.x;
      const targetY = y + placement.y;
      const value = patch.pixels[y * patch.width + x];
      if (value >= 0 && targetX >= 0 && targetX < definition.width && targetY >= 0 && targetY < definition.height) {
        pixels[targetY * definition.width + targetX] = value;
      }
    }
  }
  return { ...definition, pixels };
}

export function texel(image, x, y) {
  return image.pixels[y * image.width + x];
}

export function texelHash(image) {
  const bytes = Buffer.alloc(image.pixels.length * 2);
  for (let index = 0; index < image.pixels.length; index += 1) bytes.writeInt16LE(image.pixels[index], index * 2);
  return sha256(bytes);
}
