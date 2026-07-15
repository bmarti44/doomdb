import crypto from 'node:crypto';
import { spawnSync } from 'node:child_process';
import fs from 'node:fs';

export function readPinnedWad(archive) {
  const result = spawnSync('unzip', ['-p', archive, 'freedoom-0.13.0/freedoom1.wad'], {
    encoding: null,
    maxBuffer: 64 * 1024 * 1024,
  });
  if (result.status !== 0 || result.stderr.length) throw new Error(`cannot read pinned WAD: ${result.stderr}`);
  return result.stdout;
}

export const sha256 = (bytes) => crypto.createHash('sha256').update(bytes).digest('hex');

export function directory(wad) {
  if (wad.toString('ascii', 0, 4) !== 'IWAD') throw new Error('expected IWAD');
  const count = wad.readUInt32LE(4);
  const offset = wad.readUInt32LE(8);
  const rows = [];
  for (let index = 0; index < count; index += 1) {
    const at = offset + index * 16;
    rows.push({
      index,
      offset: wad.readUInt32LE(at),
      size: wad.readUInt32LE(at + 4),
      name: wad.toString('ascii', at + 8, at + 16).replace(/\0.*$/s, ''),
    });
  }
  return rows;
}

export function lumpBytes(wad, row) {
  return wad.subarray(row.offset, row.offset + row.size);
}

export function wadFacts(wad) {
  const rows = directory(wad);
  const marker = rows.findIndex((row) => row.name === 'E1M1');
  const nextMarker = rows.findIndex((row, index) => index > marker && /^E\dM\d$/.test(row.name));
  const mapRows = rows.slice(marker + 1, nextMarker);
  const mapLump = (name) => {
    const row = mapRows.find((candidate) => candidate.name === name);
    if (!row) throw new Error(`missing map lump ${name}`);
    return lumpBytes(wad, row);
  };

  const thingCounts = {};
  const things = mapLump('THINGS');
  for (let at = 0; at < things.length; at += 10) {
    const type = things.readUInt16LE(at + 6);
    thingCounts[type] = (thingCounts[type] ?? 0) + 1;
  }

  const linedefSpecialCounts = {};
  const linedefs = mapLump('LINEDEFS');
  for (let at = 0; at < linedefs.length; at += 14) {
    const special = linedefs.readUInt16LE(at + 6);
    if (special) linedefSpecialCounts[special] = (linedefSpecialCounts[special] ?? 0) + 1;
  }

  const wallTextures = new Set();
  const sidedefs = mapLump('SIDEDEFS');
  for (let at = 0; at < sidedefs.length; at += 30) {
    for (const field of [4, 12, 20]) {
      const name = sidedefs.toString('ascii', at + field, at + field + 8).replace(/\0.*$/s, '');
      if (name !== '-') wallTextures.add(name);
    }
  }

  const sectorSpecialCounts = {};
  const flats = new Set();
  const sectors = mapLump('SECTORS');
  for (let at = 0; at < sectors.length; at += 26) {
    flats.add(sectors.toString('ascii', at + 4, at + 12).replace(/\0.*$/s, ''));
    flats.add(sectors.toString('ascii', at + 12, at + 20).replace(/\0.*$/s, ''));
    const special = sectors.readUInt16LE(at + 22);
    if (special) sectorSpecialCounts[special] = (sectorSpecialCounts[special] ?? 0) + 1;
  }

  return {
    rows,
    marker,
    nextMarker,
    thingCounts,
    linedefSpecialCounts,
    sectorSpecialCounts,
    wallTextures: [...wallTextures].sort(),
    flats: [...flats].sort(),
  };
}

function readTextureDirectory(bytes, pnames) {
  const result = new Map();
  const count = bytes.readUInt32LE(0);
  for (let index = 0; index < count; index += 1) {
    let at = bytes.readUInt32LE(4 + index * 4);
    const name = bytes.toString('ascii', at, at + 8).replace(/\0.*$/s, '');
    const patchCount = bytes.readUInt16LE(at + 20);
    at += 22;
    const patches = [];
    for (let patch = 0; patch < patchCount; patch += 1) {
      patches.push(pnames[bytes.readUInt16LE(at + 4)]);
      at += 10;
    }
    result.set(name, patches);
  }
  return result;
}

export function texturePatches(wad) {
  const rows = directory(wad);
  const last = (name) => [...rows].reverse().find((row) => row.name === name);
  const pnamesBytes = lumpBytes(wad, last('PNAMES'));
  const pnames = [];
  for (let index = 0; index < pnamesBytes.readUInt32LE(0); index += 1) {
    pnames.push(pnamesBytes.toString('ascii', 4 + index * 8, 12 + index * 8).replace(/\0.*$/s, ''));
  }
  const textures = new Map();
  for (const lump of ['TEXTURE1', 'TEXTURE2']) {
    const row = last(lump);
    if (row) for (const [name, patches] of readTextureDirectory(lumpBytes(wad, row), pnames)) textures.set(name, patches);
  }
  return textures;
}

export function deriveRng() {
  const values = [];
  for (let counter = 0; values.length < 256; counter += 1) {
    const label = `DoomDB project RNG v1|${String(counter).padStart(4, '0')}`;
    values.push(...crypto.createHash('sha256').update(label, 'ascii').digest());
  }
  return values.slice(0, 256);
}

export function loadJson(file) {
  return JSON.parse(fs.readFileSync(file, 'utf8'));
}
