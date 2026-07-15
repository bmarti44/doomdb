import crypto from 'node:crypto';

export const WIDTH=320,HEIGHT=200,FOV=90;
export const WAD_SHA256='7323bcc168c5a45ff10749b339960e98314740a734c30d4b9f3337001f9e703d';
const i16=(b,o)=>b.readInt16LE(o),u16=(b,o)=>b.readUInt16LE(o),i32=(b,o)=>b.readInt32LE(o);
const name=(b,o,n=8)=>b.subarray(o,o+n).toString('ascii').replace(/\0.*$/,'');
export const floorMod=(a,n)=>a-n*Math.floor(a/n);
export const lightBand=l=>Math.max(0,Math.min(31,Math.floor((255-l)/8)));
export const frameSha=p=>crypto.createHash('sha256').update(Buffer.from(p)).digest('hex');

function directory(wad){
  if(crypto.createHash('sha256').update(wad).digest('hex')!==WAD_SHA256)throw new Error('wrong pinned WAD');
  const out=[];for(let id=0,n=i32(wad,4),at=i32(wad,8);id<n;id++){const p=at+id*16;out.push({id,at:i32(wad,p),size:i32(wad,p+4),name:name(wad,p+8)});}return out;
}
function last(rows,n){for(let i=rows.length-1;i>=0;i--)if(rows[i].name===n)return rows[i];throw new Error(`missing lump ${n}`);}
function bytes(wad,row){return wad.subarray(row.at,row.at+row.size);}
function patchImage(data){
  const width=i16(data,0),height=i16(data,2),pixels=new Int16Array(width*height).fill(-1);
  for(let x=0;x<width;x++){let p=i32(data,8+x*4),previous=-1;for(let guard=0;guard<height+1024;guard++){
    const raw=data[p++];if(raw===255)break;const top=raw<=previous?previous+raw:raw,len=data[p++];p++;
    for(let y=0;y<len;y++)if(top+y>=0&&top+y<height)pixels[(top+y)*width+x]=data[p+y];
    p+=len+1;previous=top;
  }}return {width,height,pixels};
}
function textureDefs(data){
  const out=[];for(let id=0,n=i32(data,0);id<n;id++){const p=i32(data,4+id*4),width=u16(data,p+12),height=u16(data,p+14),count=u16(data,p+20),parts=[];
    for(let j=0;j<count;j++){const q=p+22+j*10;parts.push({x:i16(data,q),y:i16(data,q+2),patch:u16(data,q+4)});}out.push({name:name(data,p),width,height,parts});}return out;
}
function compose(def,patchNames,wad,rows){
  const pixels=new Int16Array(def.width*def.height).fill(-1);
  for(const part of def.parts){const img=patchImage(bytes(wad,last(rows,patchNames[part.patch])));for(let y=0;y<img.height;y++)for(let x=0;x<img.width;x++){
    const c=img.pixels[y*img.width+x],tx=part.x+x,ty=part.y+y;if(c>=0&&tx>=0&&tx<def.width&&ty>=0&&ty<def.height)pixels[ty*def.width+tx]=c;
  }}return {width:def.width,height:def.height,pixels};
}

