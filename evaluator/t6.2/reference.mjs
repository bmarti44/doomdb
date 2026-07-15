// Independent evaluator-only swept-circle/opening oracle.  It imports no
// production SQL, parser, map helper, or engine definition.
export const DEFAULTS=Object.freeze({radius:16,height:56,stepHeight:24,viewHeight:41,maxContacts:2,blockingFlag:1});
const EPS=1e-9;
const dot=(ax,ay,bx,by)=>ax*bx+ay*by;
const clamp=(v,a,b)=>Math.max(a,Math.min(b,v));

function distance2(px,py,line){
  const vx=line.x2-line.x1,vy=line.y2-line.y1,l2=vx*vx+vy*vy;
  const q=l2===0?0:clamp(dot(px-line.x1,py-line.y1,vx,vy)/l2,0,1);
  const ex=px-(line.x1+q*vx),ey=py-(line.y1+q*vy);
  return ex*ex+ey*ey;
}

function sweptContact(px,py,dx,dy,line,radius,mutation={}){
  if(mutation.destinationOnly)return distance2(px+dx,py+dy,line)<=radius*radius?0:null;
  const sx=line.x2-line.x1,sy=line.y2-line.y1,len=Math.hypot(sx,sy);
  if(len<EPS)return null;
  const ux=sx/len,uy=sy/len,nx=-uy,ny=ux;
  const qn=dot(px-line.x1,py-line.y1,nx,ny),vn=dot(dx,dy,nx,ny);
  const roots=[];
  if(Math.abs(vn)>EPS)for(const side of [-radius,radius]){
    const t=(side-qn)/vn,along=dot(px+t*dx-line.x1,py+t*dy-line.y1,ux,uy);
    if(t>=-EPS&&t<=1+EPS&&along>=-EPS&&along<=len+EPS)roots.push(clamp(t,0,1));
  }
  if(!mutation.ignoreEndpoints){
    const a=dx*dx+dy*dy;
    if(a>EPS)for(const [ex,ey] of [[line.x1,line.y1],[line.x2,line.y2]]){
      const ox=px-ex,oy=py-ey,b=2*dot(ox,oy,dx,dy),c=ox*ox+oy*oy-radius*radius,disc=b*b-4*a*c;
      if(disc>=-EPS){const t=(-b-Math.sqrt(Math.max(0,disc)))/(2*a);if(t>=-EPS&&t<=1+EPS)roots.push(clamp(t,0,1));}
    }
  }
  roots.sort((a,b)=>a-b);
  for(const t of roots){
    const before=Math.max(0,t-1e-7),after=Math.min(1,t+1e-7);
    const db=distance2(px+before*dx,py+before*dy,line),da=distance2(px+after*dx,py+after*dy,line);
    if(t<=EPS?(da<db-EPS):(db>=radius*radius-1e-5&&da<=radius*radius+1e-5))return t;
  }
  return null;
}

function portal(line,sectors,z,c={}){
  if(line.leftSector===null||line.leftSector===undefined)return {blocks:true,reason:'ONE_SIDED'};
  if((line.flags&c.blockingFlag)!==0)return {blocks:true,reason:'BLOCKING_FLAG'};
  const a=sectors[line.rightSector],b=sectors[line.leftSector];
  const bottom=Math.max(a.floor,b.floor),top=Math.min(a.ceiling,b.ceiling);
  const raised=Math.max(z,bottom),step=bottom-z;
  if(top-bottom<c.height||top-raised<c.height||step>c.stepHeight)return {blocks:true,reason:step>c.stepHeight?'STEP':'OPENING'};
  return {blocks:false,reason:'PORTAL',bottom,top};
}

function locate(map,x,y){
  if(!map.regions?.length)return map.startSector??0;
  for(const r of map.regions){const v=r.axis==='y'?y:x;if(v<r.value)return r.low;}
  return map.regions.at(-1).high;
}

export function move(map,input,mutation={}){
  const c={...DEFAULTS,...map.config};
  if(mutation.zeroRadius)c.radius=0;
  if(mutation.excessStep)c.stepHeight=32;
  if(mutation.shortPlayer)c.height=48;
  if(mutation.oneContact)c.maxContacts=1;
  let x=input.x,y=input.y,z=input.z,dx=input.dx,dy=input.dy;
  const startSector=locate(map,x,y),contacts=[];
  const noclip=mutation.ignoreNoclip?false:Boolean(input.noclip);
  for(let pass=0;pass<c.maxContacts&&!noclip&&(Math.abs(dx)>EPS||Math.abs(dy)>EPS);pass++){
    const hits=[];
    for(const line of map.lines){
      if(mutation.dropCandidate===line.id)continue;
      let p=portal(line,map.sectors,z,c);
      if(mutation.oneSidedPass&&p.reason==='ONE_SIDED')p={blocks:false};
      if(mutation.ignoreBlockingFlag&&p.reason==='BLOCKING_FLAG')p={blocks:false};
      if(mutation.ignoreOpening&&p.reason==='OPENING')p={blocks:false};
      if(mutation.ignoreStep&&p.reason==='STEP')p={blocks:false};
      if(mutation.staticSectorHeights&&line.dynamicBlocks)p={blocks:false};
      if(!p.blocks)continue;
      const t=sweptContact(x,y,dx,dy,line,c.radius,mutation);
      if(t!==null)hits.push({line,t});
    }
    if(!hits.length){x+=dx;y+=dy;dx=dy=0;break;}
    hits.sort(mutation.reverseTie?(a,b)=>a.t-b.t||b.line.id-a.line.id:(a,b)=>a.t-b.t||a.line.id-b.line.id);
    const hit=mutation.lineIdFirst?[...hits].sort((a,b)=>a.line.id-b.line.id)[0]:hits[0];
    x+=dx*hit.t;y+=dy*hit.t;
    contacts.push({linedefId:hit.line.id,fraction:hit.t});
    const remx=dx*(1-hit.t),remy=dy*(1-hit.t),lx=hit.line.x2-hit.line.x1,ly=hit.line.y2-hit.line.y1,ll=lx*lx+ly*ly;
    if(mutation.noSlide){dx=dy=0;}else{const q=dot(remx,remy,lx,ly)/ll;dx=lx*q;dy=ly*q;}
  }
  if(noclip){x+=dx;y+=dy;}
  const destinationSector=locate(map,x,y),floor=map.sectors[destinationSector].floor;
  if(!mutation.keepOldFloor)z=floor;
  const viewHeight=c.viewHeight,eyeZ=(mutation.oldSectorEye?map.sectors[startSector].floor:z)+viewHeight;
  return {x,y,z,destinationSector,viewHeight,eyeZ,contacts};
}

export function canonical(result){
  const n=v=>Number(v.toFixed(9));
  return {x:n(result.x),y:n(result.y),z:n(result.z),destinationSector:result.destinationSector,
    viewHeight:n(result.viewHeight),eyeZ:n(result.eyeZ),contacts:result.contacts.map(c=>({linedefId:c.linedefId,fraction:n(c.fraction)}))};
}
