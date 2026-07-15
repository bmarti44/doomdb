import crypto from 'node:crypto';

export const WAD_SHA256='7323bcc168c5a45ff10749b339960e98314740a734c30d4b9f3337001f9e703d';
const i16=(b,o)=>b.readInt16LE(o),u16=(b,o)=>b.readUInt16LE(o);

function mapLumps(wad){
  if(crypto.createHash('sha256').update(wad).digest('hex')!==WAD_SHA256) throw new Error('wrong pinned WAD');
  const n=wad.readInt32LE(4),at=wad.readInt32LE(8),rows=[];
  for(let i=0;i<n;i++){const p=at+i*16;rows.push({name:wad.subarray(p+8,p+16).toString('ascii').replace(/\0.*$/,''),at:wad.readInt32LE(p),size:wad.readInt32LE(p+4)});}
  const marker=rows.findIndex(r=>r.name==='E1M1'); if(marker<0)throw new Error('E1M1 absent');
  return new Map(rows.slice(marker+1,marker+11).map(r=>[r.name,r]));
}

export function decodeE1M1(wad){
  const lumps=mapLumps(wad), row=n=>{const r=lumps.get(n);if(!r)throw new Error(`missing ${n}`);return r;};
  const vertices=[],v=row('VERTEXES'); for(let id=0;id<v.size/4;id++)vertices.push({id,x:i16(wad,v.at+id*4),y:i16(wad,v.at+id*4+2)});
  const sectors=[],sec=row('SECTORS'); for(let id=0;id<sec.size/26;id++)sectors.push({id,floor:i16(wad,sec.at+id*26),ceiling:i16(wad,sec.at+id*26+2)});
  const sides=[],s=row('SIDEDEFS'); for(let id=0;id<s.size/30;id++)sides.push({id,sector:u16(wad,s.at+id*30+28)});
  const lines=[],l=row('LINEDEFS'); for(let id=0;id<l.size/14;id++){const p=l.at+id*14;lines.push({id,start:u16(wad,p),end:u16(wad,p+2),flags:u16(wad,p+4),right:u16(wad,p+10),left:u16(wad,p+12)});}
  const segs=[],g=row('SEGS'); for(let id=0;id<g.size/12;id++){const p=g.at+id*12;segs.push({id,start:u16(wad,p),end:u16(wad,p+2),line:u16(wad,p+6),direction:u16(wad,p+8)});}
  const things=[],t=row('THINGS'); for(let id=0;id<t.size/10;id++){const p=t.at+id*10;things.push({id,x:i16(wad,p),y:i16(wad,p+2),angle:u16(wad,p+4),type:u16(wad,p+6)});}
  return {vertices,sectors,sides,lines,segs,things};
}

export function rays(pose,width=320,fovDegrees=90){
  const a=pose.angle*Math.PI/180,dirX=Math.cos(a),dirY=Math.sin(a),scale=Math.tan(fovDegrees*Math.PI/360),planeX=-dirY*scale,planeY=dirX*scale;
  return Array.from({length:width},(_,column)=>{const camx=2*(column+.5)/width-1,rayX=dirX+planeX*camx,rayY=dirY+planeY*camx;return {column,camx,dirX,dirY,planeX,planeY,rayX,rayY,dot:rayX*dirX+rayY*dirY};});
}

export function intersect(pose,ray,v1,v2){
  const ex=v2.x-v1.x,ey=v2.y-v1.y,D=ray.rayX*ey-ray.rayY*ex;
  if(Math.abs(D)<1e-12)return null;
  const qx=v1.x-pose.x,qy=v1.y-pose.y,t=(qx*ey-qy*ex)/D,u=(qx*ray.rayY-qy*ray.rayX)/D;
  return t>1e-9&&u>=0&&u<=1?{t,u,D}:null;
}

export function traceMap(map,pose,{width=320,fov=90}={}){
  const output=[];
  for(const ray of rays(pose,width,fov)){
    const hits=[];
    for(const seg of map.segs){
      const hit=intersect(pose,ray,map.vertices[seg.start],map.vertices[seg.end]); if(!hit)continue;
      const line=map.lines[seg.line],a=map.vertices[line.start],b=map.vertices[line.end];
      const side=(pose.x-a.x)*(b.y-a.y)-(pose.y-a.y)*(b.x-a.x)>0?0:1;
      const facing=side===0?line.right:line.left,opposite=side===0?line.left:line.right;
      let solid=facing===0xffff||opposite===0xffff;
      if(!solid){const fs=map.sectors[map.sides[facing].sector],os=map.sectors[map.sides[opposite].sector];solid=Math.min(fs.ceiling,os.ceiling)-Math.max(fs.floor,os.floor)<=0;}
      hits.push({...hit,linedefId:line.id,segId:seg.id,facingSide:side,sidedefId:facing===0xffff?null:facing,solid:solid?1:0});
    }
    hits.sort((a,b)=>a.t-b.t||a.linedefId-b.linedefId||a.segId-b.segId||a.facingSide-b.facingSide);
    output.push({ray,hits,nearestSolid:hits.find(h=>h.solid)??null});
  }
  return output;
}

export function traceSegments(vertices,segments,pose,opts={}){
  const map={vertices,segs:segments.map((s,id)=>({id,start:s.start,end:s.end,line:id,direction:0})),lines:segments.map((s,id)=>({id,start:s.start,end:s.end,right:s.right??id*2,left:s.left??0xffff})),sides:segments.flatMap((s,id)=>[{id:id*2,sector:s.front??0},{id:id*2+1,sector:s.back??1}]),sectors:[{id:0,floor:0,ceiling:128},{id:1,floor:0,ceiling:128}]};
  return traceMap(map,pose,opts);
}

export const canonical=(traces)=>traces.map(({ray,hits,nearestSolid})=>`${ray.column}:${ray.camx.toFixed(12)}:${ray.rayX.toFixed(12)}:${ray.rayY.toFixed(12)}:${hits.length}:${nearestSolid?`${nearestSolid.t.toFixed(9)}:${nearestSolid.u.toFixed(12)}:${nearestSolid.linedefId}:${nearestSolid.segId}:${nearestSolid.facingSide}`:'-'}\n`).join('');
export const sha=text=>crypto.createHash('sha256').update(text).digest('hex');
