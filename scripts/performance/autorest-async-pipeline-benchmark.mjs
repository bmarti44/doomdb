#!/usr/bin/env node
import {performance} from 'node:perf_hooks';
import {createHash} from 'node:crypto';
import {decodePayload} from '../../client/staging/codec.js';
import {applyPalette} from '../../client/staging/palette.js';

const root=(process.env.DOOM_ORDS_URL??'http://localhost:8080/ords/doom').replace(/\/$/,'');
const frames=Number(process.env.DOOM_PIPELINE_FRAMES??300),warm=30;
const commandPeriod=32,presentationPeriod=31.8;
const submitDepth=Number(process.env.DOOM_SUBMIT_DEPTH??4);
const fetchDepth=Number(process.env.DOOM_FETCH_DEPTH??2);
const bufferFrames=Number(process.env.DOOM_BUFFER_FRAMES??10);
const pollWaitMs=Number(process.env.DOOM_POLL_WAIT_MS??1000);
const fireEvery=Number(process.env.DOOM_FIRE_EVERY??0);
if(frames!==300)throw new Error('async pipeline gate requires exactly 300 frames');

async function post(procedure,body){
  const response=await fetch(`${root}/doom_api/${procedure}`,{method:'POST',
    headers:{'content-type':'application/json'},body:JSON.stringify(body)});
  if(!response.ok){const detail=await response.text();
    throw new Error(`${procedure} failed: ${response.status} ${detail.slice(0,400)}`);}
  return response.json();
}
const command=(seq,intent={})=>({seq,turn:intent.turn??0,forward:intent.forward??0,
  strafe:0,run:0,fire:intent.fire??0,use:0,weapon:intent.weapon??0,pause:0,automap:0,
  menu:'NONE',cheat:''});
const step=async(session,seq,intent={})=>(await post('STEP',{p_session:session,
  p_commands:JSON.stringify({v:1,commands:[command(seq,intent)]})})).p_payload;
const sleep=milliseconds=>new Promise(resolve=>setTimeout(resolve,milliseconds));
const submit=async(session,seq,intent)=>{
  let failure;
  for(let attempt=0;attempt<4;attempt++){
    try{return (await post('SUBMIT_STEP',{p_session:session,
      p_commands:JSON.stringify({v:1,commands:[command(seq,intent)]})})).p_request;}
    catch(error){failure=error;if(attempt<3)await sleep(25*(attempt+1));}
  }
  throw failure;
};
const poll=async(session,seq)=>post('POLL_FRAME',
  {p_session:session,p_seq:seq,p_wait_ms:pollWaitMs});
const quantile=(values,p)=>[...values].sort((a,b)=>a-b)[Math.ceil(values.length*p)-1];

const route=[];
const forward=count=>{for(let i=0;i<count;i++)route.push({forward:1});};
const turn=count=>{for(let i=0;i<count;i++)route.push({turn:1});};
forward(8);turn(16);forward(12);turn(16);forward(12);turn(16);forward(24);
turn(16);forward(16);turn(16);forward(28);turn(16);forward(20);turn(16);
forward(32);turn(16);forward(20);route[0].weapon=1;
if(route.length!==frames)throw new Error('async pipeline route length');
if(fireEvery>0)for(let i=0;i<route.length;i++)if(i%fireEvery===0)route[i].fire=1;

const created=await post('NEW_GAME',{p_skill:3});
const session=created.p_session;await decodePayload(created.p_payload);
const frameChain=[];
for(let seq=1;seq<=warm;seq++)frameChain.push(
  (await decodePayload(await step(session,seq))).frameSha);

let launched=0,submitInFlight=0,fetchInFlight=0,nextFetch=warm+1;
let nextPresentation=warm+1,presented=0,stalls=0,blockedSubmits=0;
let presentationTimer=null,pump=null,aborted=false;
const submitted=new Set(),fetching=new Set(),completed=new Map(),starts=new Map();
const activeSubmits=new Set();
const retryFetch=[];let nextDispatch=performance.now()+commandPeriod;
const submitLatency=[],fetchLatency=[],paints=[],hashes=new Set(),palette=new Uint8Array(768);
let resolveDone,rejectDone;
const done=new Promise((resolve,reject)=>{resolveDone=resolve;rejectDone=reject;});

