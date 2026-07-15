import crypto from 'node:crypto';

export class WadError extends Error {
  code: string;

  constructor(code: string) {
    super(code);
    this.code = code;
  }
}

function fail(code) {
  throw new WadError(code);
}

export class BinaryReader {
  bytes: Uint8Array;
  defaultCode: string;
  view: DataView;

  constructor(bytes: Uint8Array, defaultCode = 'WAD_LUMP_BOUNDS') {
    this.bytes = bytes;
    this.defaultCode = defaultCode;
    this.view = new DataView(bytes.buffer, bytes.byteOffset, bytes.byteLength);
  }

  require(offset, length, code = this.defaultCode) {
    if (!Number.isSafeInteger(offset) || !Number.isSafeInteger(length) || offset < 0 || length < 0 || offset > this.bytes.length - length) fail(code);
  }

  u8(offset, code) { this.require(offset, 1, code); return this.view.getUint8(offset); }
  u16(offset, code) { this.require(offset, 2, code); return this.view.getUint16(offset, true); }
  i16(offset, code) { this.require(offset, 2, code); return this.view.getInt16(offset, true); }
  u32(offset, code) { this.require(offset, 4, code); return this.view.getUint32(offset, true); }
  slice(offset, length, code) { this.require(offset, length, code); return this.bytes.subarray(offset, offset + length); }

  name(offset, code) {
    const raw = this.slice(offset, 8, code);
    let end = raw.indexOf(0);
    if (end < 0) end = 8;
    let value = '';
    for (let i = 0; i < end; i += 1) value += String.fromCharCode(raw[i]);
    return value;
  }
}

const sha256 = (bytes) => crypto.createHash('sha256').update(bytes).digest('hex');
const isMapMarker = (name) => /^(?:E\dM\d|MAP\d\d)$/.test(name);

function exactRecords(bytes, size, code) {
  if (bytes.length % size !== 0) fail(code);
  return bytes.length / size;
}

function directoryFrom(bytes) {
  const reader = new BinaryReader(bytes, 'WAD_DIRECTORY_BOUNDS');
  if (bytes.length < 4) fail('WAD_BAD_MAGIC');
  const kind = String.fromCharCode(...bytes.subarray(0, 4));
  if (kind !== 'IWAD' && kind !== 'PWAD') fail('WAD_BAD_MAGIC');
  if (bytes.length < 12) fail('WAD_DIRECTORY_BOUNDS');
  const count = reader.u32(4);
  const offset = reader.u32(8);
  if (count > Math.floor((bytes.length - Math.min(offset, bytes.length)) / 16) || offset > bytes.length || count * 16 > bytes.length - offset) fail('WAD_DIRECTORY_BOUNDS');

  const occurrences = new Map();
  const directory = [];
  for (let i = 0; i < count; i += 1) {
    const at = offset + i * 16;
    const lumpOffset = reader.u32(at);
    const size = reader.u32(at + 4);
    const name = reader.name(at + 8);
    if (lumpOffset > bytes.length || size > bytes.length - lumpOffset) fail('WAD_LUMP_BOUNDS');
    const occurrenceIndex = occurrences.get(name) ?? 0;
    occurrences.set(name, occurrenceIndex + 1);
    const data = bytes.subarray(lumpOffset, lumpOffset + size);
    directory.push({ name, offset: lumpOffset, size, occurrenceIndex, sha256: sha256(data), data });
  }
  return { kind, directory };
}

function lastNamed(directory, name) {
  for (let i = directory.length - 1; i >= 0; i -= 1) if (directory[i].name === name) return directory[i];
  return undefined;
}

function mapDirectory(directory, marker) {
  const start = directory.findIndex((entry) => entry.name === marker && isMapMarker(entry.name));
  if (start < 0) fail('WAD_MAP_NOT_FOUND');
  let end = directory.length;
  for (let i = start + 1; i < directory.length; i += 1) {
    if (isMapMarker(directory[i].name)) { end = i; break; }
  }
  const rows = directory.slice(start + 1, end);
  const get = (name, code = `WAD_${name}_MISSING`) => {
    const found = lastNamed(rows, name);
    if (!found) fail(code);
    return found.data;
  };
  return { rows, get, nextMarker: end < directory.length ? directory[end].name : null };
}