export function decodeWad(wad){
  const rows=directory(wad),marker=rows.findIndex(r=>r.name==='E1M1');if(marker<0)throw new Error('E1M1 absent');const map=new Map(rows.slice(marker+1,marker+11).map(r=>[r.name,r]));
  const lump=n=>bytes(wad,map.get(n)??(()=>{throw new Error(`map lump ${n} absent`)})());
  const vertices=[],vb=lump('VERTEXES');for(let id=0;id<vb.length/4;id++)vertices.push({id,x:i16(vb,id*4),y:i16(vb,id*4+2)});
  const sectors=[],sb=lump('SECTORS');for(let id=0;id<sb.length/26;id++){const p=id*26;sectors.push({id,floor:i16(sb,p),ceiling:i16(sb,p+2),floorFlat:name(sb,p+4),ceilingFlat:name(sb,p+12),light:i16(sb,p+20)});}
  const sides=[],sdb=lump('SIDEDEFS');for(let id=0;id<sdb.length/30;id++){const p=id*30;sides.push({id,xOffset:i16(sdb,p),yOffset:i16(sdb,p+2),upper:name(sdb,p+4),lower:name(sdb,p+12),middle:name(sdb,p+20),sector:u16(sdb,p+28)});}
  const lines=[],lb=lump('LINEDEFS');for(let id=0;id<lb.length/14;id++){const p=id*14;lines.push({id,start:u16(lb,p),end:u16(lb,p+2),flags:u16(lb,p+4),right:u16(lb,p+10),left:u16(lb,p+12)});}
  const segs=[],gb=lump('SEGS');for(let id=0;id<gb.length/12;id++){const p=id*12;segs.push({id,start:u16(gb,p),end:u16(gb,p+2),line:u16(gb,p+6),direction:u16(gb,p+8),offset:u16(gb,p+10)});}
  const pn=bytes(wad,last(rows,'PNAMES')),patchNames=Array.from({length:i32(pn,0)},(_,i)=>name(pn,4+i*8));
  const definitions=new Map([...textureDefs(bytes(wad,last(rows,'TEXTURE1'))),...textureDefs(bytes(wad,last(rows,'TEXTURE2')))].map(d=>[d.name,d]));
  const textures=new Map(),flats=new Map();
  const texture=n=>{if(!textures.has(n)){const d=definitions.get(n);if(!d)throw new Error(`texture ${n} absent`);textures.set(n,compose(d,patchNames,wad,rows));}return textures.get(n);};
  const flat=n=>{if(!flats.has(n)){const d=bytes(wad,last(rows,n));if(d.length!==4096)throw new Error(`flat ${n} size`);flats.set(n,{width:64,height:64,pixels:Int16Array.from(d)});}return flats.get(n);};
  const cm=bytes(wad,last(rows,'COLORMAP')),colormap=Array.from({length:32},(_,band)=>Uint8Array.from(cm.subarray(band*256,band*256+256)));
  return {vertices,sectors,sides,lines,segs,texture,flat,colormap};
}

export function rays(pose){const a=pose.angle*Math.PI/180,dx=Math.cos(a),dy=Math.sin(a),scale=Math.tan(FOV*Math.PI/360),px=-dy*scale,py=dx*scale;return Array.from({length:WIDTH},(_,column)=>{const camx=2*(column+.5)/WIDTH-1;return {column,rayX:dx+px*camx,rayY:dy+py*camx};});}
function hit(map,pose,ray,seg){
  const v1=map.vertices[seg.start],v2=map.vertices[seg.end],ex=v2.x-v1.x,ey=v2.y-v1.y,D=ray.rayX*ey-ray.rayY*ex;if(Math.abs(D)<1e-12)return null;
  const qx=v1.x-pose.x,qy=v1.y-pose.y,t=(qx*ey-qy*ex)/D,u=(qx*ray.rayY-qy*ray.rayX)/D;if(t<=1e-9||u<0||u>1)return null;
  const line=map.lines[seg.line],a=map.vertices[line.start],b=map.vertices[line.end],side=(pose.x-a.x)*(b.y-a.y)-(pose.y-a.y)*(b.x-a.x)>0?0:1;
  const facing=side===0?line.right:line.left,opposite=side===0?line.left:line.right;if(facing===65535)return null;
  const fs=map.sectors[map.sides[facing].sector],os=opposite===65535?null:map.sectors[map.sides[opposite].sector],solid=!os||Math.min(fs.ceiling,os.ceiling)-Math.max(fs.floor,os.floor)<=0;
  return {t,u,line,seg,facing,opposite,fs,os,solid,side};
}
export function nearestHits(map,pose){return rays(pose).map(ray=>{const hits=map.segs.map(s=>hit(map,pose,ray,s)).filter(h=>h?.solid).sort((a,b)=>a.t-b.t||a.line.id-b.line.id||a.seg.id-b.seg.id||a.side-b.side);return {ray,hit:hits[0]??null};});}
function sample(img,x,y,badMod=false){const mod=(a,n)=>badMod?a%n:floorMod(a,n);return img.pixels[mod(Math.floor(y),img.height)*img.width+mod(Math.floor(x),img.width)];}
function wallTexture(h,worldZ){
  const sd=h.map.sides[h.facing],fs=h.fs;let textureName,origin;
  if(!h.os){textureName=sd.middle;const lowerUnpegged=(h.line.flags&16)!==0;const image=h.map.texture(textureName);origin=lowerUnpegged?fs.floor+image.height:fs.ceiling;return {image,textureName,y:origin-worldZ+sd.yOffset};}
  const wanted=worldZ>=h.os.ceiling?'upper':'lower',role=sd[wanted]!=='-'?wanted:(sd.upper!=='-'?'upper':(sd.lower!=='-'?'lower':'middle'));textureName=sd[role];
  const image=h.map.texture(textureName);
  if(role==='upper')origin=(h.line.flags&8)!==0?h.os.ceiling+image.height:fs.ceiling;
  else if(role==='lower')origin=(h.line.flags&16)!==0?fs.ceiling:h.os.floor;
  else origin=(h.line.flags&16)!==0?fs.floor+image.height:fs.ceiling;
  return {image,textureName,y:origin-worldZ+sd.yOffset};
}

