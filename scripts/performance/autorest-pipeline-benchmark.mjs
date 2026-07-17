#!/usr/bin/env node
import {performance} from 'node:perf_hooks';
import {decodePayload} from '../../client/staging/codec.js';
import {applyPalette} from '../../client/staging/palette.js';

const root=(process.env.DOOM_ORDS_URL??'http://localhost:8080/ords/doom').replace(/\/$/,'');
const frames=Number(process.env.DOOM_PIPELINE_FRAMES??300);
const warm=Number(process.env.DOOM_PIPELINE_WARM??30);
const period=32,maxInFlight=4,bufferFrames=6;
if(!Number.isInteger(frames)||frames<270||!Number.isInteger(warm)||warm<1)
  throw new Error('invalid pipeline sample configuration');

async function post(procedure,body){
  const response=await fetch(`${root}/doom_api/${procedure}`,{method:'POST',
    headers:{'content-type':'application/json'},body:JSON.stringify(body)});
  const document=await response.json();
  if(!response.ok)throw new Error(`${procedure} failed: ${response.status}`);
  return document;
}
const command=seq=>({seq,turn:seq%9===0?1:seq%9===4?-1:0,forward:1,
  strafe:seq%17===0?1:0,run:seq%5===0?1:0,
  fire:0,use:0,weapon:0,pause:0,automap:0,menu:'NONE',cheat:''});
const step=(session,seq)=>post('STEP',{p_session:session,
  p_commands:JSON.stringify({v:1,commands:[command(seq)]})});
const quantile=(values,p)=>[...values].sort((a,b)=>a-b)[Math.ceil(values.length*p)-1];

const created=await post('NEW_GAME',{p_skill:3});
if(typeof created.p_session!=='string'||!/^[0-9a-f]{32}$/.test(created.p_session))
  throw new Error('NEW_GAME session contract');
await decodePayload(created.p_payload);
const session=created.p_session;
for(let seq=1;seq<=warm;seq++)await decodePayload((await step(session,seq)).p_payload);

let nextSeq=warm+1,nextPresentation=nextSeq,inFlight=0,launched=0,presented=0;
let blockedPolls=0,stalls=0,aborted=false,presentationTimer=null;
let nextDispatch=performance.now()+period;
const palette=new Uint8Array(768),starts=new Map(),completed=new Map();
const latency=[],paints=[],hashes=new Set();

let resolveDone,rejectDone;
const done=new Promise((resolve,reject)=>{resolveDone=resolve;rejectDone=reject;});
let pump;
const finish=()=>{
  clearInterval(pump);clearInterval(presentationTimer);
  const gaps=paints.slice(1).map((value,index)=>value-paints[index]);
  const displayMs=paints.at(-1)-paints[0];
  const result={session,frames,presented,uniqueFrames:hashes.size,depth:maxInFlight,
    bufferFrames,periodMs:period,blockedPolls,stalls,
    displayFps:(presented-1)*1000/displayMs,
    inputDecodeP50Ms:quantile(latency,.5),inputDecodeP95Ms:quantile(latency,.95),
    inputDecodeMaxMs:Math.max(...latency),paintGapP50Ms:quantile(gaps,.5),
    paintGapP95Ms:quantile(gaps,.95),paintGapMaxMs:Math.max(...gaps)};
  console.log(JSON.stringify(result));
  if(result.uniqueFrames<270||result.paintGapP50Ms>33.3||result.paintGapP95Ms>33.3)
    rejectDone(new Error('AutoREST pipeline gate failed'));
  else resolveDone(result);
};
const startPresentation=()=>{
  if(presentationTimer!==null||completed.size<bufferFrames)return;
  presentationTimer=setInterval(()=>{
    const frame=completed.get(nextPresentation);
    if(frame===undefined){stalls++;return;}
    completed.delete(nextPresentation++);applyPalette(frame.indices,palette);
    hashes.add(frame.frameSha);paints.push(performance.now());presented++;
    if(presented===frames)finish();
  },period);
};
const launch=()=>{
  const seq=nextSeq++;launched++;inFlight++;starts.set(seq,performance.now());
  void step(session,seq).then(document=>decodePayload(document.p_payload)).then(frame=>{
    latency.push(performance.now()-starts.get(seq));completed.set(seq,frame);
    startPresentation();
  }).catch(error=>{
    aborted=true;clearInterval(pump);if(presentationTimer!==null)clearInterval(presentationTimer);
    rejectDone(error);
  }).finally(()=>{inFlight--;});
};
pump=setInterval(()=>{
  if(aborted||launched>=frames)return;
  const now=performance.now();if(now<nextDispatch)return;
  if(inFlight>=maxInFlight){blockedPolls++;return;}
  launch();nextDispatch+=period;
},4);

await done;
