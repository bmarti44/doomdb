import assert from 'node:assert/strict';
import crypto from 'node:crypto';
import zlib from 'node:zlib';

export const WIDTH=320,HEIGHT=200;
export const sha256=b=>crypto.createHash('sha256').update(b).digest('hex');

export function canonicalPixels(rows,width=WIDTH,height=HEIGHT){
  assert.equal(rows.length,width*height,'frame row count');
  const out=Buffer.alloc(width*height),seen=new Uint8Array(width*height);
  for(const r of rows){
    assert.ok(Number.isInteger(r.column)&&r.column>=0&&r.column<width,'column range');
    assert.ok(Number.isInteger(r.row)&&r.row>=0&&r.row<height,'row range');
    assert.ok(Number.isInteger(r.cidx)&&r.cidx>=0&&r.cidx<=255,'palette range');
    const key=r.column*height+r.row;assert.equal(seen[key],0,'duplicate pixel');seen[key]=1;out[key]=r.cidx;
  }
  assert.ok(seen.every(v=>v===1),'pixel gap');return out;
}

export function encodeRle(pixels,width=WIDTH,height=HEIGHT){
  assert.equal(pixels.length,width*height,'pixel byte count');const cols=[];
  for(let x=0;x<width;x++){
    const runs=[];let y0=0,c=pixels[x*height];
    for(let y=1;y<=height;y++)if(y===height||pixels[x*height+y]!==c){runs.push([y0,y-y0,c]);y0=y;c=pixels[x*height+y];}
    cols.push(runs);
  }
  return cols;
}

export function decodeRle(cols,width=WIDTH,height=HEIGHT){
  assert.equal(cols.length,width,'RLE column count');const out=Buffer.alloc(width*height);
  for(let x=0;x<width;x++){
    let next=0,prior=null;
    for(const run of cols[x]){
      assert.ok(Array.isArray(run)&&run.length===3,'RLE tuple shape');const [y0,len,cidx]=run;
      assert.ok(Number.isInteger(y0)&&Number.isInteger(len)&&Number.isInteger(cidx),'RLE integer fields');
      assert.equal(y0,next,'RLE adjacency');assert.ok(len>0,'RLE positive length');assert.ok(y0+len<=height,'RLE height');assert.ok(cidx>=0&&cidx<=255,'RLE palette range');
      assert.notEqual(cidx,prior,'adjacent equal runs must merge');out.fill(cidx,x*height+y0,x*height+y0+len);next+=len;prior=cidx;
    }
    assert.equal(next,height,'RLE full-column coverage');
  }
  return out;
}

export function paletteBytes(palette){
  assert.equal(palette.length,256,'palette entry count');const out=Buffer.alloc(768);
  palette.forEach((rgb,i)=>{assert.ok(Array.isArray(rgb)&&rgb.length===3,'RGB tuple');rgb.forEach((v,j)=>{assert.ok(Number.isInteger(v)&&v>=0&&v<=255,'RGB range');out[i*3+j]=v;});});return out;
}

export function rgbaBytes(pixels,palette){
  const pal=paletteBytes(palette),out=Buffer.alloc(pixels.length*4);
  for(let i=0;i<pixels.length;i++){const p=pixels[i]*3;out[i*4]=pal[p];out[i*4+1]=pal[p+1];out[i*4+2]=pal[p+2];out[i*4+3]=255;}return out;
}

const crcTable=(()=>{const t=new Uint32Array(256);for(let n=0;n<256;n++){let c=n;for(let k=0;k<8;k++)c=(c&1)?0xedb88320^(c>>>1):c>>>1;t[n]=c>>>0;}return t;})();
const crc32=b=>{let c=0xffffffff;for(const v of b)c=crcTable[(c^v)&255]^(c>>>8);return (c^0xffffffff)>>>0;};
function chunk(type,data){const t=Buffer.from(type,'ascii'),len=Buffer.alloc(4),crc=Buffer.alloc(4);len.writeUInt32BE(data.length);crc.writeUInt32BE(crc32(Buffer.concat([t,data])));return Buffer.concat([len,t,data,crc]);}

export function encodeIndexedPng(pixels,palette,width=WIDTH,height=HEIGHT){
  assert.equal(pixels.length,width*height,'PNG pixel count');const ihdr=Buffer.alloc(13);ihdr.writeUInt32BE(width);ihdr.writeUInt32BE(height,4);ihdr[8]=8;ihdr[9]=3;
  const scan=Buffer.alloc((width+1)*height);
  for(let y=0;y<height;y++){const at=y*(width+1);scan[at]=0;for(let x=0;x<width;x++)scan[at+1+x]=pixels[x*height+y];}
  return Buffer.concat([Buffer.from([137,80,78,71,13,10,26,10]),chunk('IHDR',ihdr),chunk('PLTE',paletteBytes(palette)),chunk('IDAT',zlib.deflateSync(scan,{level:9})),chunk('IEND',Buffer.alloc(0))]);
}

export function decodeIndexedPng(png){
  assert.deepEqual(png.subarray(0,8),Buffer.from([137,80,78,71,13,10,26,10]),'PNG signature');let at=8,width,height,palette,idat=[],types=[];
  while(at<png.length){const len=png.readUInt32BE(at),type=png.subarray(at+4,at+8).toString('ascii'),data=png.subarray(at+8,at+8+len),got=png.readUInt32BE(at+8+len);assert.equal(got,crc32(png.subarray(at+4,at+8+len)),`PNG ${type} CRC`);types.push(type);at+=12+len;
    if(type==='IHDR'){width=data.readUInt32BE(0);height=data.readUInt32BE(4);assert.deepEqual([...data.subarray(8)],[8,3,0,0,0],'indexed PNG IHDR');}else if(type==='PLTE')palette=Buffer.from(data);else if(type==='IDAT')idat.push(data);else if(type==='IEND')break;else assert.fail(`noncanonical PNG chunk ${type}`);
  }
  assert.deepEqual(types,['IHDR','PLTE','IDAT','IEND'],'canonical PNG chunk order');assert.equal(at,png.length,'trailing PNG bytes');assert.equal(palette.length,768,'PNG palette size');const scan=zlib.inflateSync(Buffer.concat(idat));assert.equal(scan.length,(width+1)*height,'PNG scan size');const pixels=Buffer.alloc(width*height);
  for(let y=0;y<height;y++){const row=y*(width+1);assert.equal(scan[row],0,'PNG filter must be None');for(let x=0;x<width;x++)pixels[x*height+y]=scan[row+1+x];}
  return {width,height,palette,pixels};
}

export function diagnostics(pixels,palette,columns=[0,80,159,160,239,319],points=[[0,0],[159,99],[160,100],[319,199]]){
  const rgba=rgbaBytes(pixels,palette);return {columns:columns.map(column=>({column,runs:encodeRle(pixels)[column],sha256:sha256(pixels.subarray(column*HEIGHT,(column+1)*HEIGHT))})),pixels:points.map(([column,row])=>{const at=column*HEIGHT+row,i=at*4;return {column,row,cidx:pixels[at],rgba:[...rgba.subarray(i,i+4)]};})};
}
