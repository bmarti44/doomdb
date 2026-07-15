import crypto from 'node:crypto';

export const FAR_DISTANCE = 4096;

const sideOf = (pose, wall) =>
  (pose.x-wall.x1)*(wall.y2-wall.y1)-(pose.y-wall.y1)*(wall.x2-wall.x1)>0 ? 0 : 1;

export function intersections(scene, pose, ray={x:Math.cos(pose.angle*Math.PI/180),y:Math.sin(pose.angle*Math.PI/180)}, mutation={}) {
  const rows=[];
  for (const wall of scene.walls) {
    const ex=wall.x2-wall.x1, ey=wall.y2-wall.y1;
    let d=ray.x*ey-ray.y*ex;
    if (mutation.flipDeterminant) d=-d;
    if (Math.abs(d)<1e-12) continue;
    const qx=wall.x1-pose.x,qy=wall.y1-pose.y;
    let t=(qx*ey-qy*ex)/d;const u=(qx*ray.y-qy*ray.x)/d;
    if(mutation.roundDepth)t=Math.round(t);
    if (t<=1e-9 || u<0 || u>1) continue;
    let facingSide=sideOf(pose,wall);
    if (mutation.reverseFacing) facingSide=1-facingSide;
    const facingSector=facingSide===0?wall.right:wall.left;
    const oppositeSector=facingSide===0?wall.left:wall.right;
    rows.push({t,u,linedefId:wall.id,segId:wall.segId??wall.id,facingSide,facingSector,oppositeSector});
  }
  rows.sort((a,b)=>a.t-b.t || (mutation.reverseLineTie?b.linedefId-a.linedefId:a.linedefId-b.linedefId) || a.segId-b.segId || a.facingSide-b.facingSide);
  return rows;
}

export function timeline(scene, pose, mutation={}) {
  const sectors=new Map(scene.sectors.map(s=>[s.id,s]));
  let ordered=intersections(scene,pose,undefined,mutation);
  if(mutation.nearestOnly) ordered=ordered.slice(0,1);
  let current=scene.startSector, priorT=0, terminated=false, intervalOrdinal=0;
  const hits=[],intervals=[];
  for(let hitOrdinal=0;hitOrdinal<ordered.length;hitOrdinal++){
    const h=ordered[hitOrdinal], from=sectors.get(h.facingSector), to=sectors.get(h.oppositeSector);
    let active=!terminated && h.facingSector===current;
    if(mutation.ignoreCompatibility) active=!terminated;
    let bottom=null,top=null,closed=1,lowerBottom=null,lowerTop=null,upperBottom=null,upperTop=null,transition=0,termination=0;
    if(from&&to){
      bottom=mutation.unionOpening?Math.min(from.floor,to.floor):Math.max(from.floor,to.floor);
      top=mutation.unionOpening?Math.max(from.ceiling,to.ceiling):Math.min(from.ceiling,to.ceiling);
      closed=(mutation.closedStrict ? top<bottom : top<=bottom)?1:0;
      if(to.floor>from.floor){lowerBottom=from.floor;lowerTop=to.floor;}
      if(to.ceiling<from.ceiling){upperBottom=to.ceiling;upperTop=from.ceiling;}
    }
    if(mutation.dropLower){lowerBottom=null;lowerTop=null;}
    if(mutation.dropUpper){upperBottom=null;upperTop=null;}
    if(active){
      intervals.push({ordinal:intervalOrdinal++,tStart:priorT,tEnd:h.t,sectorId:current,terminatedBy:h.linedefId,isFinal:0});
      priorT=h.t;
      if(to && (!closed||mutation.forceOpen)){transition=1;if(!mutation.staySector)current=to.id;}
      else if(!to&&mutation.oneSidedOpen){transition=1;}
      else {termination=1;terminated=true;}
    }
    hits.push({...h,hitOrdinal,active:active?1:0,fromSector:active?h.facingSector:null,toSector:active&&transition&&to?to.id:null,
      openingBottom:bottom,openingTop:top,isClosed:closed,lowerBottom,lowerTop,upperBottom,upperTop,isTransition:transition,isTermination:termination});
  }
  if(!terminated&&!mutation.dropFinal) intervals.push({ordinal:intervalOrdinal,tStart:priorT,tEnd:mutation.badFar?2048:(scene.farDistance??FAR_DISTANCE),sectorId:current,terminatedBy:null,isFinal:1});
  return {hits,intervals};
}

const n=v=>v===null?'~':Number.isInteger(v)?String(v):v.toFixed(9);
export function canonical(result){
  const hs=result.hits.map(h=>['H',h.hitOrdinal,n(h.t),h.linedefId,h.segId,h.facingSide,n(h.facingSector),n(h.oppositeSector),h.active,n(h.fromSector),n(h.toSector),n(h.openingBottom),n(h.openingTop),n(h.lowerBottom),n(h.lowerTop),n(h.upperBottom),n(h.upperTop),h.isClosed,h.isTransition,h.isTermination].join(':'));
  const is=result.intervals.map(i=>['I',i.ordinal,n(i.tStart),n(i.tEnd),i.sectorId,n(i.terminatedBy),i.isFinal].join(':'));
  return [...hs,...is].join('\n')+'\n';
}
export const sha=text=>crypto.createHash('sha256').update(text).digest('hex');

export function transformScene(scene,{dx=0,dy=0,mirrorX=null}={}){
  const walls=scene.walls.map(w=>{
    if(mirrorX===null)return {...w,x1:w.x1+dx,x2:w.x2+dx,y1:w.y1+dy,y2:w.y2+dy};
    return {...w,x1:2*mirrorX-w.x1+dx,x2:2*mirrorX-w.x2+dx,y1:w.y1+dy,y2:w.y2+dy,right:w.left,left:w.right};
  });
  return {...scene,sectors:scene.sectors.map(s=>({...s})),walls};
}
