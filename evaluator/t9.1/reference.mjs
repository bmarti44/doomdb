import crypto from 'node:crypto';

export const WIDTH=160,HEIGHT=96,FRAMES=150,MAX_HEAT=36;
export const floorMod=(a,n)=>((a%n)+n)%n;
export function noise(frame,x,y,opt={}){
  const value=frame*73+x*151+y*199+frame*x*17+x*y*13;
  return floorMod(value+(opt.noiseBias??0),256);
}
export function generate(config={},opt={}){
  const width=config.width??WIDTH,height=config.height??HEIGHT,frames=config.frames??FRAMES;
  const out=Array.from({length:frames},()=>new Uint8Array(width*height));
  for(let frame=0;frame<frames;frame++)for(let y=height-1;y>=0;y--)for(let x=0;x<width;x++){
    const i=y*width+x,n=noise(frame,x,y,opt);
    if(y===height-1){out[frame][i]=(opt.constantBase?36:28+floorMod(n,9));continue}
    if(frame===0){out[frame][i]=0;continue}
    const shift=opt.noLateral?0:floorMod(n,3)-1;
    const sourceX=floorMod(x+shift,width);
    const decay=opt.noDecay?0:floorMod(Math.floor(n/3),3);
    const sourceY=opt.sameRow?y:y+1;
    out[frame][i]=Math.max(0,out[frame-1][sourceY*width+sourceX]-decay);
  }
  return out;
}
export function encode(frame){
  const runs=[];let start=0,value=frame[0];
  for(let i=1;i<=frame.length;i++)if(i===frame.length||frame[i]!==value){
    runs.push({runNo:runs.length,startOffset:start,runLength:i-start,intensity:value});
    start=i;value=frame[i];
  }
  return runs;
}
export function decode(runs,size=WIDTH*HEIGHT){
  const out=new Uint8Array(size);let cursor=0,last=null;
  for(let i=0;i<runs.length;i++){
    const r=runs[i];
    if(r.runNo!==i||r.startOffset!==cursor||!Number.isInteger(r.runLength)||r.runLength<1||
       !Number.isInteger(r.intensity)||r.intensity<0||r.intensity>MAX_HEAT||r.intensity===last)throw Error('noncanonical run');
    if(cursor+r.runLength>size)throw Error('run overflow');
    out.fill(r.intensity,cursor,cursor+r.runLength);cursor+=r.runLength;last=r.intensity;
  }
  if(cursor!==size)throw Error('incomplete frame');
  return out;
}
export const frameHash=frame=>crypto.createHash('sha256').update(frame).digest('hex');
export const animationHash=frames=>crypto.createHash('sha256').update(Buffer.concat(frames.map(x=>Buffer.from(x)))).digest('hex');
export function stats(frames){
  let cells=0,min=MAX_HEAT,max=0,nonzero=0,runs=0;
  for(const f of frames){cells+=f.length;runs+=encode(f).length;for(const v of f){min=Math.min(min,v);max=Math.max(max,v);if(v)nonzero++;}}
  return {cells,min,max,nonzero,runs,rawBytes:cells,runRows:runs};
}