function parseThings(bytes) {
  const count = exactRecords(bytes, 10, 'WAD_THINGS_SIZE');
  const r = new BinaryReader(bytes, 'WAD_THINGS_SIZE');
  return Array.from({ length: count }, (_, id) => {
    const at = id * 10;
    const flags = r.u16(at + 8);
    return {
      id, x: r.i16(at), y: r.i16(at + 2), angle: r.u16(at + 4), type: r.u16(at + 6), flags,
      easy: (flags & 0x01) !== 0, medium: (flags & 0x02) !== 0, hard: (flags & 0x04) !== 0,
      ambush: (flags & 0x08) !== 0, notSinglePlayer: (flags & 0x10) !== 0,
      unknownFlagBits: flags & ~0x1f,
    };
  });
}

function parseVertexes(bytes) {
  const count = exactRecords(bytes, 4, 'WAD_VERTEXES_SIZE');
  const r = new BinaryReader(bytes, 'WAD_VERTEXES_SIZE');
  return Array.from({ length: count }, (_, id) => ({ id, x: r.i16(id * 4), y: r.i16(id * 4 + 2) }));
}

function parseLinedefs(bytes, vertexCount) {
  const count = exactRecords(bytes, 14, 'WAD_LINEDEFS_SIZE');
  const r = new BinaryReader(bytes, 'WAD_LINEDEFS_SIZE');
  return Array.from({ length: count }, (_, id) => {
    const at = id * 14;
    const v1 = r.u16(at), v2 = r.u16(at + 2);
    if (v1 >= vertexCount || v2 >= vertexCount) fail('WAD_LINEDEF_VERTEX_REF');
    const leftRaw = r.u16(at + 12);
    return { id, v1, v2, flags: r.u16(at + 4), special: r.u16(at + 6), tag: r.u16(at + 8), right: r.u16(at + 10), left: leftRaw === 0xffff ? null : leftRaw };
  });
}

function parseSidedefs(bytes, sectorCount) {
  const count = exactRecords(bytes, 30, 'WAD_SIDEDEFS_SIZE');
  const r = new BinaryReader(bytes, 'WAD_SIDEDEFS_SIZE');
  return Array.from({ length: count }, (_, id) => {
    const at = id * 30, sector = r.u16(at + 28);
    if (sector >= sectorCount) fail('WAD_SIDEDEF_SECTOR_REF');
    return { id, xOffset: r.i16(at), yOffset: r.i16(at + 2), upper: r.name(at + 4), lower: r.name(at + 12), middle: r.name(at + 20), sector };
  });
}

function validateLinedefSides(linedefs, sidedefCount) {
  for (const line of linedefs) {
    if (line.right !== 0xffff && line.right >= sidedefCount) fail('WAD_LINEDEF_SIDEDEF_REF');
    if (line.left !== null && line.left >= sidedefCount) fail('WAD_LINEDEF_SIDEDEF_REF');
  }
}

function parseSectors(bytes) {
  const count = exactRecords(bytes, 26, 'WAD_SECTORS_SIZE');
  const r = new BinaryReader(bytes, 'WAD_SECTORS_SIZE');
  return Array.from({ length: count }, (_, id) => {
    const at = id * 26;
    return { id, floor: r.i16(at), ceiling: r.i16(at + 2), floorFlat: r.name(at + 4), ceilingFlat: r.name(at + 12), light: r.u16(at + 20), special: r.u16(at + 22), tag: r.u16(at + 24) };
  });
}

function parseSegs(bytes, vertexCount, linedefCount) {
  const count = exactRecords(bytes, 12, 'WAD_SEGS_SIZE');
  const r = new BinaryReader(bytes, 'WAD_SEGS_SIZE');
  return Array.from({ length: count }, (_, id) => {
    const at = id * 12, start = r.u16(at), end = r.u16(at + 2), linedef = r.u16(at + 6);
    if (start >= vertexCount || end >= vertexCount) fail('WAD_SEG_VERTEX_REF');
    if (linedef >= linedefCount) fail('WAD_SEG_LINEDEF_REF');
    const direction = r.u16(at + 8);
    if (direction > 1) fail('WAD_SEG_DIRECTION');
    return { id, start, end, angle: r.u16(at + 4), linedef, direction, offset: r.u16(at + 10) };
  });
}

