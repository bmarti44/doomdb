import crypto from 'node:crypto';

export const WAD_SHA256 = '7323bcc168c5a45ff10749b339960e98314740a734c30d4b9f3337001f9e703d';

function wadMap(wad) {
  if (crypto.createHash('sha256').update(wad).digest('hex') !== WAD_SHA256) throw new Error('wrong pinned WAD');
  const count = wad.readInt32LE(4), directoryAt = wad.readInt32LE(8), rows = [];
  for (let id = 0; id < count; id++) {
    const at = directoryAt + id * 16;
    rows.push({name:wad.subarray(at + 8, at + 16).toString('ascii').replace(/\0.*$/, ''), offset:wad.readInt32LE(at), size:wad.readInt32LE(at + 4)});
  }
  const marker = rows.findIndex((row) => row.name === 'E1M1');
  if (marker < 0) throw new Error('E1M1 absent');
  return new Map(rows.slice(marker + 1, marker + 11).map((row) => [row.name, row]));
}

export function decodeBlockmapBytes(bytes) {
  if (bytes.length < 8) throw new Error('short BLOCKMAP');
  const originX = bytes.readInt16LE(0), originY = bytes.readInt16LE(2);
  const columns = bytes.readUInt16LE(4), rows = bytes.readUInt16LE(6);
  if (bytes.length < 8 + columns * rows * 2) throw new Error('short BLOCKMAP offsets');
  const cells = [], memberships = [];
  for (let cellId = 0; cellId < columns * rows; cellId++) {
    const blockX = cellId % columns, blockY = Math.floor(cellId / columns);
    const listWordOffset = bytes.readUInt16LE(8 + cellId * 2);
    let at = listWordOffset * 2;
    if (at + 2 > bytes.length || bytes.readUInt16LE(at) !== 0) throw new Error('BLOCKMAP list header');
    at += 2;
    const lines = [];
    while (true) {
      if (at + 2 > bytes.length) throw new Error('BLOCKMAP unterminated list');
      const line = bytes.readUInt16LE(at); at += 2;
      if (line === 0xffff) break;
      const lineOrdinal = lines.length;
      lines.push(line);
      memberships.push({cellId, blockX, blockY, lineOrdinal, linedefId:line});
    }
    cells.push({cellId, blockX, blockY, worldMinX:originX + blockX * 128, worldMinY:originY + blockY * 128, listWordOffset, lines});
  }
  return {originX, originY, columns, rows, cells, memberships};
}

export function encodeBlockmap(decoded) {
  const listByOffset = new Map();
  for (const cell of decoded.cells) {
    const previous = listByOffset.get(cell.listWordOffset);
    if (previous && previous.join(',') !== cell.lines.join(',')) throw new Error('shared BLOCKMAP offset disagrees');
    listByOffset.set(cell.listWordOffset, cell.lines);
  }
  const endWord = Math.max(4 + decoded.cells.length, ...[...listByOffset].map(([offset, lines]) => offset + lines.length + 2));
  const out = Buffer.alloc(endWord * 2, 0);
  out.writeInt16LE(decoded.originX, 0); out.writeInt16LE(decoded.originY, 2);
  out.writeUInt16LE(decoded.columns, 4); out.writeUInt16LE(decoded.rows, 6);
  for (const cell of decoded.cells) out.writeUInt16LE(cell.listWordOffset, 8 + cell.cellId * 2);
  for (const [offset, lines] of listByOffset) {
    let at = offset * 2; out.writeUInt16LE(0, at); at += 2;
    for (const line of lines) { out.writeUInt16LE(line, at); at += 2; }
    out.writeUInt16LE(0xffff, at);
  }
  return out;
}

export function cellForPoint(x, y, decoded) {
  return {blockX:Math.floor((x - decoded.originX) / 128), blockY:Math.floor((y - decoded.originY) / 128)};
}

export function decodeRejectBytes(bytes, sectorCount) {
  const required = Math.ceil(sectorCount * sectorCount / 8);
  if (bytes.length !== required) throw new Error('wrong REJECT length');
  const bits = [];
  for (let sourceSectorId = 0; sourceSectorId < sectorCount; sourceSectorId++) {
    for (let targetSectorId = 0; targetSectorId < sectorCount; targetSectorId++) {
      const bit = sourceSectorId * sectorCount + targetSectorId;
      bits.push({sourceSectorId,targetSectorId,rejected:(bytes[bit >> 3] >> (bit & 7)) & 1,byteOffset:bit >> 3,bitOffset:bit & 7});
    }
  }
  return bits;
}

export function graphEdges(lines, sides, sectors) {
  const edges = [];
  for (const line of lines) {
    if (line.left === 0xffff) continue;
    const source = sides[line.right].sector, target = sides[line.left].sector;
    if (source === target) continue;
    const opening = Math.min(sectors[source].ceiling, sectors[target].ceiling) - Math.max(sectors[source].floor, sectors[target].floor);
    if (opening <= 0) continue;
    const soundBlock = (line.flags & 0x40) === 0x40 ? 1 : 0;
    edges.push({edgeId:line.id * 2,sourceSectorId:source,targetSectorId:target,linedefId:line.id,soundBlock,opening});
    edges.push({edgeId:line.id * 2 + 1,sourceSectorId:target,targetSectorId:source,linedefId:line.id,soundBlock,opening});
  }
  return edges;
}

export function decodeE1M1(wad) {
  const lumps = wadMap(wad), lump = (name) => { const row=lumps.get(name); if (!row) throw new Error(`missing ${name}`); return row; };
  const getBytes = (name) => { const row=lump(name); return wad.subarray(row.offset,row.offset+row.size); };
  const sectors = [], sector=lump('SECTORS');
  for (let id=0; id<sector.size/26; id++) { const at=sector.offset+id*26; sectors.push({id,floor:wad.readInt16LE(at),ceiling:wad.readInt16LE(at+2)}); }
  const sides=[], side=lump('SIDEDEFS');
  for (let id=0; id<side.size/30; id++) sides.push({id,sector:wad.readUInt16LE(side.offset+id*30+28)});
  const lines=[], line=lump('LINEDEFS');
  for (let id=0; id<line.size/14; id++) { const at=line.offset+id*14; lines.push({id,flags:wad.readUInt16LE(at+4),right:wad.readUInt16LE(at+10),left:wad.readUInt16LE(at+12)}); }
  const blockBytes=getBytes('BLOCKMAP'), rejectBytes=getBytes('REJECT');
  return {blockBytes,rejectBytes,sectors,sides,lines,blockmap:decodeBlockmapBytes(blockBytes),reject:decodeRejectBytes(rejectBytes,sectors.length),edges:graphEdges(lines,sides,sectors)};
}

export const sha = (text) => crypto.createHash('sha256').update(text).digest('hex');
export const blockDocument = (memberships) => memberships.map((m) => `${m.blockX}:${m.blockY}:${m.lineOrdinal}:${m.linedefId}\n`).join('');
export const rejectDocument = (bits) => bits.map((b) => `${b.sourceSectorId}:${b.targetSectorId}:${b.rejected}\n`).join('');
export const graphDocument = (edges) => edges.map((e) => `${e.edgeId}:${e.sourceSectorId}:${e.targetSectorId}:${e.linedefId}:${e.soundBlock}\n`).join('');