export function render(map,pose,mutation={}){
  const eye=pose.z+pose.viewHeight,k=(WIDTH/(mutation.badProjection?1.9:2))/Math.tan(FOV*Math.PI/360),pixels=new Uint8Array(WIDTH*HEIGHT),layers=new Uint8Array(WIDTH*HEIGHT),hits=nearestHits(map,pose);
  for(const {ray,h:h0,hit:h1} of hits.map(x=>({ray:x.ray,h:x.hit,hit:x.hit}))){const h=h0;if(!h)throw new Error(`no solid at column ${ray.column}`);h.map=map;const top=HEIGHT/2-(h.fs.ceiling-eye)*k/h.t,bottom=HEIGHT/2-(h.fs.floor-eye)*k/h.t,band=mutation.badLightRound?Math.max(0,Math.min(31,Math.round((255-h.fs.light)/8))):lightBand(h.fs.light);
    for(let row=0;row<HEIGHT;row++){const center=row+(mutation.integerRows?0:.5),index=ray.column*HEIGHT+row;let raw,layer;
      if(center>=top&&center<bottom){const worldZ=eye+(HEIGHT/2-center)*h.t/k,wt=wallTexture(h,worldZ),segStart=map.vertices[h.seg.start],segEnd=map.vertices[h.seg.end],segLength=Math.hypot(segEnd.x-segStart.x,segEnd.y-segStart.y),x=(mutation.ignoreXOffset?0:h.seg.offset+map.sides[h.facing].xOffset)+h.u*segLength,y=mutation.ignoreYOffset?wt.y-map.sides[h.facing].yOffset:wt.y;raw=sample(wt.image,x,y,mutation.badMod);if(raw<0)throw new Error(`transparent solid wall ${wt.textureName}`);layer=10;}
      else if(center<top){const distance=(h.fs.ceiling-eye)*k/(HEIGHT/2-center),wx=pose.x+ray.rayX*distance,wy=pose.y+ray.rayY*distance;raw=sample(map.flat(mutation.swapFlats?h.fs.floorFlat:h.fs.ceilingFlat),wx,wy,mutation.badMod);layer=1;}
      else {const distance=(eye-h.fs.floor)*k/(center-HEIGHT/2),wx=pose.x+ray.rayX*distance,wy=pose.y+ray.rayY*distance;raw=sample(map.flat(mutation.swapFlats?h.fs.ceilingFlat:h.fs.floorFlat),wx,wy,mutation.badMod);layer=0;}
      const useBand=mutation.changeBand?Math.min(31,band+1):band;pixels[index]=mutation.wallNoColormap&&layer===10?raw:map.colormap[useBand][raw];layers[index]=layer;
    }
  }return {pixels,layers,hits};
}

export function miniMap(){
  const image=(seed)=>({width:64,height:64,pixels:Int16Array.from({length:4096},(_,i)=>(i+seed)&255)}),assets=new Map([['WALL',image(17)],['FLOOR',image(31)],['CEIL',image(47)]]);
  return {vertices:[{x:128,y:256},{x:128,y:-256}],sectors:[{floor:0,ceiling:96,floorFlat:'FLOOR',ceilingFlat:'CEIL',light:187}],sides:[{xOffset:-3,yOffset:5,upper:'-',lower:'-',middle:'WALL',sector:0}],lines:[{id:0,start:0,end:1,flags:16,right:0,left:65535}],segs:[{id:0,start:0,end:1,line:0,direction:0,offset:2}],texture:n=>assets.get(n),flat:n=>assets.get(n),colormap:Array.from({length:32},(_,b)=>Uint8Array.from({length:256},(_,c)=>(c+b)&255))};
}