function parseSsectors(bytes, segCount) {
  const count = exactRecords(bytes, 4, 'WAD_SSECTORS_SIZE');
  const r = new BinaryReader(bytes, 'WAD_SSECTORS_SIZE');
  return Array.from({ length: count }, (_, id) => {
    const at = id * 4, segCountHere = r.u16(at), firstSeg = r.u16(at + 2);
    if (firstSeg > segCount || segCountHere > segCount - firstSeg) fail('WAD_SSECTOR_SEG_RANGE');
    return { id, segCount: segCountHere, firstSeg };
  });
}

function parseNodes(bytes, ssectorCount) {
  const count = exactRecords(bytes, 28, 'WAD_NODES_SIZE');
  const r = new BinaryReader(bytes, 'WAD_NODES_SIZE');
  const nodes = Array.from({ length: count }, (_, id) => {
    const at = id * 28;
    const bbox = (p) => ({ top: r.i16(p), bottom: r.i16(p + 2), left: r.i16(p + 4), right: r.i16(p + 6) });
    const child = (raw) => ({ subsector: (raw & 0x8000) !== 0, id: raw & 0x7fff });
    return { id, x: r.i16(at), y: r.i16(at + 2), dx: r.i16(at + 4), dy: r.i16(at + 6), bboxes: [bbox(at + 8), bbox(at + 16)], children: [child(r.u16(at + 24)), child(r.u16(at + 26))] };
  });
  for (const node of nodes) for (const child of node.children) {
    if ((child.subsector && child.id >= ssectorCount) || (!child.subsector && child.id >= count)) fail('WAD_NODE_CHILD_REF');
  }
  return nodes;
}

function parseReject(bytes, sectorCount) {
  const bitCount = sectorCount * sectorCount;
  const byteCount = Math.ceil(bitCount / 8);
  if (bytes.length < byteCount) fail('WAD_REJECT_SIZE');
  const bits = Array.from({ length: bitCount }, (_, bit) => (bytes[bit >> 3] & (1 << (bit & 7))) !== 0);
  return { sectorCount, bits };
}

function parseBlockmap(bytes, linedefCount) {
  if (bytes.length < 8 || bytes.length % 2 !== 0) fail('WAD_BLOCKMAP_SIZE');
  const r = new BinaryReader(bytes, 'WAD_BLOCKMAP_OFFSET');
  const originX = r.i16(0), originY = r.i16(2), columns = r.u16(4), rows = r.u16(6);
  const cellCount = columns * rows;
  if (!Number.isSafeInteger(cellCount) || cellCount > (bytes.length - 8) / 2) fail('WAD_BLOCKMAP_OFFSET');
  const tableEndWords = 4 + cellCount;
  const cells = [];
  for (let cell = 0; cell < cellCount; cell += 1) {
    const offsetWords = r.u16(8 + cell * 2);
    if (offsetWords < tableEndWords || offsetWords >= bytes.length / 2) fail('WAD_BLOCKMAP_OFFSET');
    let cursor = offsetWords * 2;
    if (r.u16(cursor) !== 0) fail('WAD_BLOCKMAP_OFFSET');
    cursor += 2;
    const lines = [];
    for (;;) {
      if (cursor + 2 > bytes.length) fail('WAD_BLOCKMAP_OFFSET');
      const line = r.u16(cursor); cursor += 2;
      if (line === 0xffff) break;
      if (line >= linedefCount) fail('WAD_BLOCKMAP_LINEDEF_REF');
      lines.push(line);
    }
    cells.push(lines);
  }
  return { originX, originY, columns, rows, cells };
}

function parsePlaypal(bytes) {
  if (bytes.length === 0 || bytes.length % 768 !== 0) fail('WAD_PLAYPAL_SIZE');
  const palettes = Array.from({ length: bytes.length / 768 }, (_, palette) => Array.from({ length: 256 }, (_, index) => Array.from(bytes.subarray(palette * 768 + index * 3, palette * 768 + index * 3 + 3))));
  return { paletteCount: palettes.length, palette0: { index0: palettes[0][0], index255: palettes[0][255] }, palettes };
}

