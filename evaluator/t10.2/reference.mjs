import crypto from 'node:crypto';
import zlib from 'node:zlib';

export const WIDTH=320,HEIGHT=200;
export const sha=bytes=>crypto.createHash('sha256').update(bytes).digest('hex');
export function palette(){const p=Buffer.alloc(768);for(let i=0;i<256;i++){p[i*3]=i;p[i*3+1]=255-i;p[i*3+2]=(i*17)&255}return p}
export function indices(tic=0){const out=Buffer.alloc(WIDTH*HEIGHT);for(let y=0;y<HEIGHT;y++)for(let x=0;x<WIDTH;x++)out[y*WIDTH+x]=(x+tic)&255;return out}
export function transport(tic=0){const out=Buffer.alloc(WIDTH*HEIGHT);for(let x=0;x<WIDTH;x++)for(let y=0;y<HEIGHT;y++)out[x*HEIGHT+y]=(x+tic)&255;return out}
export function columns(tic=0){return Array.from({length:WIDTH},(_,x)=>[[0,HEIGHT,(x+tic)&255]])}
export function rgba(tic=0,pal=palette()){const idx=indices(tic),out=Buffer.alloc(WIDTH*HEIGHT*4);for(let i=0;i<idx.length;i++){const c=idx[i];out[i*4]=pal[c*3];out[i*4+1]=pal[c*3+1];out[i*4+2]=pal[c*3+2];out[i*4+3]=255}return out}
export function payload(tic=0,{audio=tic?[tic,0,'DSPISTOL',255,128]:null,mode='GAME'}={}){return {v:1,tic,w:WIDTH,h:HEIGHT,mode,state_sha:sha(Buffer.from(`state:${tic}`)),frame_sha:sha(transport(tic)),cols:columns(tic),audio:audio?[audio]:[],complete:0}}
export function encodedPayload(tic=0,opts={}){return zlib.gzipSync(Buffer.from(JSON.stringify(payload(tic,opts)))).toString('base64')}
export function validateRle(p){if(p.v!==1||p.w!==WIDTH||p.h!==HEIGHT||p.cols?.length!==WIDTH)throw Error('payload dimensions');const out=Buffer.alloc(WIDTH*HEIGHT),wire=Buffer.alloc(WIDTH*HEIGHT);for(let x=0;x<WIDTH;x++){let y=0;for(const run of p.cols[x]){if(!Array.isArray(run)||run.length!==3)throw Error('run shape');const [y0,n,c]=run;if(y0!==y||!Number.isInteger(n)||n<1||y+n>HEIGHT||!Number.isInteger(c)||c<0||c>255)throw Error('run value');for(let q=0;q<n;q++){out[(y+q)*WIDTH+x]=c;wire[x*HEIGHT+y+q]=c}y+=n}if(y!==HEIGHT)throw Error('run coverage')}if(sha(wire)!==p.frame_sha)throw Error('frame hash');return out}
export function decodeIndependent(p,pal){const idx=validateRle(p),out=Buffer.alloc(WIDTH*HEIGHT*4);for(let i=0;i<idx.length;i++){const c=idx[i];out[i*4]=pal[c*3];out[i*4+1]=pal[c*3+1];out[i*4+2]=pal[c*3+2];out[i*4+3]=255}return out}
export const fixtureHashes=Object.freeze({palette:sha(palette()),index0:sha(indices(0)),rgba0:sha(rgba(0)),rgba1:sha(rgba(1)),rgba2:sha(rgba(2))});
