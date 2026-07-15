#!/usr/bin/env node
import crypto from 'node:crypto';
import fs from 'node:fs';
import path from 'node:path';

const PINNED_WAD_SHA256 = '7323bcc168c5a45ff10749b339960e98314740a734c30d4b9f3337001f9e703d';
const MAP = 'E1M1';
const MAX_ROWS = 500;
const MAP_LUMPS = ['E1M1','THINGS','LINEDEFS','SIDEDEFS','VERTEXES','SEGS','SSECTORS','NODES','SECTORS','REJECT','BLOCKMAP'];
const CORE_LUMPS = ['PLAYPAL','COLORMAP','PNAMES','TEXTURE1','TEXTURE2'];
const sha256 = (bytes) => crypto.createHash('sha256').update(bytes).digest('hex');

function die(message) { process.stderr.write(`generate-seed: ${message}\n`); process.exit(1); }
function readJson(file, label) {
  try { return JSON.parse(fs.readFileSync(file, 'utf8')); }
  catch (error) { die(`cannot read ${label}: ${error.message}`); }
}
function argumentsFrom(argv) {
  const allowed = new Set(['--wad','--engine-defs','--asset-closure','--animations','--rng','--out']);
  const values = {};
  for (let i = 0; i < argv.length; i += 2) {
    const flag = argv[i];
    if (!allowed.has(flag) || i + 1 >= argv.length || argv[i + 1].startsWith('--') || values[flag]) die('expected each required option exactly once');
    values[flag] = argv[i + 1];
  }
  if (argv.length !== allowed.size * 2 || [...allowed].some((flag) => !values[flag])) die('required options: --wad --engine-defs --asset-closure --animations --rng --out');
  return values;
}
function directory(wad) {
  if (wad.length < 12 || wad.toString('ascii', 0, 4) !== 'IWAD') die('input is not an IWAD');
  const count = wad.readUInt32LE(4), at = wad.readUInt32LE(8);
  if (at > wad.length || count * 16 > wad.length - at) die('invalid WAD directory');
  const occurrences = new Map();
  return Array.from({ length: count }, (_, index) => {
    const pos = at + index * 16, offset = wad.readUInt32LE(pos), size = wad.readUInt32LE(pos + 4);
    if (offset > wad.length || size > wad.length - offset) die('invalid WAD lump bounds');
    const name = wad.toString('ascii', pos + 8, pos + 16).replace(/\0.*$/s, '');
    const occurrence = occurrences.get(name) ?? 0;
    occurrences.set(name, occurrence + 1);
    const bytes = wad.subarray(offset, offset + size);
    return { index, name, occurrence, offset, size, sha256:sha256(bytes), bytes };
  });
}
function last(rows, name) {
  for (let i = rows.length - 1; i >= 0; i -= 1) if (rows[i].name === name) return rows[i];
  die(`required lump ${name} is absent`);
}
function confinedMap(rows) {
  const start = rows.findIndex((row) => row.name === MAP);
  if (start < 0) die(`${MAP} marker is absent`);
  let end = rows.length;
  for (let i = start + 1; i < rows.length; i += 1) if (/^(?:E\dM\d|MAP\d\d)$/.test(rows[i].name)) { end = i; break; }
  const selected = [rows[start]];
  for (const name of MAP_LUMPS.slice(1)) {
    const found = rows.slice(start + 1, end).filter((row) => row.name === name).at(-1);
    if (!found) die(`${MAP} confined lump ${name} is absent`);
    selected.push(found);
  }
  return selected;
}
const lumpName = (bytes, at) => bytes.toString('ascii', at, at + 8).replace(/\0.*$/s, '');
function records(bytes, size, label, decode) {
  if (bytes.length % size !== 0) die(`malformed ${label}`);
  return Array.from({length:bytes.length / size}, (_, id) => decode(bytes, id * size, id));
}
function decodeMap(byName) {
  const bytes = (name) => byName.get(name).bytes;
  const things = records(bytes('THINGS'),10,'THINGS',(b,a,id)=>({id,x:b.readInt16LE(a),y:b.readInt16LE(a+2),angle:b.readUInt16LE(a+4),type:b.readUInt16LE(a+6),flags:b.readUInt16LE(a+8)}));
  const vertexes = records(bytes('VERTEXES'),4,'VERTEXES',(b,a,id)=>({id,x:b.readInt16LE(a),y:b.readInt16LE(a+2)}));
  const linedefs = records(bytes('LINEDEFS'),14,'LINEDEFS',(b,a,id)=>{ const left=b.readUInt16LE(a+12); return {id,v1:b.readUInt16LE(a),v2:b.readUInt16LE(a+2),flags:b.readUInt16LE(a+4),special:b.readUInt16LE(a+6),tag:b.readUInt16LE(a+8),right:b.readUInt16LE(a+10),left:left===0xffff?null:left}; });
  const sidedefs = records(bytes('SIDEDEFS'),30,'SIDEDEFS',(b,a,id)=>({id,xOffset:b.readInt16LE(a),yOffset:b.readInt16LE(a+2),upper:lumpName(b,a+4),lower:lumpName(b,a+12),middle:lumpName(b,a+20),sector:b.readUInt16LE(a+28)}));
  const sectors = records(bytes('SECTORS'),26,'SECTORS',(b,a,id)=>({id,floor:b.readInt16LE(a),ceiling:b.readInt16LE(a+2),floorFlat:lumpName(b,a+4),ceilingFlat:lumpName(b,a+12),light:b.readUInt16LE(a+20),special:b.readUInt16LE(a+22),tag:b.readUInt16LE(a+24)}));
  const segs = records(bytes('SEGS'),12,'SEGS',(b,a,id)=>({id,start:b.readUInt16LE(a),end:b.readUInt16LE(a+2),angle:b.readUInt16LE(a+4),linedef:b.readUInt16LE(a+6),direction:b.readUInt16LE(a+8),offset:b.readUInt16LE(a+10)}));
  const ssectors = records(bytes('SSECTORS'),4,'SSECTORS',(b,a,id)=>({id,segCount:b.readUInt16LE(a),firstSeg:b.readUInt16LE(a+2)}));
  const nodes = records(bytes('NODES'),28,'NODES',(b,a,id)=>{ const bbox=(p)=>({top:b.readInt16LE(p),bottom:b.readInt16LE(p+2),left:b.readInt16LE(p+4),right:b.readInt16LE(p+6)}); const child=(p)=>{const raw=b.readUInt16LE(p);return{subsector:(raw&0x8000)!==0,id:raw&0x7fff};}; return {id,x:b.readInt16LE(a),y:b.readInt16LE(a+2),dx:b.readInt16LE(a+4),dy:b.readInt16LE(a+6),bboxes:[bbox(a+8),bbox(a+16)],children:[child(a+24),child(a+26)]}; });
  return { things,vertexes,linedefs,sidedefs,sectors,segs,ssectors,nodes };
}
function patchImage(bytes) {
  if (bytes.length < 8) die('malformed patch');
  const width = bytes.readInt16LE(0), height = bytes.readInt16LE(2);
  if (width <= 0 || height <= 0 || 8 + width * 4 > bytes.length) die('malformed patch dimensions');
  const pixels = new Int16Array(width * height).fill(-1);
  for (let x = 0; x < width; x += 1) {
    let at = bytes.readUInt32LE(8 + x * 4), previousTop = -1;
    while (true) {
      if (at >= bytes.length) die('malformed patch post stream');
      const rawTop = bytes[at];
      if (rawTop === 255) break;
      if (at + 3 > bytes.length) die('malformed patch post header');
      const length = bytes[at + 1];
      let top = rawTop;
      if (previousTop >= 0 && rawTop <= previousTop) top += previousTop;
      previousTop = top;
      at += 3;
      if (at + length + 1 > bytes.length) die('malformed patch post pixels');
      for (let y = 0; y < length; y += 1) if (top + y >= 0 && top + y < height) pixels[(top + y) * width + x] = bytes[at + y];
      at += length + 1;
    }
  }
  return { width, height, pixels };
}
function textureDefinitions(rows) {
  const pnamesBytes = last(rows, 'PNAMES').bytes;
  const count = pnamesBytes.readUInt32LE(0);
  if (4 + count * 8 !== pnamesBytes.length) die('malformed PNAMES');
  const pnames = Array.from({length:count}, (_, i) => pnamesBytes.toString('ascii', 4 + i * 8, 12 + i * 8).replace(/\0.*$/s, ''));
  const definitions = new Map();
  for (const source of ['TEXTURE1','TEXTURE2']) {
    const bytes = last(rows, source).bytes, textureCount = bytes.readUInt32LE(0);
    for (let i = 0; i < textureCount; i += 1) {
      let at = bytes.readUInt32LE(4 + i * 4);
      const name = bytes.toString('ascii', at, at + 8).replace(/\0.*$/s, '');
      const width = bytes.readUInt16LE(at + 12), height = bytes.readUInt16LE(at + 14), patchCount = bytes.readUInt16LE(at + 20);
      at += 22;
      const patches = [];
      for (let p = 0; p < patchCount; p += 1, at += 10) {
        const patchIndex = bytes.readUInt16LE(at + 4);
        if (patchIndex >= pnames.length) die(`texture ${name} has invalid patch index`);
        patches.push({ x:bytes.readInt16LE(at), y:bytes.readInt16LE(at + 2), name:pnames[patchIndex] });
      }
      definitions.set(name, { width, height, patches });
    }
  }
  return definitions;
}
function composeTexture(rows, definition, name) {
  if (!definition) die(`wall texture ${name} is undefined`);
  const pixels = new Int16Array(definition.width * definition.height).fill(-1);
  for (const placement of definition.patches) {
    const patch = patchImage(last(rows, placement.name).bytes);
    for (let y = 0; y < patch.height; y += 1) for (let x = 0; x < patch.width; x += 1) {
      const targetX = x + placement.x, targetY = y + placement.y, value = patch.pixels[y * patch.width + x];
      if (value >= 0 && targetX >= 0 && targetX < definition.width && targetY >= 0 && targetY < definition.height) pixels[targetY * definition.width + targetX] = value;
    }
  }
  return { width:definition.width, height:definition.height, pixels };
}
function texelSha(image) {
  const bytes = Buffer.allocUnsafe(image.pixels.length * 2);
  for (let i = 0; i < image.pixels.length; i += 1) bytes.writeInt16LE(image.pixels[i], i * 2);
  return sha256(bytes);
}
const sqlString = (value) => value === null ? 'NULL' : `'${String(value).replaceAll("'", "''")}'`;
const sqlNumber = (value) => value === null ? 'NULL' : String(Number(value));
function insertSql(table, columns, rows) {
  let output = '';
  for (let start = 0; start < rows.length; start += MAX_ROWS) {
    const batch = rows.slice(start, start + MAX_ROWS);
    output += 'INSERT ALL\n';
    for (const row of batch) output += `  INTO ${table} (${columns.join(', ')}) VALUES (${row.join(', ')})\n`;
    output += 'SELECT 1 FROM DUAL;\n';
  }
  return output;
}
function sqlFile(dataset, table, columns, rows) {
  return { dataset, rowCount:rows.length, text:insertSql(table, columns, rows) };
}
function writeOutput(out, generated) {
  if (fs.existsSync(out) && (!fs.statSync(out).isDirectory() || fs.readdirSync(out).length !== 0)) die('--out must name a new or empty directory');
  fs.mkdirSync(out, { recursive:true });
  const records = [];
  for (const [relative, file] of [...generated.entries()].sort(([a],[b]) => a < b ? -1 : a > b ? 1 : 0)) {
    let fileHash;
    if (file.rows) {
      const hash = crypto.createHash('sha256'), fd = fs.openSync(path.join(out, relative), 'w');
      let batch = [], writtenRows = 0;
      const flush = () => {
        if (batch.length === 0) return;
        const text = insertSql(file.table, file.columns, batch);
        fs.writeSync(fd, text, null, 'ascii'); hash.update(text, 'ascii');
        writtenRows += batch.length; batch = [];
      };
      try { for (const row of file.rows()) { batch.push(row); if (batch.length === MAX_ROWS) flush(); } flush(); }
      finally { fs.closeSync(fd); }
      if (writtenRows !== file.rowCount) die(`internal row-count error for ${relative}`);
      fileHash = hash.digest('hex');
    } else {
      if (!/^[\x00-\x7f]*$/.test(file.text) || file.text.includes('\r') || !file.text.endsWith('\n')) die(`internal output-format error for ${relative}`);
      fs.writeFileSync(path.join(out, relative), file.text, 'ascii');
      fileHash = sha256(Buffer.from(file.text, 'ascii'));
    }
    records.push({ path:relative, dataset:file.dataset, rowCount:file.rowCount, batchCount:file.batchCount ?? Math.ceil(file.rowCount / MAX_ROWS), maxRowsInBatch:file.maxRowsInBatch ?? Math.min(MAX_ROWS, file.rowCount), sha256:fileHash });
  }
  return records;
}