function parseColormap(bytes) {
  if (bytes.length === 0 || bytes.length % 256 !== 0) fail('WAD_COLORMAP_SIZE');
  const maps = Array.from({ length: bytes.length / 256 }, (_, map) => Array.from(bytes.subarray(map * 256, map * 256 + 256)));
  return { mapCount: maps.length, map0: { index0: maps[0][0], index255: maps[0][255] }, map31: maps[31] ? { index7: maps[31][7] } : null, maps };
}

function parsePnames(bytes) {
  const r = new BinaryReader(bytes, 'WAD_PNAMES_SIZE');
  if (bytes.length < 4) fail('WAD_PNAMES_SIZE');
  const count = r.u32(0);
  if (count > (bytes.length - 4) / 8 || bytes.length !== 4 + count * 8) fail('WAD_PNAMES_SIZE');
  return Array.from({ length: count }, (_, i) => r.name(4 + i * 8));
}

function parseTextureDirectory(bytes, source, patchCount) {
  const code = 'WAD_TEXTURE_SIZE';
  const r = new BinaryReader(bytes, code);
  if (bytes.length < 4) fail(code);
  const count = r.u32(0);
  if (count > (bytes.length - 4) / 4) fail(code);
  const textures = [];
  for (let i = 0; i < count; i += 1) {
    const at = r.u32(4 + i * 4);
    r.require(at, 22, code);
    const patchEntries = r.u16(at + 20);
    r.require(at + 22, patchEntries * 10, code);
    const patches = Array.from({ length: patchEntries }, (_, p) => {
      const record = at + 22 + p * 10, patch = r.u16(record + 4);
      if (patch >= patchCount) fail('WAD_TEXTURE_PATCH_REF');
      return { x: r.i16(record), y: r.i16(record + 2), patch };
    });
    const width = r.i16(at + 12), height = r.i16(at + 14);
    if (width <= 0 || height <= 0) fail(code);
    textures.push({ source, name: r.name(at), width, height, patches });
  }
  return textures;
}

function parsePatch(bytes) {
  const headerCode = 'WAD_PATCH_COLUMN_BOUNDS';
  const r = new BinaryReader(bytes, headerCode);
  if (bytes.length < 8) fail(headerCode);
  const width = r.i16(0), height = r.i16(2), leftOffset = r.i16(4), topOffset = r.i16(6);
  if (width <= 0 || height <= 0 || width > (bytes.length - 8) / 4) fail(headerCode);
  const columns = [];
  for (let x = 0; x < width; x += 1) {
    let cursor = r.u32(8 + x * 4);
    if (cursor < 8 + width * 4 || cursor >= bytes.length) fail(headerCode);
    const posts = [];
    let previousTop = -1;
    for (;;) {
      if (cursor >= bytes.length) fail('WAD_PATCH_POST_STREAM');
      const rawTop = r.u8(cursor, 'WAD_PATCH_POST_STREAM'); cursor += 1;
      if (rawTop === 0xff) break;
      if (cursor + 2 > bytes.length) fail('WAD_PATCH_POST_STREAM');
      const length = r.u8(cursor, 'WAD_PATCH_POST_STREAM'); cursor += 2;
      if (cursor + length + 1 > bytes.length) fail('WAD_PATCH_POST_STREAM');
      const top = previousTop >= 0 && rawTop <= previousTop ? previousTop + rawTop : rawTop;
      const pixels = Array.from(r.slice(cursor, length, 'WAD_PATCH_POST_STREAM'));
      cursor += length + 1;
      posts.push({ top, pixels });
      previousTop = top;
    }
    columns.push(posts);
  }
  return { width, height, leftOffset, topOffset, columns };
}

function transparentRanges(patch) {
  const covered = new Uint8Array(patch.height);
  // The compact summary describes the first column; complete per-column posts
  // remain available in `columns` and are the canonical transparency data.
  for (const post of patch.columns[0] ?? []) for (let y = post.top; y < post.top + post.pixels.length && y < patch.height; y += 1) if (y >= 0) covered[y] = 1;
  const ranges = [];
  let start = -1;
  for (let y = 0; y <= patch.height; y += 1) {
    if (y < patch.height && covered[y] === 0) { if (start < 0) start = y; }
    else if (start >= 0) { ranges.push([start, y - 1]); start = -1; }
  }
  return ranges;
}

