#!/usr/bin/env node
import assert from 'node:assert/strict';
import fs from 'node:fs';

const percentile=(values,fraction)=>{
  const ordered=[...values].sort((left,right)=>left-right);
  return ordered[Math.ceil(ordered.length*fraction)-1];
};

export function evaluateTwoPovEvidence(evidence,expectedArtifact=null) {
  assert.equal(evidence?.schema,1);
  assert.equal(evidence.classification,'RAW_TWO_POV_BROWSER_SAMPLES');
  assert.equal(evidence.requiredRenderer,'DATABASE_PIXELS');
  for(const field of [
    'authoritySha256','rendererSha256','coordinatorSha256']) {
    assert.match(evidence.artifact?.[field]??'',/^[0-9a-f]{64}$/);
    if(expectedArtifact!==null)
      assert.equal(evidence.artifact[field],expectedArtifact[field]);
  }
  assert.equal(evidence.framesPerPlayer,300);
  assert.equal(evidence.players?.length,2);
  const summaries=evidence.players.map((player,slot)=>{
    assert.equal(player.slot,slot);
    assert.equal(player.presents?.length,300);
    assert.ok(player.presents.every(frame=>
      frame.source==='database-framebuffer'));
    assert.ok(player.presents.every(frame=>
      typeof frame.frameSha256==='string'&&
      /^[0-9a-f]{64}$/.test(frame.frameSha256)));
    assert.equal(new Set(
      player.presents.map(frame=>frame.frameSha256)).size,300);
    let confirmedDropCount=0;
    for(let index=1;index<player.presents.length;index+=1) {
      const ticDelta=player.presents[index].tic-
        player.presents[index-1].tic;
      assert.ok(ticDelta>=1&&ticDelta<=3);
      confirmedDropCount+=ticDelta-1;
      assert.ok(Number.isFinite(player.presents[index].at)
        &&player.presents[index].at>player.presents[index-1].at);
    }
    assert.ok(confirmedDropCount<=60);
    const gaps=player.presents.slice(1)
      .map((frame,index)=>frame.at-player.presents[index].at);
    const fps=299*1000/
      (player.presents[299].at-player.presents[0].at);
    const p95=percentile(gaps,.95);
    const p99=percentile(gaps,.99);
    const maximum=Math.max(...gaps);
    const occupancy=player.presents
      .map(frame=>frame.bufferedFrames).sort((left,right)=>left-right);
    assert.ok(occupancy.every(value=>
      Number.isInteger(value)&&value>=0&&value<=64));
    const polls=(player.resources??[]).filter(resource=>
      resource.name==='poll_match_pixel_batch'
        ||resource.name==='exchange_match_pixel_batch');
    assert.ok(polls.length>0,`player ${slot} has no DPB2 resource samples`);
    assert.ok(polls.every(resource=>
      Number.isFinite(resource.ttfb)&&resource.ttfb>=0
      &&Number.isFinite(resource.download)&&resource.download>=0));
    const pollTtfbP95=percentile(polls.map(resource=>resource.ttfb),.95);
    const pollDownloadP95=
      percentile(polls.map(resource=>resource.download),.95);
    assert.ok(fps>=30,`player ${slot} fps=${fps}`);
    assert.ok(p95<=33.333,`player ${slot} p95=${p95}`);
    assert.ok(p99<=2*1000/35,`player ${slot} p99=${p99}`);
    assert.ok(maximum<=100,`player ${slot} maximum=${maximum}`);
    return {
      slot,fps,p95,p99,maximum,confirmedDropCount,
      occupancyMin:occupancy[0],
      occupancyP50:percentile(occupancy,.5),
      occupancyP95:percentile(occupancy,.95),
      pollCount:polls.length,pollTtfbP95,pollDownloadP95
    };
  });
  const secondByTic=new Map(evidence.players[1].presents
    .map(frame=>[frame.tic,frame.frameSha256]));
  const common=evidence.players[0].presents
    .filter(frame=>secondByTic.has(frame.tic));
  assert.ok(common.length>=250,`two-POV overlap=${common.length}`);
  assert.ok(common.every(frame=>
    frame.frameSha256!==secondByTic.get(frame.tic)),
  'two-POV framebuffers collapsed');
  return summaries;
}