const args = argumentsFrom(process.argv.slice(2));
let wad;
try { wad = fs.readFileSync(args['--wad']); } catch (error) { die(`cannot read WAD: ${error.message}`); }
if (sha256(wad) !== PINNED_WAD_SHA256) die('WAD SHA-256 is not the pinned Freedoom 0.13.0 Phase 1 IWAD');
const engineDefs = readJson(args['--engine-defs'], 'engine definitions');
const closure = readJson(args['--asset-closure'], 'asset closure');
const animations = readJson(args['--animations'], 'animation groups');
const rng = readJson(args['--rng'], 'RNG table');
if (engineDefs.schema !== 1 || closure.schema !== 1 || animations.schema !== 1 || rng.schema !== 1 || !Array.isArray(closure.assets)) die('approved input document schema mismatch');
const rows = directory(wad), mapSources = confinedMap(rows), textures = textureDefinitions(rows);
const mapLump = new Map(mapSources.map((source) => [source.name, source])), map = decodeMap(mapLump);

const assets = [];
const decodedImages = new Map();
let assetTexelCount = 0;
for (const approved of [...closure.assets].sort((a,b) => { const ak=`${a.kind}:${a.name}`, bk=`${b.kind}:${b.name}`; return ak < bk ? -1 : ak > bk ? 1 : 0; })) {
  if (!approved.kind || !approved.name || !Array.isArray(approved.sourceLumps) || approved.sourceLumps.length === 0) die('invalid asset closure row');
  const sourceRows = approved.sourceLumps.map((name) => last(rows, name));
  let image;
  if (approved.kind === 'wall_texture') image = composeTexture(rows, textures.get(approved.name), approved.name);
  else if (['patch','sprite_patch','ui_patch'].includes(approved.kind)) image = patchImage(last(rows, approved.name).bytes);
  else if (approved.kind === 'flat') {
    const bytes = last(rows, approved.name).bytes;
    if (bytes.length !== 4096) die(`flat ${approved.name} is not 64x64`);
    image = { width:64, height:64, pixels:Int16Array.from(bytes) };
  }
  const asset = { assetId:assets.length, kind:approved.kind, name:approved.name, sourceLumps:[...approved.sourceLumps], sourceSha256:sourceRows.map((source) => source.sha256) };
  if (sourceRows.length === 1) asset.rawSha256 = sourceRows[0].sha256;
  if (image) {
    asset.width = image.width; asset.height = image.height; asset.texelSha256 = texelSha(image);
    decodedImages.set(`${asset.kind}:${asset.name}`, image);
    assetTexelCount += image.width * image.height;
  }
  assets.push(asset);
}
const assetKeys = new Set(assets.map((asset) => `${asset.kind}:${asset.name}`));
if (assetKeys.size !== assets.length) die('duplicate asset closure key');

