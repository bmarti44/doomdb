import crypto from 'node:crypto';
import fs from 'node:fs';

export const WAD_SHA256 = '7323bcc168c5a45ff10749b339960e98314740a734c30d4b9f3337001f9e703d';

export function pointSide(px, py, node) {
  if (node.dx === 0) return px <= node.x ? (node.dy > 0 ? 1 : 0) : (node.dy < 0 ? 1 : 0);
  if (node.dy === 0) return py <= node.y ? (node.dx < 0 ? 1 : 0) : (node.dx > 0 ? 1 : 0);
  const cross = (px - node.x) * node.dy - (py - node.y) * node.dx;
  return cross > 0 ? 0 : 1;
}

function mapLumps(wad) {
  if (crypto.createHash('sha256').update(wad).digest('hex') !== WAD_SHA256) throw new Error('wrong pinned WAD');
  const count = wad.readInt32LE(4), directoryAt = wad.readInt32LE(8), directory = [];
  for (let id = 0; id < count; id++) {
    const at = directoryAt + id * 16;
    directory.push({
      name: wad.subarray(at + 8, at + 16).toString('ascii').replace(/\0.*$/, ''),
      offset: wad.readInt32LE(at), size: wad.readInt32LE(at + 4)
    });
  }
  const marker = directory.findIndex((row) => row.name === 'E1M1');
  if (marker < 0) throw new Error('E1M1 absent');
  return new Map(directory.slice(marker + 1, marker + 11).map((row) => [row.name, row]));
}

export function decodeE1M1(wad) {
  const lumps = mapLumps(wad), get = (name) => {
    const row = lumps.get(name); if (!row) throw new Error(`missing ${name}`); return row;
  };
  const things = [], thing = get('THINGS');
  for (let id = 0; id < thing.size / 10; id++) {
    const at = thing.offset + id * 10;
    things.push({id, x: wad.readInt16LE(at), y: wad.readInt16LE(at + 2), angle: wad.readUInt16LE(at + 4), type: wad.readUInt16LE(at + 6), flags: wad.readUInt16LE(at + 8)});
  }
  const lines = [], line = get('LINEDEFS');
  for (let id = 0; id < line.size / 14; id++) {
    const at = line.offset + id * 14;
    lines.push({right: wad.readUInt16LE(at + 10), left: wad.readUInt16LE(at + 12)});
  }
  const sides = [], sidedef = get('SIDEDEFS');
  for (let id = 0; id < sidedef.size / 30; id++) sides.push({sector: wad.readUInt16LE(sidedef.offset + id * 30 + 28)});
  const segs = [], seg = get('SEGS');
  for (let id = 0; id < seg.size / 12; id++) {
    const at = seg.offset + id * 12;
    segs.push({line: wad.readUInt16LE(at + 6), direction: wad.readUInt16LE(at + 8)});
  }
  const ssectors = [], ss = get('SSECTORS');
  for (let id = 0; id < ss.size / 4; id++) ssectors.push({count: wad.readUInt16LE(ss.offset + id * 4), firstSeg: wad.readUInt16LE(ss.offset + id * 4 + 2)});
  const nodes = [], node = get('NODES');
  for (let id = 0; id < node.size / 28; id++) {
    const at = node.offset + id * 28, child0 = wad.readUInt16LE(at + 24), child1 = wad.readUInt16LE(at + 26);
    nodes.push({id, x: wad.readInt16LE(at), y: wad.readInt16LE(at + 2), dx: wad.readInt16LE(at + 4), dy: wad.readInt16LE(at + 6), children:[child0,child1]});
  }
  const sectorForSubsector = (ssector) => {
    const sg = segs[ssectors[ssector].firstSeg], ln = lines[sg.line];
    const sideId = sg.direction === 0 ? ln.right : ln.left;
    if (sideId === 0xffff || !sides[sideId]) throw new Error(`invalid facing side for subsector ${ssector}`);
    return sides[sideId].sector;
  };
  return {things, nodes, ssectors, locate(px, py) {
    let child = nodes.length - 1, depth = 0; const path = [];
    while ((child & 0x8000) === 0) {
      const n = nodes[child]; if (!n) throw new Error(`invalid node ${child}`);
      const side = pointSide(px, py, n); path.push(`${n.id}:${side}`);
      child = n.children[side]; depth++;
      if (depth > nodes.length) throw new Error('BSP cycle');
    }
    const ssector = child & 0x7fff;
    return {ssector, sector: sectorForSubsector(ssector), depth, pathSignature:path.join('/')};
  }};
}

export function canonicalSha(value) {
  return crypto.createHash('sha256').update(JSON.stringify(value)).digest('hex');
}