const finish=()=>{
  clearInterval(pump);clearInterval(presentationTimer);
  const gaps=paints.slice(1).map((value,index)=>value-paints[index]);
  const elapsed=paints.at(-1)-paints[0];
  const result={session,frames,presented,uniqueFrames:hashes.size,submitDepth,fetchDepth,
    bufferFrames,pollWaitMs,fireEvery,stalls,blockedSubmits,
    frameChainSha:createHash('sha256').update(JSON.stringify(frameChain)).digest('hex'),
    displayFps:(presented-1)*1000/elapsed,
    submitP50Ms:quantile(submitLatency,.5),submitP95Ms:quantile(submitLatency,.95),
    fetchP50Ms:quantile(fetchLatency,.5),fetchP95Ms:quantile(fetchLatency,.95),
    paintGapP50Ms:quantile(gaps,.5),paintGapP95Ms:quantile(gaps,.95),
    paintGapMaxMs:Math.max(...gaps)};
  console.log(JSON.stringify(result));
  if(result.uniqueFrames<270||result.displayFps<30||result.paintGapP50Ms>33.3||
     result.paintGapP95Ms>33.3)rejectDone(new Error('async AutoREST pipeline gate failed'));
  else resolveDone(result);
};
const startPresentation=()=>{
  if(presentationTimer!==null||completed.size<bufferFrames)return;
  presentationTimer=setInterval(()=>{
    const frame=completed.get(nextPresentation);
    if(frame===undefined){stalls++;return;}
    completed.delete(nextPresentation++);applyPalette(frame.indices,palette);
    hashes.add(frame.frameSha);frameChain.push(frame.frameSha);
    paints.push(performance.now());presented++;
    if(presented===frames)finish();
  },presentationPeriod);
};
const launchFetch=seq=>{
  fetchInFlight++;fetching.add(seq);const started=performance.now();
  void poll(session,seq).then(async document=>{
    if(Number(document.p_ready)!==1||typeof document.p_payload!=='string'){
      retryFetch.push(seq);return;
    }
    fetchLatency.push(performance.now()-started);
    completed.set(seq,await decodePayload(document.p_payload));startPresentation();
  }).catch(error=>{aborted=true;rejectDone(error);})
    .finally(()=>{fetchInFlight--;fetching.delete(seq);});
};
const launchSubmit=()=>{
  const seq=warm+1+launched,intent=route[launched++];submitInFlight++;
  starts.set(seq,performance.now());activeSubmits.add(seq);
  void submit(session,seq,intent).then(request=>{
    if(typeof request!=='string'||!/^[0-9a-f]{32}$/.test(request))
      throw new Error('invalid async request id');
    submitLatency.push(performance.now()-starts.get(seq));submitted.add(seq);
  }).catch(error=>{aborted=true;rejectDone(new Error(`submit seq ${seq}: ${error.message}`));})
    .finally(()=>{submitInFlight--;activeSubmits.delete(seq);});
};

pump=setInterval(()=>{
  if(aborted)return;
  const now=performance.now();
  while(launched<Math.min(frames,submitDepth)&&submitInFlight<submitDepth)launchSubmit();
  const nextSeq=warm+1+launched;
  if(launched>=submitDepth&&launched<frames&&submitInFlight<submitDepth&&
     nextSeq<=nextPresentation+16&&now>=nextDispatch){
    // Advance from the absolute cadence. Basing the next deadline on `now`
    // permanently accumulates the pump's 0-4 ms timer lateness and creates an
    // artificial ~29 FPS ceiling even when the worker is keeping up.
    launchSubmit();nextDispatch+=commandPeriod;
  }
  if(launched<frames&&submitInFlight>=submitDepth)blockedSubmits++;
  while(fetchInFlight<fetchDepth&&retryFetch.length>0)launchFetch(retryFetch.shift());
  while(fetchInFlight<fetchDepth&&nextFetch<=warm+frames&&submitted.has(nextFetch)){
    launchFetch(nextFetch++);
  }
},4);

await done;