const selectedSources = new Map(mapSources.map((source) => [source.index, { source, selection:'map-confined' }]));
for (const name of CORE_LUMPS) { const source = last(rows, name); selectedSources.set(source.index, { source, selection:'last-occurrence' }); }
for (const asset of assets) for (const name of asset.sourceLumps) { const source = last(rows, name); selectedSources.set(source.index, { source, selection:'last-occurrence' }); }
const sources = [...selectedSources.values()].sort((a,b) => a.source.index - b.source.index).map(({source,selection}) => ({ directoryIndex:source.index,name:source.name,occurrence:source.occurrence,offset:source.offset,size:source.size,sha256:source.sha256,selection }));

const generated = new Map();
const add = (pathName, file) => generated.set(pathName, file);
add('010_things.sql', sqlFile('things','DOOM_MAP_THING',['THING_ID','X','Y','ANGLE','THING_TYPE','FLAGS'],map.things.map(r=>[r.id,r.x,r.y,r.angle,r.type,r.flags].map(sqlNumber))));
add('020_vertices.sql', sqlFile('vertices','DOOM_MAP_VERTEX',['VERTEX_ID','X','Y'],map.vertexes.map(r=>[r.id,r.x,r.y].map(sqlNumber))));
add('030_linedefs.sql', sqlFile('linedefs','DOOM_MAP_LINEDEF',['LINEDEF_ID','START_VERTEX_ID','END_VERTEX_ID','FLAGS','SPECIAL','TAG','RIGHT_SIDEDEF_ID','LEFT_SIDEDEF_ID'],map.linedefs.map(r=>[r.id,r.v1,r.v2,r.flags,r.special,r.tag,r.right===0xffff?null:r.right,r.left].map(sqlNumber))));
add('040_sidedefs.sql', sqlFile('sidedefs','DOOM_MAP_SIDEDEF',['SIDEDEF_ID','X_OFFSET','Y_OFFSET','UPPER_TEXTURE','LOWER_TEXTURE','MIDDLE_TEXTURE','SECTOR_ID'],map.sidedefs.map(r=>[sqlNumber(r.id),sqlNumber(r.xOffset),sqlNumber(r.yOffset),sqlString(r.upper),sqlString(r.lower),sqlString(r.middle),sqlNumber(r.sector)])));
add('050_sectors.sql', sqlFile('sectors','DOOM_MAP_SECTOR',['SECTOR_ID','FLOOR_HEIGHT','CEILING_HEIGHT','FLOOR_FLAT','CEILING_FLAT','LIGHT_LEVEL','SPECIAL','TAG'],map.sectors.map(r=>[sqlNumber(r.id),sqlNumber(r.floor),sqlNumber(r.ceiling),sqlString(r.floorFlat),sqlString(r.ceilingFlat),sqlNumber(r.light),sqlNumber(r.special),sqlNumber(r.tag)])));
add('060_segs.sql', sqlFile('segs','DOOM_MAP_SEG',['SEG_ID','START_VERTEX_ID','END_VERTEX_ID','ANGLE','LINEDEF_ID','DIRECTION','OFFSET'],map.segs.map(r=>[r.id,r.start,r.end,r.angle,r.linedef,r.direction,r.offset].map(sqlNumber))));
add('070_ssectors.sql', sqlFile('ssectors','DOOM_MAP_SSECTOR',['SSECTOR_ID','SEG_COUNT','FIRST_SEG_ID'],map.ssectors.map(r=>[r.id,r.segCount,r.firstSeg].map(sqlNumber))));
add('080_nodes.sql', sqlFile('nodes','DOOM_MAP_NODE',['NODE_ID','X','Y','DX','DY','BBOX0_TOP','BBOX0_BOTTOM','BBOX0_LEFT','BBOX0_RIGHT','BBOX1_TOP','BBOX1_BOTTOM','BBOX1_LEFT','BBOX1_RIGHT','CHILD0_IS_SSECTOR','CHILD0_ID','CHILD1_IS_SSECTOR','CHILD1_ID'],map.nodes.map(r=>[r.id,r.x,r.y,r.dx,r.dy,r.bboxes[0].top,r.bboxes[0].bottom,r.bboxes[0].left,r.bboxes[0].right,r.bboxes[1].top,r.bboxes[1].bottom,r.bboxes[1].left,r.bboxes[1].right,r.children[0].subsector?1:0,r.children[0].id,r.children[1].subsector?1:0,r.children[1].id].map(sqlNumber))));
add('090_reject_bytes.sql', sqlFile('rejectBytes','DOOM_REJECT_BYTE',['BYTE_OFFSET','BYTE_VALUE'],Array.from(mapLump.get('REJECT').bytes, (v,i)=>[sqlNumber(i),sqlNumber(v)])));
add('100_blockmap_bytes.sql', sqlFile('blockmapBytes','DOOM_BLOCKMAP_BYTE',['BYTE_OFFSET','BYTE_VALUE'],Array.from(mapLump.get('BLOCKMAP').bytes, (v,i)=>[sqlNumber(i),sqlNumber(v)])));
const playpal = last(rows,'PLAYPAL').bytes, colormap = last(rows,'COLORMAP').bytes;
if (playpal.length < 768 || colormap.length < 8192) die('PLAYPAL or COLORMAP is too short');
add('110_palette_texels.sql', sqlFile('paletteTexels','DOOM_PALETTE_TEXEL',['PALETTE_INDEX','RED','GREEN','BLUE'],Array.from({length:256},(_,i)=>[i,playpal[i*3],playpal[i*3+1],playpal[i*3+2]].map(sqlNumber))));
add('120_colormap_texels.sql', sqlFile('colormapTexels','DOOM_COLORMAP_TEXEL',['MAP_INDEX','PALETTE_INDEX','MAPPED_INDEX'],Array.from({length:8192},(_,i)=>[Math.floor(i/256),i%256,colormap[i]].map(sqlNumber))));
add('130_wad_sources.sql', sqlFile('wadSources','DOOM_WAD_SOURCE',['DIRECTORY_INDEX','LUMP_NAME','OCCURRENCE_INDEX','LUMP_OFFSET','LUMP_SIZE','SHA256','SELECTION_RULE'],sources.map(r=>[sqlNumber(r.directoryIndex),sqlString(r.name),sqlNumber(r.occurrence),sqlNumber(r.offset),sqlNumber(r.size),sqlString(r.sha256),sqlString(r.selection)])));
add('140_assets.sql', sqlFile('assets','DOOM_ASSET',['ASSET_ID','ASSET_KIND','ASSET_NAME','WIDTH','HEIGHT','RAW_SHA256','TEXEL_SHA256'],assets.map(r=>[sqlNumber(r.assetId),sqlString(r.kind),sqlString(r.name),sqlNumber(r.width??null),sqlNumber(r.height??null),sqlString(r.rawSha256??null),sqlString(r.texelSha256??null)])));
add('150_asset_sources.sql', sqlFile('assetSources','DOOM_ASSET_SOURCE',['ASSET_KIND','ASSET_NAME','SOURCE_ORDINAL','LUMP_NAME','SOURCE_SHA256'],assets.flatMap(a=>a.sourceLumps.map((name,i)=>[sqlString(a.kind),sqlString(a.name),sqlNumber(i),sqlString(name),sqlString(a.sourceSha256[i])]))));
let texelFileOrdinal = 0, partitionedTexelCount = 0;
for (const asset of assets) {
  const image = decodedImages.get(`${asset.kind}:${asset.name}`);
  if (!image) continue;
  texelFileOrdinal += 1;
  const denseRows = image.width * image.height;
  partitionedTexelCount += denseRows;
  add(`160_asset_texels_${String(texelFileOrdinal).padStart(4,'0')}.sql`, { dataset:'assetTexels', table:'AT', columns:['A','X','Y','C'], rowCount:denseRows, rows:function* () {
    for (let y = 0; y < image.height; y += 1) for (let x = 0; x < image.width; x += 1) yield [sqlNumber(asset.assetId),sqlNumber(x),sqlNumber(y),sqlNumber(image.pixels[y * image.width + x])];
  } });
}
if (partitionedTexelCount !== assetTexelCount) die('internal asset texel partition error');

