import crypto from 'node:crypto';

export const WIDTH=16, HEIGHT=12, FOV=90, K=(WIDTH/2)/Math.tan(FOV*Math.PI/360);
export const norm=a=>((a%360)+360)%360;

export function rotationFor(viewer,object,mutation={}){
  const bearing=Math.atan2(viewer.y-object.y,viewer.x-object.x)*180/Math.PI;
  const relative=norm(bearing-object.angle+(mutation.rotationHalfTurn?180:0));
  return (Math.floor((relative+22.5)/45)%8)+1;
}

export function chooseRotation(rotation,frames,mutation={}){
  let key=mutation.forceRotation0?'0':String(rotation);
  let row=frames[key]??frames['0'];
  if(!row) throw new Error(`missing rotation ${rotation}`);
  return {asset:row.asset,flip:mutation.ignoreMirror?0:(row.flip??0)};
}

const samplePatch=(patch,x,y,flip)=>{
  const sx=flip?patch.width-1-x:x;
  return patch.texels[y]?.[sx]??null;
};

export function projectSprite(sprite,scene,mutation={}){
  const a=scene.pose.angle*Math.PI/180,dx=sprite.x-scene.pose.x,dy=sprite.y-scene.pose.y;
  const depth=dx*Math.cos(a)+dy*Math.sin(a),side=-dx*Math.sin(a)+dy*Math.cos(a);
  if(depth<=1e-9)return [];
  const rotation=rotationFor(scene.pose,sprite,mutation);
  const picked=chooseRotation(rotation,sprite.frames,mutation),patch=scene.patches[picked.asset];
  const scale=K/depth,center=WIDTH/2+side*scale;
  const left=Math.floor(center-(patch.leftOffset??patch.width/2)*scale);
  const top=Math.floor(HEIGHT/2-(sprite.z+patch.topOffset-scene.pose.eyeZ)*scale);
  const right=Math.ceil(center+(patch.width-(patch.leftOffset??patch.width/2))*scale)-1;
  const bottom=Math.ceil(HEIGHT/2-(sprite.z+patch.topOffset-patch.height-scene.pose.eyeZ)*scale)-1;
  const out=[];
  for(let row=top;row<=bottom;row++)for(let column=left;column<=right;column++){
    const ax=Math.min(patch.width-1,Math.max(0,Math.floor((column-left)*patch.width/(right-left+1))));
    const ay=Math.min(patch.height-1,Math.max(0,Math.floor((row-top)*patch.height/(bottom-top+1))));
    let palette=samplePatch(patch,ax,ay,picked.flip);
    if(palette===null){if(mutation.opaqueHoles)palette=0;else continue;}
    out.push({sourceKind:'SPRITE',sourceId:sprite.id,depth,column,row,asset:picked.asset,assetX:ax,assetY:ay,palette,rotation,flip:picked.flip,sectorId:sprite.sectorId});
  }
  return out;
}

export function maskedCandidates(scene,mutation={}){
  const candidates=[];
  for(const m of scene.masked??[])for(const p of m.pixels){
    if((p.palette===null || p.palette===-1)&&!mutation.opaqueHoles)continue;
    candidates.push({sourceKind:'MASKED',sourceId:m.id,depth:m.depth,column:p.column,row:p.row,asset:m.asset,assetX:p.assetX,assetY:p.assetY,palette:(p.palette===null||p.palette===-1)?0:p.palette,rotation:0,flip:0,sectorId:m.sectorId});
  }
  for(const s of scene.sprites??[])candidates.push(...projectSprite(s,scene,mutation));
  return candidates.map(original=>{
    const c=mutation.roundDepth?{...original,depth:Math.round(original.depth)}:original;
    const screen=c.column>=0&&c.column<WIDTH&&c.row>=0&&c.row<HEIGHT;
    const span=scene.sectorSpans?.[c.sectorId]?.[c.column];
    const sector=scene.sectorSpans==null || (!!span&&c.row>=span.top&&c.row<=span.bottom);
    const wall=scene.wallDepth?.[c.column];
    const wallVisible=wall==null || (mutation.wallBehindSprite?c.depth<=wall:c.depth<wall-1e-9);
    return {...c,screenVisible:screen?1:0,sectorVisible:sector?1:0,wallVisible:wallVisible?1:0};
  });
}

export function compose(scene,mutation={}){
  let candidates=maskedCandidates(scene,mutation);
  if(mutation.ignoreSector)candidates=candidates.map(c=>({...c,sectorVisible:1}));
  if(mutation.ignoreWall)candidates=candidates.map(c=>({...c,wallVisible:1}));
  if(mutation.ignoreScreen)candidates=candidates.map(c=>({...c,screenVisible:1}));
  const eligible=candidates.filter(c=>c.screenVisible&&c.sectorVisible&&c.wallVisible);
  eligible.sort((a,b)=>a.column-b.column||a.row-b.row||
    (mutation.fartherWins?b.depth-a.depth:a.depth-b.depth)||
    (mutation.reverseClass?(a.sourceKind==='SPRITE'?0:1)-(b.sourceKind==='SPRITE'?0:1):(a.sourceKind==='MASKED'?0:1)-(b.sourceKind==='MASKED'?0:1))||
    (mutation.reverseId?b.sourceId-a.sourceId:a.sourceId-b.sourceId)||a.assetY-b.assetY||a.assetX-b.assetX);
  const winners=[];let key='';
  for(const c of eligible){const k=`${c.column}:${c.row}`;if(k!==key){winners.push(c);key=k;}}
  return {candidates,winners};
}

const n=v=>Number.isInteger(v)?String(v):Number(v.toFixed(9));
export function canonical(result){
  return result.winners.map(x=>[x.column,x.row,x.sourceKind,x.sourceId,n(x.depth),x.asset,x.assetX,x.assetY,x.palette,x.rotation,x.flip].join(':')).join('\n')+'\n';
}
export const sha=x=>crypto.createHash('sha256').update(x).digest('hex');
