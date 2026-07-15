import assert from 'node:assert/strict';
import crypto from 'node:crypto';
import fs from 'node:fs';
import path from 'node:path';
import zlib from 'node:zlib';

const root=path.resolve(import.meta.dirname,'..');
const sha=value=>crypto.createHash('sha256').update(value).digest('hex');
const read=relative=>fs.readFileSync(path.join(root,relative));
const json=relative=>JSON.parse(read(relative));

const crcTable=new Uint32Array(256);
for(let n=0;n<256;n++){let c=n;for(let k=0;k<8;k++)c=(c&1)?0xedb88320^(c>>>1):c>>>1;crcTable[n]=c>>>0;}
const crc32=value=>{let c=0xffffffff;for(const byte of value)c=crcTable[(c^byte)&255]^(c>>>8);return(c^0xffffffff)>>>0;};

function decodeCanonicalIndexedPng(png){
  assert.deepEqual([...png.subarray(0,8)],[137,80,78,71,13,10,26,10],'PNG signature');
  let at=8,ihdr,plte,idat=[];const types=[];
  while(at<png.length){
    const length=png.readUInt32BE(at),type=png.subarray(at+4,at+8).toString('ascii');
    const data=png.subarray(at+8,at+8+length),expectedCrc=png.readUInt32BE(at+8+length);
    assert.equal(crc32(png.subarray(at+4,at+8+length)),expectedCrc,`${type} CRC`);types.push(type);
    if(type==='IHDR')ihdr=data;else if(type==='PLTE')plte=data;else if(type==='IDAT')idat.push(data);
    at+=12+length;if(type==='IEND')break;
  }
  assert.equal(at,png.length,'trailing PNG bytes');assert.deepEqual(types,['IHDR','PLTE','IDAT','IEND'],'canonical chunks');
  const width=ihdr.readUInt32BE(0),height=ihdr.readUInt32BE(4);assert.deepEqual([...ihdr.subarray(8)],[8,3,0,0,0],'indexed PNG IHDR');
  assert.equal(plte.length,768,'dense palette');const scan=zlib.inflateSync(Buffer.concat(idat));assert.equal(scan.length,(width+1)*height,'scan bytes');
  const pixels=Buffer.alloc(width*height);for(let y=0;y<height;y++){const row=y*(width+1);assert.equal(scan[row],0,`row ${y} filter`);for(let x=0;x<width;x++)pixels[x*height+y]=scan[row+1+x];}
  return {width,height,palette:Buffer.from(plte),pixels};
}

const visible=json('goldens/t5.2-visible.json'),pose=visible.pose,integrity=json('goldens/integrity-T5.2.json');
assert.equal(visible.status,'HUMAN_REVIEWED_APPROVED');assert.ok(pose.review.length>=350,'visual review must be concrete');
assert.equal(sha(read('sql/render/r2/020_pixels.sql')),visible.productionPixelsSourceSha256,'reviewed production source');
for(const [relative,expected] of Object.entries(integrity.files))assert.equal(sha(read(relative)),expected,`${relative} integrity`);

const observationBytes=read('artifacts/t5.2-review/spawn-east.json'),observation=JSON.parse(observationBytes);
assert.equal(sha(observationBytes),pose.observationSha256,'observation identity');assert.deepEqual(observation.spawn,{x:pose.x,y:pose.y,angle:pose.angle});
assert.deepEqual([observation.width,observation.height,observation.order,observation.currentTic],[pose.width,pose.height,pose.order,pose.currentTic]);
assert.deepEqual([observation.pixels.length,observation.layers.length,observation.sectorIntervals.length,observation.palette.length],[64000,64000,64000,256]);
const pixels=Buffer.from(observation.pixels),palette=Buffer.from(observation.palette.flat()),layers=Buffer.from(observation.layers),sectors=Buffer.from(observation.sectorIntervals);
const rgba=Buffer.alloc(256000);for(let i=0;i<pixels.length;i++){const p=pixels[i]*3;rgba[i*4]=palette[p];rgba[i*4+1]=palette[p+1];rgba[i*4+2]=palette[p+2];rgba[i*4+3]=255;}
assert.deepEqual([sha(pixels),sha(palette),sha(rgba),sha(layers),sha(sectors)],[pose.frameSha256,pose.paletteSha256,pose.rgbaSha256,pose.layersSha256,pose.sectorIntervalsSha256]);
assert.equal(new Set(observation.pixels).size,pose.uniquePaletteIndices);assert.equal(new Set(observation.sectorIntervals).size,pose.uniqueSectorIntervals);
assert.deepEqual(observation.layerCounts,pose.layerCounts);for(const d of pose.diagnosticPixels){const i=d.column*200+d.row;assert.deepEqual([observation.pixels[i],observation.layers[i],observation.sectorIntervals[i]],[d.paletteIndex,d.layerOrdinal,d.sectorIntervalOrdinal],`${d.column},${d.row}`);}

const goldenPng=read('goldens/t5.2/spawn-east.png'),artifactPng=read('artifacts/t5.2-review/spawn-east.png');assert.deepEqual(goldenPng,artifactPng,'golden/artifact bytes');
assert.equal(goldenPng.length,pose.pngBytes);assert.equal(sha(goldenPng),pose.pngSha256);const decoded=decodeCanonicalIndexedPng(goldenPng);
assert.deepEqual([decoded.width,decoded.height],[320,200]);assert.deepEqual(decoded.palette,palette);assert.deepEqual(decoded.pixels,pixels);
process.stdout.write('PASS T5.2-VISIBLE-GOLDEN (1/1 human-reviewed database PNG; independent CRC/IDAT/palette/frame/diagnostics agreement)\n');