const files = writeOutput(args['--out'], generated);
const planCounts = { things:map.things.length,vertices:map.vertexes.length,linedefs:map.linedefs.length,sidedefs:map.sidedefs.length,sectors:map.sectors.length,segs:map.segs.length,ssectors:map.ssectors.length,nodes:map.nodes.length,rejectBytes:mapLump.get('REJECT').size,blockmapBytes:mapLump.get('BLOCKMAP').size,paletteTexels:256,colormapTexels:8192 };
const xs = map.vertexes.map(v=>v.x), ys = map.vertexes.map(v=>v.y);
const manifest = { schema:1,wadSha256:PINNED_WAD_SHA256,map:MAP,encoding:'ASCII',newline:'LF',maxRowsPerBatch:MAX_ROWS,planCounts,mapBounds:{minX:Math.min(...xs),maxX:Math.max(...xs),minY:Math.min(...ys),maxY:Math.max(...ys)},playerOneSpawn:{thingIndex:157,x:-416,y:256,angle:0,flags:7},sources,assets,spotTexels:[
  {kind:'palette',name:'PLAYPAL0',x:0,y:0,value:[0,0,0]},{kind:'palette',name:'PLAYPAL0',x:112,y:0,value:[119,255,111]},{kind:'palette',name:'PLAYPAL0',x:255,y:0,value:[167,107,107]},
  {kind:'colormap',name:'COLORMAP',x:200,y:15,value:205},{kind:'colormap',name:'COLORMAP',x:255,y:31,value:8},{kind:'flat',name:'AQF001',x:31,y:32,value:0},{kind:'flat',name:'NUKAGE1',x:31,y:32,value:125},
  {kind:'wall_texture',name:'AQCONC05',x:32,y:64,value:75},{kind:'wall_texture',name:'AQDOOR01',x:64,y:64,value:99},{kind:'wall_texture',name:'COMPUTE1',x:127,y:127,value:104},{kind:'wall_texture',name:'SFALL1',x:0,y:0,value:124},{kind:'wall_texture',name:'SKY1',x:255,y:127,value:88},
  {kind:'ui_patch',name:'TITLEPIC',x:160,y:100,value:123},{kind:'ui_patch',name:'STBAR',x:319,y:31,value:6},{kind:'sprite_patch',name:'POSSA1',x:20,y:28,value:6},{kind:'sprite_patch',name:'POSSA1',x:0,y:0,value:-1}
],files,sqlTreeSha256:sha256(Buffer.from(files.map(r=>`${r.path}\0${r.sha256}\n`).join(''),'ascii')) };
fs.writeFileSync(path.join(args['--out'],'seed-manifest.json'), `${JSON.stringify(manifest,null,2)}\n`, 'ascii');
