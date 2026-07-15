import { bytes, i16, le16, le32, name8, patch, postColumn, textureDirectory, u8 } from './fixture-kit.mjs';

const repeat = (length, fn) => Uint8Array.from({ length }, (_, i) => fn(i) & 0xff);
const thing = (x, y, angle, type, flags) => bytes(i16(x), i16(y), le16(angle), le16(type), le16(flags));
const vertex = (x, y) => bytes(i16(x), i16(y));
const linedef = (v1, v2, flags, special, tag, right, left) => bytes(le16(v1), le16(v2), le16(flags), le16(special), le16(tag), le16(right), le16(left));
const sidedef = (x, y, upper, lower, middle, sector) => bytes(i16(x), i16(y), name8(upper), name8(lower), name8(middle), le16(sector));
const sector = (floor, ceiling, floorFlat, ceilingFlat, light, special, tag) => bytes(i16(floor), i16(ceiling), name8(floorFlat), name8(ceilingFlat), le16(light), le16(special), le16(tag));
const seg = (start, end, angle, linedefId, direction, offset) => bytes(le16(start), le16(end), le16(angle), le16(linedefId), le16(direction), le16(offset));
const bbox = (top, bottom, left, right) => bytes(i16(top), i16(bottom), i16(left), i16(right));

const tallPatch = patch(2, 300, [
  postColumn({ top: 250, pixels: [10, 11] }, { top: 5, pixels: [12, 13, 14] }),
  postColumn({ top: 0, pixels: [0] }, { top: 20, pixels: [255] }),
], -2, 7);

const spritePatch = patch(2, 3, [
  postColumn({ top: 0, pixels: [21, 22, 23] }),
  postColumn({ top: 1, pixels: [24] }),
], 1, 2);

const pnames = bytes(le32(2), name8('PCHTALL'), name8('SPRTA0'));
const texture1 = textureDirectory([{ name: 'ODDWALL', width: 3, height: 300, patches: [
  { x: -1, y: -2, patch: 0 }, { x: 2, y: 1, patch: 1 },
]}]);
const texture2 = textureDirectory([{ name: 'SECOND', width: 5, height: 3, patches: [{ x: 0, y: 0, patch: 1 }] }]);

export const completeLumps = [
  { name: 'DUPLUMP', data: u8(1) },
  { name: 'DUPLUMP', data: u8(2, 3) },
  { name: 'E1M1', data: u8() },
  { name: 'THINGS', data: bytes(
    thing(-16, 32, 90, 1, 0x0007),
    thing(64, -32, 270, 3004, 0x0018),
  ) },
  { name: 'LINEDEFS', data: bytes(
    linedef(0, 1, 0x0005, 11, 7, 0, 0xffff),
    linedef(1, 2, 0x0200, 0, 0, 1, 2),
  ) },
  { name: 'SIDEDEFS', data: bytes(
    sidedef(-8, 12, 'UPPER', '-', 'ODDWALL', 0),
    sidedef(3, -4, '-', 'LOWER', '-', 0),
    sidedef(0, 0, '-', '-', 'SECOND', 1),
  ) },
  { name: 'VERTEXES', data: bytes(vertex(-128, 64), vertex(256, -64), vertex(0, 128)) },
  { name: 'SEGS', data: bytes(seg(0, 1, 0x4000, 0, 0, 12), seg(2, 1, 0xc000, 1, 1, 20)) },
  { name: 'SSECTORS', data: bytes(le16(1), le16(0), le16(1), le16(1)) },
  { name: 'NODES', data: bytes(
    i16(0), i16(0), i16(128), i16(-64),
    bbox(128, -64, -128, 256), bbox(64, -64, 0, 256),
    le16(0x8000), le16(0x8001),
  ) },
  { name: 'SECTORS', data: bytes(
    sector(-16, 128, 'FLAT1', 'CEIL1', 160, 9, 2),
    sector(0, 192, 'FLAT2', 'F_SKY1', 255, 0, 0),
  ) },
  { name: 'REJECT', data: u8(0x06) },
  { name: 'BLOCKMAP', data: bytes(
    i16(-128), i16(-64), le16(2), le16(1),
    le16(6), le16(10),
    le16(0), le16(0), le16(1), le16(0xffff),
    le16(0), le16(1), le16(0xffff),
  ) },
  { name: 'PLAYPAL', data: repeat(14 * 256 * 3, (i) => i) },
  { name: 'COLORMAP', data: repeat(34 * 256, (i) => 255 - i) },
  { name: 'PNAMES', data: pnames },
  { name: 'TEXTURE1', data: texture1 },
  { name: 'TEXTURE2', data: texture2 },
  { name: 'PCHTALL', data: tallPatch },
  { name: 'F_START', data: u8() },
  { name: 'FLAT1', data: repeat(4096, (i) => i * 3) },
  { name: 'F_END', data: u8() },
  { name: 'S_START', data: u8() },
  { name: 'SPRTA0', data: spritePatch },
  { name: 'S_END', data: u8() },
  { name: 'DSPISTOL', data: bytes(le16(3), le16(11025), le32(4), u8(128, 129, 127, 0)) },
  { name: 'D_E1M1', data: bytes(new TextEncoder().encode('MUS\x1a'), le16(2), le16(16), le16(1), le16(0), le16(0), le16(0), u8(0x60, 0)) },
  { name: 'E1M2', data: u8() },
  { name: 'THINGS', data: thing(999, 999, 0, 1, 7) },
];