function spriteView(name, patch) {
  const opaqueTexels = [];
  for (let x = 0; x < patch.columns.length; x += 1) for (const post of patch.columns[x]) {
    for (let p = 0; p < post.pixels.length; p += 1) opaqueTexels.push([x, post.top + p, post.pixels[p]]);
  }
  return { sprite: name.slice(0, 4), rotation: Number.parseInt(name[5] ?? '0', 10), width: patch.width, height: patch.height, leftOffset: patch.leftOffset, topOffset: patch.topOffset, opaqueTexels };
}

function namespaceEntries(directory, startNames, endNames) {
  let active = false;
  const entries = [];
  for (const entry of directory) {
    if (startNames.has(entry.name)) { active = true; continue; }
    if (endNames.has(entry.name)) { active = false; continue; }
    if (active && entry.size > 0) entries.push(entry);
  }
  return entries;
}

function parseSound(name, bytes) {
  const r = new BinaryReader(bytes, 'WAD_SOUND_SIZE');
  if (bytes.length < 8) fail('WAD_SOUND_SIZE');
  const sampleCount = r.u32(4);
  if (sampleCount !== bytes.length - 8) fail('WAD_SOUND_SIZE');
  return { name, format: r.u16(0), sampleRate: r.u16(2), sampleCount, samples: Array.from(bytes.subarray(8)) };
}

function parseMusic(name, bytes) {
  const r = new BinaryReader(bytes, 'WAD_MUSIC_SIZE');
  if (bytes.length < 4) fail('WAD_MUSIC_SIZE');
  const magic = String.fromCharCode(...bytes.subarray(0, 4));
  if (magic === 'MThd') {
    if (bytes.length < 14 || r.u32(4) !== 0x06000000) fail('WAD_MUSIC_SIZE');
    const be16 = (offset) => (r.u8(offset) << 8) | r.u8(offset + 1);
    return { name, magic, format: be16(8), trackCount: be16(10), division: be16(12), byteLength: bytes.length };
  }
  if (magic !== 'MUS\x1a') fail('WAD_MUSIC_MAGIC');
  if (bytes.length < 16) fail('WAD_MUSIC_SIZE');
  const scoreLength = r.u16(4), scoreStart = r.u16(6), instrumentCount = r.u16(12);
  if (scoreStart > bytes.length || scoreLength > bytes.length - scoreStart || 16 + instrumentCount * 2 > bytes.length) fail('WAD_MUSIC_SIZE');
  return { name, magic, scoreLength, scoreStart, primaryChannels: r.u16(8), secondaryChannels: r.u16(10), instrumentCount };
}

