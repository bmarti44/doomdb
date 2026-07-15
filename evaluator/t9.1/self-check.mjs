import assert from 'node:assert/strict';import fs from 'node:fs';
import {WIDTH,HEIGHT,FRAMES,MAX_HEAT,animationHash,decode,encode,floorMod,frameHash,generate,noise,stats} from './reference.mjs';
const load=n=>JSON.parse(fs.readFileSync(new URL(n,import.meta.url))),f=load('./fixtures.json'),e=load('./expectations.json'),t=load('./test-ids.json'),m=load('./mutation-specs.json'),p=load('./capability-policy.json');let n=0;
const eq=(a,b,s)=>{assert.deepEqual(a,b,s);n++},ok=(x,s)=>{assert.ok(x,s);n++};
eq([f.frames,f.width,f.height],[FRAMES,WIDTH,HEIGHT],'full dimensions');eq(f.frames*f.width*f.height,2304000,'full cells');eq(f.order,{frame:'ASC',y:'DESC',x:'ASC'},'explicit order');eq(f.maxHeat,MAX_HEAT,'heat range');eq(p.status,'REQUIRED_NO_FALLBACK','capability mandatory');ok(p.failurePolicy.includes('blocks T9.1')&&p.documentation.includes('oracle.com'),'capability policy');
eq(t.tests.length,21,'test count');eq(new Set(t.tests.map(x=>x.id)).size,21,'unique test ids');eq(t.tests.reduce((a,x)=>a+x.assertions,0),t.declaredAssertions,'assertion total');eq(t.declaredAssertions,12731825,'fixed assertions');ok(t.tests.every(x=>/^T91-[A-Z0-9-]+$/.test(x.id)&&x.intent.length>=125),'strong test intents');eq(m.mutations.length,26,'mutation count');eq(new Set(m.mutations.map(x=>x.id)).size,26,'unique mutation ids');ok(m.mutations.every(x=>t.tests.some(y=>y.id===x.killedBy)&&x.change.length>=65&&x.reason.length>=75),'focused documented mutations');
const frames=generate(f);eq(frames.length,150,'frame count');ok(frames.every(x=>x.length===15360),'frame size');eq(frames.map(frameHash),e.frameHashes,'all exact frame hashes');eq(animationHash(frames),e.animationHash,'animation hash');eq(stats(frames),e.stats,'full stats');eq(e.frameRunCounts.length,150,'run count vector');eq(frames.map(x=>encode(x).length),e.frameRunCounts,'exact frame runs');
let cells=0,nonzero=0,min=36,max=0;for(let frame=0;frame<FRAMES;frame++){
  const a=frames[frame],runs=encode(a),decoded=decode(runs,a.length);eq(Buffer.from(decoded),Buffer.from(a),`RLE frame ${frame}`);let cursor=0,last=null;
  for(let ri=0;ri<runs.length;ri++){const r=runs[ri];eq(r.runNo,ri,`dense run ${frame}/${r.runNo}`);eq(r.startOffset,cursor,`adjacent run ${frame}/${r.runNo}`);ok(r.intensity!==last,`nonmergeable ${frame}/${r.runNo}`);cursor+=r.runLength;last=r.intensity}eq(cursor,a.length,`coverage ${frame}`);
  for(let y=HEIGHT-1;y>=0;y--)for(let x=0;x<WIDTH;x++){
    const v=a[y*WIDTH+x];ok(Number.isInteger(v)&&v>=0&&v<=36,`range ${frame}/${y}/${x}`);cells++;if(v)nonzero++;min=Math.min(min,v);max=Math.max(max,v);
    const z=noise(frame,x,y);ok(z>=0&&z<256,`noise ${frame}/${y}/${x}`);
    if(y===HEIGHT-1)eq(v,28+floorMod(z,9),`base ${frame}/${x}`);
    else if(frame===0)eq(v,0,`initial zero ${y}/${x}`);
    else{const sx=floorMod(x+floorMod(z,3)-1,WIDTH),decay=floorMod(Math.floor(z/3),3);eq(v,Math.max(0,frames[frame-1][(y+1)*WIDTH+sx]-decay),`recurrence ${frame}/${y}/${x}`)}
  }
}
eq(cells,2304000,'visited all cells');eq(nonzero,e.stats.nonzero,'nonzero exact');eq([min,max],[0,36],'range extrema');ok(new Set(e.frameHashes).size===150,'all frames distinct');ok(e.stats.runs<e.stats.cells,'RLE fewer rows than cells');
const small=generate(f.feasibility.small),smallStats=stats(small);eq(smallStats,{cells:1536,min:0,max:36,nonzero:576,runs:485,rawBytes:1536,runRows:485},'small probe exact');eq(animationHash(small),'839e061d802ca3021f2261bb3e644b8bb9d1149847cf8c9a792467417f60295d','small probe hash');ok(e.stats.cells*32<f.feasibility.maxEstimatedBytes,'conservative full memory bound');eq(f.visualReview,{status:'PENDING',artifactSha256:null,reviewedFrameHashes:[],note:'Must be a real 150-frame animation decoded from accepted Oracle RLE rows; no evaluator-generated image is a visual golden.'},'visual review not invented');
process.stdout.write(`PASS T9.1-EVAL-SELF-CHECK (${n}/${n} fixture-reference assertions; ${cells} independent cells)\n`);