export const malformedCases = [
  { id: 'bad-header', bytes: bytes(new TextEncoder().encode('XXXX'), le32(0), le32(12)), error: 'WAD_BAD_MAGIC' },
  { id: 'directory-oob', bytes: bytes(new TextEncoder().encode('PWAD'), le32(1), le32(0x7fffffff)), error: 'WAD_DIRECTORY_BOUNDS' },
  { id: 'lump-oob', rawDirectory: { offset: 1000, size: 3, name: 'BROKEN' }, error: 'WAD_LUMP_BOUNDS' },
  { id: 'things-size', replace: { lump: 'THINGS', data: u8(1) }, error: 'WAD_THINGS_SIZE' },
  { id: 'linedefs-ref', mutate: { lump: 'LINEDEFS', byte: 0, value: 99 }, error: 'WAD_LINEDEF_VERTEX_REF' },
  { id: 'sidedefs-ref', mutate: { lump: 'SIDEDEFS', byte: 28, value: 99 }, error: 'WAD_SIDEDEF_SECTOR_REF' },
  { id: 'segs-ref', mutate: { lump: 'SEGS', byte: 6, value: 99 }, error: 'WAD_SEG_LINEDEF_REF' },
  { id: 'ssectors-ref', mutate: { lump: 'SSECTORS', byte: 2, value: 99 }, error: 'WAD_SSECTOR_SEG_RANGE' },
  { id: 'nodes-ref', mutate: { lump: 'NODES', byte: 24, value: 2 }, error: 'WAD_NODE_CHILD_REF' },
  { id: 'blockmap-offset', mutate: { lump: 'BLOCKMAP', byte: 8, value: 250 }, error: 'WAD_BLOCKMAP_OFFSET' },
  { id: 'reject-short', replace: { lump: 'REJECT', data: u8() }, error: 'WAD_REJECT_SIZE' },
  { id: 'pnames-ref', mutate: { lump: 'TEXTURE1', byte: 34, value: 9 }, error: 'WAD_TEXTURE_PATCH_REF' },
  { id: 'patch-column-oob', mutate: { lump: 'PCHTALL', byte: 8, value: 250 }, error: 'WAD_PATCH_COLUMN_BOUNDS' },
  { id: 'patch-post-truncated', replace: { lump: 'SPRTA0', data: spritePatch.slice(0, -1) }, error: 'WAD_PATCH_POST_STREAM' },
  { id: 'sound-size', replace: { lump: 'DSPISTOL', data: bytes(le16(3), le16(11025), le32(99), u8(1)) }, error: 'WAD_SOUND_SIZE' },
];
