import assert from 'node:assert/strict';
import crypto from 'node:crypto';
import fs from 'node:fs';
import path from 'node:path';
import zlib from 'node:zlib';

const root=path.resolve(import.meta.dirname,'..');
const sha=value=>crypto.createHash('sha256').update(value).digest('hex');
const read=relative=>fs.readFileSync(path.join(root,relative));
const json=relative=>JSON.parse(read(relative));
const ids=['game-pistol','game-shotgun','game-paused','menu-selection-0',
  'menu-selection-2','automap-normal','automap-full','intermission',
  'hud-hidden-values'];

const crcTable=new Uint32Array(256);
for(let n=0;n<256;n++){let c=n;for(let k=0;k<8;k++)
  c=(c&1)?0xedb88320^(c>>>1):c>>>1;crcTable[n]=c>>>0;}
const crc32=value=>{let c=0xffffffff;for(const byte of value)
  c=crcTable[(c^byte)&255]^(c>>>8);return(c^0xffffffff)>>>0;};

function decodeCanonicalIndexedPng(png){
  assert.deepEqual([...png.subarray(0,8)],[137,80,78,71,13,10,26,10],
    'PNG signature');
  let at=8,ihdr,plte;const idat=[],types=[];
  while(at<png.length){
    const length=png.readUInt32BE(at),type=png.toString('ascii',at+4,at+8);
    const data=png.subarray(at+8,at+8+length);
    assert.equal(crc32(png.subarray(at+4,at+8+length)),
      png.readUInt32BE(at+8+length),`${type} CRC`);
    types.push(type);if(type==='IHDR')ihdr=data;else if(type==='PLTE')plte=data;
    else if(type==='IDAT')idat.push(data);at+=12+length;if(type==='IEND')break;
  }
  assert.equal(at,png.length,'trailing PNG bytes');
  assert.deepEqual(types,['IHDR','PLTE','IDAT','IEND'],'canonical chunks');
  const width=ihdr.readUInt32BE(0),height=ihdr.readUInt32BE(4);
  assert.deepEqual([...ihdr.subarray(8)],[8,3,0,0,0],'indexed PNG IHDR');
  assert.equal(plte.length,768,'dense palette');
  const scan=zlib.inflateSync(Buffer.concat(idat));
  assert.equal(scan.length,(width+1)*height,'inflated scan bytes');
  const pixels=Buffer.alloc(width*height);
  for(let y=0;y<height;y++){
    const row=y*(width+1);assert.equal(scan[row],0,`row ${y} filter`);
    for(let x=0;x<width;x++)pixels[x*height+y]=scan[row+1+x];
  }
  return {width,height,palette:Buffer.from(plte),pixels};
}

function diff(a,b){let changed=0,x0=320,x1=-1,y0=200,y1=-1;
  for(let x=0;x<320;x++)for(let y=0;y<200;y++){const i=x*200+y;
    if(a[i]!==b[i]){changed++;x0=Math.min(x0,x);x1=Math.max(x1,x);
      y0=Math.min(y0,y);y1=Math.max(y1,y);}}
  return {changed,x0,x1,y0,y1};
}

const visible=json('goldens/t5.4-visible.json');
assert.match(visible.status,/^HUMAN_REVIEWED_APPROVED/,'visible approval missing');
assert.equal(visible.sourceEvaluatorManifestSha256,
  '77236041e8925fdae418af702f03ca3f7ab314e84b2e11a2dfd4ed733c1cc0ae');
assert.deepEqual(visible.observations.map(x=>x.id),ids,'reviewed frame order');
assert.ok(visible.observations.every(x=>x.review.length>=180),'concrete review notes');
assert.match(visible.quality,/no transpose, tears, unintended bands, palette corruption/i);

const integrity=json('goldens/integrity-T5.4.json');
assert.match(integrity.approval,/^HUMAN_REVIEWED_APPROVED/,'integrity approval');
for(const [relative,expected] of Object.entries(integrity.files))
  assert.equal(sha(read(relative)),expected,`${relative} integrity`);

const frames=new Map();let paletteSha;
for(const id of ids){
  const goldenJson=json(`goldens/t5.4/${id}.json`);
  const artifactJson=json(`artifacts/t5.4-review/${id}.json`);
  assert.match(goldenJson.reviewStatus,/^HUMAN_REVIEWED_APPROVED/,
    `${id} review approval`);
  for(const key of ['schema','kind','width','height','order','state','frameSha256',
    'pngSha256','sourceCounts'])assert.deepEqual(goldenJson[key],artifactJson[key],
    `${id} captured SQL diagnostic ${key}`);
  assert.equal(Object.values(goldenJson.sourceCounts).reduce((a,b)=>a+b,0),64000,
    `${id} source ownership`);
  const goldenPng=read(`goldens/t5.4/${id}.png`);
  assert.deepEqual(goldenPng,read(`artifacts/t5.4-review/${id}.png`),
    `${id} artifact/golden bytes`);
  assert.equal(sha(goldenPng),goldenJson.pngSha256,`${id} PNG identity`);
  const decoded=decodeCanonicalIndexedPng(goldenPng);
  assert.deepEqual([decoded.width,decoded.height],[320,200],`${id} dimensions`);
  assert.equal(sha(decoded.pixels),goldenJson.frameSha256,
    `${id} exact 64000 SQL palette bytes`);
  paletteSha??=sha(decoded.palette);assert.equal(sha(decoded.palette),paletteSha,
    `${id} palette identity`);frames.set(id,decoded.pixels);
}
assert.equal(new Set([...frames.values()].map(sha)).size,9,'distinct reviewed frames');

const diagnostics=visible.crossFrameDiagnostics;
for(const [key,a,b] of [
  ['pistolToShotgun','game-pistol','game-shotgun'],
  ['pistolToPaused','game-pistol','game-paused'],
  ['menu0ToMenu2','menu-selection-0','menu-selection-2'],
  ['automapNormalToFull','automap-normal','automap-full'],
  ['pistolToHiddenHud','game-pistol','hud-hidden-values']]){
  const want=diagnostics[key],got=diff(frames.get(a),frames.get(b));
  assert.deepEqual(got,{changed:want.changed,x0:want.x0,x1:want.x1,
    y0:want.y0,y1:want.y1},`${key} reviewed region`);
}
assert.equal(json('goldens/t5.4/automap-normal.json').sourceCounts.AUTOMAP_PLAYER,9,
  'normal automap player marker');
assert.equal(json('goldens/t5.4/automap-full.json').sourceCounts.AUTOMAP_PLAYER,9,
  'full automap player marker');
assert.equal(json('goldens/t5.4/automap-full.json').sourceCounts.AUTOMAP_LINE-
  json('goldens/t5.4/automap-normal.json').sourceCounts.AUTOMAP_LINE,55,
  'FULL hidden relational line pixels');

const recapture=process.env.DOOMDB_T54_RECAPTURE_DIR;
if(recapture)for(const id of ids){
  const observed=fs.readFileSync(path.join(recapture,`${id}.png`));
  assert.deepEqual(observed,read(`goldens/t5.4/${id}.png`),
    `${id} deterministic live recapture`);
}
process.stdout.write('PASS T5.4-VISIBLE-GOLDEN (9/9 human-reviewed database PNGs; independent CRC/IDAT/palette/frame/region diagnostics agreement)\n');
