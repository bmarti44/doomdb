#!/usr/bin/env node
import assert from 'node:assert/strict';
import crypto from 'node:crypto';

const supplied=process.env.ADB_ORDS_BASE_URL;
assert.ok(supplied,'ADB_ORDS_BASE_URL is required');
const schemaRoot=new URL(supplied.endsWith('/')?supplied:`${supplied}/`);
assert.equal(schemaRoot.protocol,'https:','managed ORDS must use HTTPS');
assert.equal(schemaRoot.username,'');assert.equal(schemaRoot.password,'');
assert.equal(schemaRoot.search,'');assert.equal(schemaRoot.hash,'');
const root=new URL('doom_api/',schemaRoot);
const origin=root.origin,observations=[];
const sha=value=>crypto.createHash('sha256').update(value).digest('hex');
const remember=(id,status,body)=>{
  assert.ok(status>=200&&status<600);
  observations.push({id,status,sha256:sha(Buffer.from(body))});
};
async function request(id,path,{method='POST',body,headers={},accept='ok'}={}){
  const url=new URL(path,root);assert.equal(url.origin,origin);
  const response=await fetch(url,{method,
    headers:{accept:'application/json',...headers},body,redirect:'manual'});
  assert.equal(response.headers.get('location'),null,`${id} redirect`);
  const text=await response.text();
  if(accept==='ok')assert.ok(response.ok,`${id} ${response.status}`);
  else if(accept==='4xx')assert.ok(response.status>=400&&response.status<500,
    `${id} client status ${response.status}`);
  else assert.equal(response.status,accept,`${id} exact status`);
  let json={};
  if(text&&/^application\/json\b/i.test(
    response.headers.get('content-type')||''))json=JSON.parse(text);
  else if(text&&accept==='ok'&&method!=='OPTIONS')
    throw new Error(`${id} did not return JSON`);
  remember(id,response.status,text);return {response,json};
}
const value=(document,key)=>document[key]??document[key.toUpperCase()]??
  document.items?.[0]?.[key]??document.items?.[0]?.[key.toUpperCase()];
const jsonBody=value_=>({headers:{'content-type':'application/json',
  origin:'https://doomdb.invalid'},body:JSON.stringify(value_)});

await request('PUBLIC_HEALTH',new URL('public_health/',schemaRoot).href,
  {method:'GET'});
const created=await request('CREATE_MATCH','CREATE_MATCH',jsonBody({
  p_game_mode:'COOP',p_skill:3,p_episode:1,p_map:1,
  p_display_name:'CLOUD SOLO',p_max_players:1
}));
const match=value(created.json,'p_match');
const player=value(created.json,'p_player_capability');
assert.match(match,/^[0-9a-f]{32}$/);assert.match(player,/^[0-9a-f]{64}$/);

