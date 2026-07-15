#!/usr/bin/env node
import assert from 'node:assert/strict';
import crypto from 'node:crypto';

const supplied=process.env.ADB_ORDS_BASE_URL;
assert.ok(supplied,'ADB_ORDS_BASE_URL is required');
const root=new URL(supplied.endsWith('/')?supplied:`${supplied}/`);
assert.equal(root.protocol,'https:','managed ORDS must use HTTPS');
assert.equal(root.username,'');assert.equal(root.password,'');assert.equal(root.search,'');assert.equal(root.hash,'');
const origin=root.origin, observations=[];
const sha=x=>crypto.createHash('sha256').update(x).digest('hex');
const remember=(id,status,body)=>{assert.ok(status>=200&&status<600);observations.push({id,status,sha256:sha(Buffer.from(body))});};
async function request(id,path,{method='POST',body,headers={},accept='ok'}={}){
  const url=new URL(path,root);assert.equal(url.origin,origin);assert.equal(url.protocol,'https:');
  const response=await fetch(url,{method,headers:{accept:'application/json',...headers},body,redirect:'manual'});
  assert.equal(response.headers.get('location'),null,`${id} redirect`);
  const text=await response.text();
  if(accept==='ok')assert.ok(response.ok,`${id} ${response.status}`);
  else if(accept==='4xx')assert.ok(response.status>=400&&response.status<500,`${id} client status`);
  else assert.equal(response.status,accept,`${id} exact status`);
  let json={};
  if(text&&/^application\/json\b/i.test(response.headers.get('content-type')||''))json=JSON.parse(text);
  else if(text&&accept==='ok'&&method!=='OPTIONS')throw new Error(`${id} did not return JSON`);
  remember(id,response.status,text);return {response,text,json};
}
const value=(o,k)=>o[k]??o[k.toUpperCase()]??o.items?.[0]?.[k]??o.items?.[0]?.[k.toUpperCase()];
const jsonBody=x=>({headers:{'content-type':'application/json','origin':'https://doomdb.invalid'},body:JSON.stringify(x)});
const command=(seq,patch={})=>({seq,turn:0,forward:0,strafe:0,run:0,fire:0,use:0,weapon:0,pause:0,automap:0,menu:'NONE',cheat:'',...patch});

await request('PUBLIC_HEALTH','public_health/',{method:'GET'});
const ng=await request('NEW_GAME','doom_api/new_game/',jsonBody({p_skill:3}));
const session=value(ng.json,'p_session');assert.match(session,/^[0-9a-f]{32}$/);
let seq=1;
const step=async(id,patch={})=>request(id,'doom_api/step/',jsonBody({p_session:session,p_commands:JSON.stringify({v:1,commands:[command(seq++,patch)]})}));
const first=await step('STEP',{forward:1});assert.ok(value(first.json,'p_payload'));
const compressed=Buffer.from(value(first.json,'p_payload'),'base64');assert.equal(compressed[0],0x1f);assert.equal(compressed[1],0x8b);
remember('STEP_GZIP_BLOB',200,compressed);
await request('ASSET_PLAYPAL','doom_api/get_asset/',jsonBody({p_asset_name:'PLAYPAL'}));
await request('ASSET_AUDIO','doom_api/get_asset/',jsonBody({p_asset_name:'DSPISTOL'}));
await request('SAVE','doom_api/save_game/',jsonBody({p_session:session,p_slot:3}));
await step('CHEAT',{cheat:'GOD'});
await request('LOAD','doom_api/load_game/',jsonBody({p_session:session,p_slot:3}));
await step('REWIND',{cheat:'REWIND:1'});
const replay=await request('REPLAY','doom_api/start_replay/',jsonBody({p_session:session,p_from_tic:0,p_to_tic:1}));
assert.match(value(replay.json,'p_replay_id'),/^[0-9a-f]{32}$/);
await step('COMPLETION_SMOKE',{use:1});
await request('BAD_TOKEN_4XX','doom_api/step/',{...jsonBody({p_session:'0'.repeat(32),p_commands:JSON.stringify({v:1,commands:[command(1)]})}),accept:'4xx'});
await request('BAD_BODY_4XX','doom_api/step/',{headers:{'content-type':'application/json'},body:'{"broken":',accept:'4xx'});
await request('METHOD_405','doom_api/new_game/',{method:'GET',accept:405});
const simple=await request('CORS_SIMPLE','public_health/',{method:'GET',headers:{origin:'https://doomdb.invalid'}});
assert.match(simple.response.headers.get('access-control-allow-origin')||'',/^(?:\*|https:\/\/doomdb\.invalid)$/);
const preflight=await request('CORS_PREFLIGHT','doom_api/new_game/',{method:'OPTIONS',headers:{origin:'https://doomdb.invalid','access-control-request-method':'POST','access-control-request-headers':'content-type'}});
assert.match(preflight.response.headers.get('access-control-allow-methods')||'',/POST/i);

const expected=['PUBLIC_HEALTH','NEW_GAME','STEP','STEP_GZIP_BLOB','ASSET_PLAYPAL','ASSET_AUDIO','SAVE','LOAD','REWIND','REPLAY','CHEAT','COMPLETION_SMOKE','BAD_TOKEN_4XX','BAD_BODY_4XX','METHOD_405','CORS_SIMPLE','CORS_PREFLIGHT'];
assert.deepEqual(observations.map(x=>x.id).sort(),expected.sort());
process.stdout.write(`${JSON.stringify({schema:1,originSha256:sha(Buffer.from(origin)),observations})}\n`);
