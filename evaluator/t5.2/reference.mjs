import crypto from 'node:crypto';
export const WIDTH=320,HEIGHT=200,FOV=90;
export const floorMod=(a,n)=>a-n*Math.floor(a/n);
export const frameSha=p=>crypto.createHash('sha256').update(Buffer.from(p)).digest('hex');
const seed=n=>[...n].reduce((a,c)=>(a*33+c.charCodeAt(0))&255,17);
const animate=(name,tic,a,mutation)=>{if(mutation.freezeAnimation)return name;for(const g of [a.flat,a.wall]){const i=g.names.indexOf(name);if(i>=0)return g.names[(i+Math.floor(tic/g.period))%g.names.length];}return name;};
const texel=(name,x,y,mutation={})=>{const xx=mutation.badMod?Math.floor(x)%64:floorMod(Math.floor(x),64),yy=mutation.badMod?Math.floor(y)%64:floorMod(Math.floor(y),64);return floorMod(seed(name)+xx*5+yy*11,256);};
const mapped=(raw,light,mutation={})=>{const q=(255-light)/8,band=Math.max(0,Math.min(31,mutation.roundLight?Math.round(q):Math.floor(q)));return floorMod(raw+(mutation.changeColormap?band+1:band)*3,256);};
const bound=(z,eye,k,t)=>HEIGHT/2-(z-eye)*k/t;
export function render(scene,animation,mutation={}){
 const pixels=new Uint8Array(WIDTH*HEIGHT),layers=new Uint8Array(WIDTH*HEIGHT),sectors=new Uint8Array(WIDTH*HEIGHT),k=(WIDTH/2)/Math.tan(FOV*Math.PI/360),tic=mutation.wrongTic?0:(scene.tic??0);
 for(let col=0;col<WIDTH;col++)for(let row=0;row<HEIGHT;row++){
  const center=row+(mutation.integerCenters?0:.5),idx=col*HEIGHT+row,t=scene.depth*(1+Math.abs((col+.5-WIDTH/2)/(WIDTH/2))*.12);
  const nt=bound(scene.near.ceiling,41,k,t),nb=bound(scene.near.floor,41,k,t),ft=bound(scene.far.ceiling,41,k,t),fb=bound(scene.far.floor,41,k,t);
  let layer,sector=0,raw,light=scene.near.light;
  const sharedSky=scene.near.ceilingFlat==='SKY1'&&scene.far.ceilingFlat==='SKY1',upper=!sharedSky&&center>=nt&&center<ft,lower=center>=fb&&center<nb;
  if((upper||lower)&&!mutation.dropPortalPieces){
   layer=upper?12:11;const role=upper?'upper':'lower',w=scene.wall,n=animate(w[role],tic,animation,mutation);let origin;
   if(upper)origin=(w.flags&8)&&!mutation.ignorePegging?scene.far.ceiling+64:scene.near.ceiling;
   else origin=(w.flags&16)&&!mutation.ignorePegging?scene.near.ceiling:scene.far.floor;
   const worldZ=41+(HEIGHT/2-center)*t/k,x=col/4+(mutation.ignoreOffsets?0:(w.segOffset??0)+w.xOffset),y=origin-worldZ+(mutation.ignoreOffsets?0:w.yOffset);raw=texel(n,x,y,mutation);
  } else if(center<Math.max(nt,ft)){
   const sky=scene.near.ceilingFlat==='SKY1'||scene.far.ceilingFlat==='SKY1';
   if(sky&&!mutation.disableSky){layer=3;raw=texel('SKY1',col/2,center,mutation);light=mutation.lightSky?scene.near.light:255;}
   else {layer=1;const distance=(scene.near.ceiling-41)*k/(HEIGHT/2-center);sector=mutation.nearestSectorOnly?0:(distance>t?1:0);const s=sector?scene.far:scene.near;raw=texel(animate(s.ceilingFlat,tic,animation,mutation),col+distance/8,distance/7,mutation);light=s.light;}
  } else if(center>=Math.min(nb,fb)){
   layer=0;const distance=(41-scene.near.floor)*k/(center-HEIGHT/2);sector=mutation.nearestSectorOnly?0:(distance>t?1:0);const s=sector?scene.far:scene.near;raw=texel(animate(s.floorFlat,tic,animation,mutation),col-distance/9,distance/6,mutation);light=s.light;
  } else {
   layer=4;sector=mutation.nearestSectorOnly?0:1;const s=sector?scene.far:scene.near;raw=texel(animate(center<HEIGHT/2?s.ceilingFlat:s.floorFlat,tic,animation,mutation),col,row,mutation);light=s.light;
  }
  pixels[idx]=layer===3&&!mutation.lightSky?raw:mapped(raw,light,mutation);layers[idx]=layer;sectors[idx]=sector;
 }
 return {pixels,layers,sectors};
}
export const canonical=r=>Buffer.from(r.pixels);