export function parseWad(input: Uint8Array | ArrayBuffer, marker: string): Record<string, unknown> {
  const bytes = input instanceof Uint8Array ? input : new Uint8Array(input);
  const { kind, directory } = directoryFrom(bytes);
  const map = mapDirectory(directory, marker);
  const sectors = parseSectors(map.get('SECTORS'));
  const vertexes = parseVertexes(map.get('VERTEXES'));
  const linedefs = parseLinedefs(map.get('LINEDEFS'), vertexes.length);
  const sidedefs = parseSidedefs(map.get('SIDEDEFS'), sectors.length);
  validateLinedefSides(linedefs, sidedefs.length);
  const segs = parseSegs(map.get('SEGS'), vertexes.length, linedefs.length);
  const ssectors = parseSsectors(map.get('SSECTORS'), segs.length);
  const nodes = parseNodes(map.get('NODES'), ssectors.length);
  const things = parseThings(map.get('THINGS'));
  const reject = parseReject(map.get('REJECT'), sectors.length);
  const blockmap = parseBlockmap(map.get('BLOCKMAP'), linedefs.length);

  const playpalFull = parsePlaypal(lastNamed(directory, 'PLAYPAL')?.data ?? fail('WAD_PLAYPAL_MISSING'));
  const colormapFull = parseColormap(lastNamed(directory, 'COLORMAP')?.data ?? fail('WAD_COLORMAP_MISSING'));
  const pnames = parsePnames(lastNamed(directory, 'PNAMES')?.data ?? fail('WAD_PNAMES_MISSING'));
  const textures = [];
  for (const source of ['TEXTURE1', 'TEXTURE2']) {
    const lump = lastNamed(directory, source);
    if (lump) textures.push(...parseTextureDirectory(lump.data, source, pnames.length));
  }

  const patches = {};
  for (const name of pnames) {
    const lump = lastNamed(directory, name);
    if (!lump) fail('WAD_PATCH_MISSING');
    const parsed = parsePatch(lump.data);
    patches[name] = { ...parsed, transparent: transparentRanges(parsed) };
  }
  const spriteEntries = namespaceEntries(directory, new Set(['S_START', 'SS_START']), new Set(['S_END', 'SS_END']));
  for (const entry of spriteEntries) patches[entry.name] = spriteView(entry.name, parsePatch(entry.data));

  const flatEntries = namespaceEntries(directory, new Set(['F_START', 'FF_START']), new Set(['F_END', 'FF_END']));
  const flats = flatEntries.map((entry) => {
    if (entry.size !== 4096) fail('WAD_FLAT_SIZE');
    return { name: entry.name, width: 64, height: 64, index0: entry.data[0], index4095: entry.data[4095], texels: Array.from(entry.data) };
  });
  const wantedFlat = sectors.map((s) => s.floorFlat).find((name) => flatEntries.some((entry) => entry.name === name));
  const flatFull = flats.find((item) => item.name === wantedFlat) ?? flats[0] ?? fail('WAD_FLAT_MISSING');

  const soundEntries = directory.filter((entry) => /^DS/.test(entry.name) && entry.size > 0);
  const sounds = soundEntries.map((entry) => parseSound(entry.name, entry.data));
  const soundFull = sounds.find((item) => item.name === 'DSPISTOL') ?? sounds[0] ?? fail('WAD_SOUND_MISSING');
  const musicName = `D_${marker}`;
  const musicEntry = lastNamed(directory, musicName);
  if (!musicEntry) fail('WAD_MUSIC_MISSING');
  const music = parseMusic(musicName, musicEntry.data);

  const duplicate = directory.find((entry, i) => directory.some((other, j) => j > i && other.name === entry.name));
  let duplicateLookup = null;
  if (duplicate) {
    const selected = lastNamed(directory, duplicate.name);
    duplicateLookup = { name: duplicate.name, occurrenceIndex: selected.occurrenceIndex, bytes: Array.from(selected.data) };
  }

  return {
    schema: 1,
    wad: { kind, directoryCount: directory.length, duplicateLookup, mapBoundary: { marker, nextMarker: map.nextMarker, thingsCount: things.length } },
    directory: directory.map(({ data: ignored, ...entry }) => entry),
    things,
    counts: { linedefs: linedefs.length, sidedefs: sidedefs.length, vertexes: vertexes.length, segs: segs.length, ssectors: ssectors.length, nodes: nodes.length, sectors: sectors.length },
    spotChecks: {
      linedef0: linedefs[0] ? (({ id, ...v }) => v)(linedefs[0]) : null,
      sidedef0: sidedefs[0] ? (({ id, ...v }) => v)(sidedefs[0]) : null,
      vertex0: vertexes[0] ? (({ id, ...v }) => v)(vertexes[0]) : null,
      seg1: segs[1] ? (({ id, ...v }) => v)(segs[1]) : null,
      ssector1: ssectors[1] ? (({ id, ...v }) => v)(ssectors[1]) : null,
      node0: nodes[0] ? { x: nodes[0].x, y: nodes[0].y, dx: nodes[0].dx, dy: nodes[0].dy, children: nodes[0].children } : null,
      sector0: sectors[0] ? (({ id, ...v }) => v)(sectors[0]) : null,
    },
    reject, blockmap,
    playpal: { paletteCount: playpalFull.paletteCount, palette0: playpalFull.palette0 },
    colormap: { mapCount: colormapFull.mapCount, map0: colormapFull.map0, map31: colormapFull.map31 },
    pnames, textures, patches,
    flat: (({ texels, ...v }) => v)(flatFull),
    sound: soundFull, music,
    mapData: { things, linedefs, sidedefs, vertexes, segs, ssectors, nodes, sectors },
    palettes: playpalFull.palettes, colormaps: colormapFull.maps, flats, sounds,
  };
}