let left=false;
try {
  const ready=await request('READY_MATCH','READY_MATCH',jsonBody({
    p_match:match,p_player_capability:player,p_ready:1
  }));
  assert.ok(['STARTING','ACTIVE'].includes(value(ready.json,'p_match_state')));
  let status;
  for(let attempt=0;attempt<900;attempt+=1){
    status=await request('MATCH_STATUS_WAIT',
      'MATCH_STATUS',jsonBody({p_match:match,p_capability:player}));
    observations.pop();
    if(value(status.json,'p_match_state')==='ACTIVE')break;
    await new Promise(resolve=>setTimeout(resolve,1000));
  }
  assert.equal(value(status?.json??{},'p_match_state'),'ACTIVE');
  status=await request('MATCH_STATUS_ACTIVE','MATCH_STATUS',
    jsonBody({p_match:match,p_capability:player}));
  const currentTic=Number(value(status.json,'p_current_tic'));
  let pixels;
  for(let attempt=0;attempt<120;attempt+=1){
    pixels=await request('POLL_PIXELS_WAIT','POLL_MATCH_PIXELS',jsonBody({
      p_match:match,p_player_capability:player,p_after_tic:-1
    }));
    observations.pop();
    if(value(pixels.json,'p_ready')===1)break;
    await new Promise(resolve=>setTimeout(resolve,100));
  }
  assert.equal(value(pixels?.json??{},'p_ready'),1);
  assert.equal(Buffer.from(value(pixels.json,'p_payload'),'base64').length,64000);
  pixels=await request('POLL_PIXELS','POLL_MATCH_PIXELS',jsonBody({
    p_match:match,p_player_capability:player,p_after_tic:-1
  }));
  assert.equal(Buffer.from(value(pixels.json,'p_payload'),'base64').length,64000);
  const pixelBatch=await request('POLL_PIXEL_BATCH',
    'POLL_MATCH_PIXEL_BATCH',jsonBody({
      p_match:match,p_player_capability:player,p_after_tic:-1,p_max_frames:8
    }));
  const pixelBatchCount=Number(value(pixelBatch.json,'p_frame_count'));
  const pixelBatchBytes=Buffer.from(value(pixelBatch.json,'p_payload'),'base64');
  assert.ok(pixelBatchCount>=1&&pixelBatchCount<=8);
  assert.equal(pixelBatchBytes.subarray(0,4).toString('ascii'),'DPB2');
  assert.equal(pixelBatchBytes.readUInt32BE(4),pixelBatchCount);
  assert.equal(pixelBatchBytes.length,8+pixelBatchCount*64_008);

  const revised=await request('REVISE_INPUT','REVISE_MATCH_INPUT',jsonBody({
    p_match:match,p_player_capability:player,p_input_seq:1,
    p_ticcmd_hex:'0800000000000000',p_target_tic:null
  }));
  assert.equal(value(revised.json,'p_accepted'),1);
  await request('INPUT_FRONTIER','MATCH_INPUT_FRONTIER',jsonBody({
    p_match:match,p_player_capability:player
  }));
  const transitions=await request('POLL_TRANSITIONS',
    'POLL_MATCH_TRANSITIONS',jsonBody({
      p_match:match,p_player_capability:player,
      p_after_tic:Math.max(0,currentTic-2),p_hold_ms:0,p_max_transitions:4
    }));
  assert.ok(value(transitions.json,'p_payload'));

  await request('ASSET_PLAYPAL','GET_ASSET',
    jsonBody({p_asset_name:'PLAYPAL'}));
  const playpalAll=await request('ASSET_PLAYPAL_ALL','GET_ASSET',
    jsonBody({p_asset_name:'PLAYPAL_ALL'}));
  const playpalAllBytes=
    Buffer.from(value(playpalAll.json,'p_payload'),'base64');
  assert.equal(playpalAllBytes.length,14*256*3);
  assert.equal(sha(playpalAllBytes),
    '3d6069acf11e7c8cf6ae77869a3b67eade15c5df686ca3a49fa31e4517359312');
  await request('ASSET_AUDIO','GET_ASSET',
    jsonBody({p_asset_name:'DSPISTOL'}));
  // Managed AutoREST maps a rejected PL/SQL application error to its
  // user-resource 555 response. It remains a fail-closed rejection; local
  // reverse-proxy status remapping is not part of the Autonomous contract.
  await request('BAD_AUTH_REJECTED','MATCH_STATUS',{
    ...jsonBody({p_match:match,p_capability:'f'.repeat(64)}),accept:555});
  await request('BAD_BODY_4XX','CREATE_MATCH',{
    headers:{'content-type':'application/json'},body:'{"broken":',accept:'4xx'});
  await request('METHOD_405','CREATE_MATCH',{method:'GET',accept:405});
  await request('LEGACY_NEW_GAME_ABSENT','NEW_GAME',{
    ...jsonBody({p_skill:3}),accept:404});
  await request('LEGACY_FRAME_ABSENT','POLL_MATCH_FRAME',{
    ...jsonBody({p_match:match,p_player_capability:player,p_tic:0,p_wait_ms:0}),
    accept:404});
  const simple=await request('CORS_SIMPLE',
    new URL('public_health/',schemaRoot).href,
    {method:'GET',headers:{origin:'https://doomdb.invalid'}});
  assert.match(simple.response.headers.get('access-control-allow-origin')||'',
    /^(?:\*|https:\/\/doomdb\.invalid)$/);
  const preflight=await request('CORS_PREFLIGHT','CREATE_MATCH',{
    method:'OPTIONS',headers:{origin:'https://doomdb.invalid',
      'access-control-request-method':'POST',
      'access-control-request-headers':'content-type'}});
  assert.match(preflight.response.headers.get(
    'access-control-allow-methods')||'',/POST/i);
  const leave=await request('LEAVE_MATCH','LEAVE_MATCH',jsonBody({
    p_match:match,p_player_capability:player
  }));
  assert.ok(['CANCELLED','FINISHED','ACTIVE'].includes(
    value(leave.json,'p_match_state')));
  left=true;
} finally {
  if(!left){
    try {
      await request('CLEANUP_LEAVE','LEAVE_MATCH',jsonBody({
        p_match:match,p_player_capability:player
      }));
      observations.pop();
    } catch {}
  }
}

const expected=['PUBLIC_HEALTH','CREATE_MATCH','READY_MATCH',
  'MATCH_STATUS_ACTIVE','POLL_PIXELS','POLL_PIXEL_BATCH',
  'REVISE_INPUT','INPUT_FRONTIER','POLL_TRANSITIONS',
  'ASSET_PLAYPAL','ASSET_PLAYPAL_ALL','ASSET_AUDIO',
  'BAD_AUTH_REJECTED','BAD_BODY_4XX','METHOD_405',
  'LEGACY_NEW_GAME_ABSENT','LEGACY_FRAME_ABSENT','CORS_SIMPLE',
  'CORS_PREFLIGHT','LEAVE_MATCH'];
assert.deepEqual(observations.map(item=>item.id).sort(),expected.sort());
process.stdout.write(`${JSON.stringify({schema:1,
  originSha256:sha(Buffer.from(origin)),observations})}\n`);