function syntheticEvidence() {
  return {
    schema:1,
    classification:'RAW_TWO_POV_BROWSER_SAMPLES',
    requiredRenderer:'DATABASE_PIXELS',
    artifact:{
      authoritySha256:'a'.repeat(64),
      rendererSha256:'b'.repeat(64),
      coordinatorSha256:'c'.repeat(64)
    },
    framesPerPlayer:300,
    players:[0,1].map(slot=>({
      slot,
      presents:Array.from({length:300},(_,index)=>({
        tic:1000+index,
        at:index*28,
        frameSha256:(slot*300+index+1).toString(16).padStart(64,'0'),
        source:'database-framebuffer',
        bufferedFrames:6,
        selectedDepth:6,
        expectedBatchTics:4,
        playoutMode:'FREE'
      })),
      confirmedDrops:[],
      resources:Array.from({length:50},()=>({
        name:'poll_match_pixel_batch',queue:0,ttfb:5,download:3,duration:8
      }))
    }))
  };
}

function rejects(mutate) {
  const evidence=structuredClone(syntheticEvidence());
  mutate(evidence);
  assert.throws(()=>evaluateTwoPovEvidence(evidence));
}

if(process.argv[2]==='--self-test') {
  assert.equal(evaluateTwoPovEvidence(syntheticEvidence()).length,2);
  rejects(value=>{value.players[0].presents[1].frameSha256=
    value.players[0].presents[0].frameSha256;});
  rejects(value=>{value.players[0].presents[1].tic+=3;});
  rejects(value=>{value.players[1].presents[2].source='browser-renderer';});
  rejects(value=>{for(const row of value.players[0].presents)row.at*=2;});
  rejects(value=>{for(const boundary of [50,100,150,200])
    for(let index=boundary;index<300;index+=1)
      value.players[0].presents[index].at+=30;});
  rejects(value=>{for(let index=297;index<300;index+=1)
    value.players[0].presents[index].at+=80;});
  rejects(value=>{value.players[1].presents[299].frameSha256='not-a-sha';});
  rejects(value=>{for(const frame of value.players[1].presents)
    frame.frameSha256=value.players[0].presents[
      frame.tic-value.players[0].presents[0].tic]?.frameSha256;});
  rejects(value=>{value.players[0].resources=[];});
  rejects(value=>{value.artifact.coordinatorSha256='unbound';});
  process.stdout.write(
    'PMLE_OCI_TWO_POV_EVALUATOR_SELFTEST|PASS|mutations=10\n');
} else {
  assert.equal(process.argv.length,6,
    'usage: evaluate-live-frame-two-pov.mjs <evidence.json> '
      +'<authority-sha> <renderer-sha> <coordinator-sha>|--self-test');
  const evidence=JSON.parse(fs.readFileSync(process.argv[2],'utf8'));
  const summaries=evaluateTwoPovEvidence(evidence,{
    authoritySha256:process.argv[3],
    rendererSha256:process.argv[4],
    coordinatorSha256:process.argv[5]
  });
  process.stdout.write(
    'PMLE_OCI_TWO_POV_EVALUATOR|PASS|'
      +summaries.map(summary=>
        `p${summary.slot}_fps=${summary.fps.toFixed(3)}`
          +`|p${summary.slot}_p95_ms=${summary.p95.toFixed(3)}`
          +`|p${summary.slot}_p99_ms=${summary.p99.toFixed(3)}`
          +`|p${summary.slot}_max_ms=${summary.maximum.toFixed(3)}`
          +`|p${summary.slot}_confirmed_drops=${summary.confirmedDropCount}`
          +`|p${summary.slot}_buffer_min=${summary.occupancyMin}`
          +`|p${summary.slot}_buffer_p50=${summary.occupancyP50}`
          +`|p${summary.slot}_buffer_p95=${summary.occupancyP95}`
          +`|p${summary.slot}_polls=${summary.pollCount}`
          +`|p${summary.slot}_poll_ttfb_p95_ms=${
            summary.pollTtfbP95.toFixed(3)}`
          +`|p${summary.slot}_poll_download_p95_ms=${
            summary.pollDownloadP95.toFixed(3)}`)
        .join('|')+'\n');
}
