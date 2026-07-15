import fs from 'node:fs';

const te = new TextEncoder();

export const u8 = (...values) => Uint8Array.from(values.map((v) => v & 0xff));
export const le16 = (value) => u8(value, value >> 8);
export const le32 = (value) => u8(value, value >> 8, value >> 16, value >> 24);
export const i16 = le16;
export const i32 = le32;
export const bytes = (...parts) => {
  const flat = parts.flatMap((part) => [...part]);
  return Uint8Array.from(flat);
};
export const name8 = (name) => {
  if (!/^[\x20-\x7e]{0,8}$/.test(name)) throw new Error(`invalid WAD name: ${name}`);
  return bytes(te.encode(name), new Uint8Array(8 - name.length));
};

export function wad(lumps, kind = 'PWAD') {
  const payloadStart = 12;
  let offset = payloadStart;
  const payload = [];
  const directory = [];
  for (const lump of lumps) {
    payload.push(lump.data);
    directory.push(bytes(le32(offset), le32(lump.data.length), name8(lump.name)));
    offset += lump.data.length;
  }
  return bytes(te.encode(kind), le32(lumps.length), le32(offset), ...payload, ...directory);
}

export function writeWad(file, lumps, kind = 'PWAD') {
  fs.writeFileSync(file, wad(lumps, kind));
}

export function patch(width, height, columns, left = 0, top = 0) {
  const headerSize = 8 + 4 * width;
  let cursor = headerSize;
  const offsets = [];
  for (const column of columns) {
    offsets.push(cursor);
    cursor += column.length;
  }
  return bytes(i16(width), i16(height), i16(left), i16(top), ...offsets.map(le32), ...columns);
}

export const postColumn = (...posts) => bytes(
  ...posts.map(({ top, pixels }) => bytes(u8(top, pixels.length, 0), u8(...pixels), u8(0))),
  u8(255),
);

export function textureDirectory(textures) {
  let cursor = 4 + textures.length * 4;
  const offsets = [];
  const records = [];
  for (const t of textures) {
    const record = bytes(
      name8(t.name), le32(0), i16(t.width), i16(t.height), le32(0), le16(t.patches.length),
      ...t.patches.map((p) => bytes(i16(p.x), i16(p.y), le16(p.patch), le16(0), le16(0))),
    );
    offsets.push(cursor);
    records.push(record);
    cursor += record.length;
  }
  return bytes(le32(textures.length), ...offsets.map(le32), ...records);
}

