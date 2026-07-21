import assert from 'node:assert/strict';
import {execFileSync} from 'node:child_process';
import fs from 'node:fs';
import {chromium} from 'playwright';

const base=process.env.DOOMDB_PLAY_BASE_URL??'http://localhost:8080';
const seconds=Number(process.env.DOOMDB_MULTIPLAYER_SOAK_SECONDS??1800);
assert.ok(Number.isInteger(seconds)&&seconds>=20&&seconds<=1800);
const matchFile=process.env.DOOMDB_MATCH_ID_FILE;
assert.ok(matchFile,'DOOMDB_MATCH_ID_FILE is required');
const dbContainer=execFileSync('docker',['compose','ps','-q','db'],{encoding:'utf8'}).trim();
assert.ok(dbContainer,'database container is unavailable');
const workerMemory=match=>{
  const sql=`alter session set container=freepdb1;\n`+
    `set heading off feedback off pagesize 0 linesize 32767 trimspool on\n`+
    `select 'SOAK_MEM|sessions='||(select count(*) from v$session where sid=w.worker_sid)||`+
    `'|doomSessions='||(select count(*) from v$session where username='DOOM')||`+
    `'|pga='||coalesce(max(case when n.name='session pga memory' then s.value end),0)||`+
    `'|uga='||coalesce(max(case when n.name='session uga memory' then s.value end),0)||`+
    `'|javaSession='||coalesce(max(case when n.name='java session heap live size' then s.value end),0)||`+
    `'|javaCall='||coalesce(max(case when n.name='java call heap live size' then s.value end),0)||`+
    `'|gc='||coalesce(max(case when n.name='java call heap gc count' then s.value end),0) `+
    `from doom.doom_match_worker_control w left join v$sesstat s on s.sid=w.worker_sid `+
    `left join v$statname n on n.statistic#=s.statistic# `+
    `where w.match_id='${match}' group by w.worker_sid;\n`;
  const output=execFileSync('docker',['exec','-i',dbContainer,'sqlplus','-s','/','as','sysdba'],
    {input:sql,encoding:'utf8'});
  const row=output.match(/SOAK_MEM\|sessions=(\d+)\|doomSessions=(\d+)\|pga=(\d+)\|uga=(\d+)\|javaSession=(\d+)\|javaCall=(\d+)\|gc=(\d+)/);
  assert.ok(row,'worker memory evidence missing');
  return {sessions:Number(row[1]),doomSessions:Number(row[2]),pga:Number(row[3]),
    uga:Number(row[4]),javaSession:Number(row[5]),javaCall:Number(row[6]),gc:Number(row[7])};
};
const browser=await chromium.launch({headless:true});
const contexts=await Promise.all([0,1].map(()=>browser.newContext({viewport:{width:960,height:720}})));
const [host,guest]=await Promise.all(contexts.map(context=>context.newPage()));
await Promise.all([host,guest].map(page=>page.addInitScript(()=>{
  window.__doomSoakTics=[];
  window.__doomSoakResyncs=[];
  addEventListener('doom:multiplayer-present',event=>window.__doomSoakTics.push(event.detail.tic));
  addEventListener('doom:multiplayer-resync',event=>window.__doomSoakResyncs.push({
    atCount:window.__doomSoakTics.length,tic:event.detail.tic
  }));
})));
let match='';
try {
  await host.goto(`${base}/play/multiplayer`,{waitUntil:'networkidle'});
  await host.locator('[data-create] input[name=name]').fill('SOAK HOST');
  await host.getByRole('button',{name:'Create two-player match'}).click();
  await host.locator('[data-room]').waitFor({state:'visible'});
  const share=await host.locator('[data-share]').inputValue();
  match=new URL(share).hash.slice('#join='.length).split('.')[0]??'';
  assert.match(match,/^[0-9a-f]{32}$/);
  fs.writeFileSync(matchFile,`${match}\n`,{encoding:'ascii',mode:0o600});
  await guest.goto(share,{waitUntil:'networkidle'});
  await guest.locator('[data-join] input[name=name]').fill('SOAK GUEST');
  await guest.getByRole('button',{name:'Join co-op'}).click();
  await guest.locator('[data-room]').waitFor({state:'visible'});
  await guest.waitForFunction(()=>location.hash.startsWith('#resume='));
  await host.waitForFunction(()=>document.querySelector('[data-room-status]')?.textContent?.includes('2/2 joined'));
  for (const page of [host,guest]) {
    await page.waitForFunction(()=>{
      const button=document.querySelector('[data-ready]');
      return button instanceof HTMLButtonElement&&!button.disabled;
    });
  }
  await Promise.all([host,guest].map(page=>page.locator('[data-ready]').click()));
  await Promise.all([host,guest].map(page=>page.locator('[data-game][data-active]')
    .waitFor({state:'visible',timeout:60000})));
  await Promise.all([host,guest].map(page=>page.waitForFunction(()=>
    /TIC [1-9][0-9]*/.test(document.querySelector('[data-hud]')?.textContent??''),
    null,{timeout:30000})));
  await Promise.all([host,guest].map(page=>page.waitForFunction(()=>{
    const text=document.querySelector('[data-hud]')?.textContent??'';
    const lag=Number(text.match(/LAG (\d+)/)?.[1]??999);
    return window.__doomSoakTics.length>=40&&lag<=8;
  },null,{timeout:60000})));
  const ticOf=async page=>Number((await page.locator('[data-hud]').textContent()??'')
    .match(/TIC (\d+)/)?.[1]??0);
  const starts=await Promise.all([host,guest].map(ticOf));
  const startCounts=await Promise.all([host,guest].map(page=>page.evaluate(()=>
    window.__doomSoakTics.length)));
  let pressed=false;let samples=0;let maxLag=0;let memoryBaseline=null;
  const reconnectSamples=[0,0];let maxReconnectSamples=0;
  const startedAt=Date.now();
  const deadline=Date.now()+seconds*1000;
  while (Date.now()<deadline) {
    pressed=!pressed;
    await Promise.all([host,guest].map(page=>pressed?page.keyboard.down('w'):page.keyboard.up('w')));
    await host.waitForTimeout(500);
    if (samples%10===0) {
      const hudRows=await Promise.all([host,guest].map(page=>page.locator('[data-hud]')
        .evaluate(element=>({text:element.textContent??'',error:element.classList.contains('error')}))));
      for (const [slot,row] of hudRows.entries()) {
        assert.equal(row.error,false,row.text);
        if (row.text.includes('Reconnecting to Oracle')) {
          reconnectSamples[slot]+=1;maxReconnectSamples=Math.max(maxReconnectSamples,
            reconnectSamples[slot]);
          assert.ok(reconnectSamples[slot]<=6,
            `soak player ${slot} reconnect exceeded 30 seconds`);
          continue;
        }
        reconnectSamples[slot]=0;
        const lag=Number(row.text.match(/LAG (\d+)/)?.[1]??999);
        assert.ok(lag<128,`soak presentation lag exceeded retention ring: ${row.text}`);
        maxLag=Math.max(maxLag,lag);
      }
    }
    if (seconds>=120&&memoryBaseline===null&&Date.now()-startedAt>=60000)
      memoryBaseline=workerMemory(match);
    samples+=1;
  }
  await Promise.all([host,guest].map(page=>page.keyboard.up('w')));
  const ends=await Promise.all([host,guest].map(ticOf));
  const evidence=await Promise.all([host,guest].map((page,slot)=>page.evaluate(start=>({
    presented:window.__doomSoakTics.slice(start),
    resyncs:window.__doomSoakResyncs.filter(value=>value.atCount>=start)
      .map(value=>({...value,atCount:value.atCount-start}))
  }),startCounts[slot])));
  const presented=evidence.map(value=>value.presented);
  for (let slot=0;slot<2;slot++) {
    assert.ok(presented[slot].length>=seconds*25,
      `soak player ${slot} presented ${presented[slot].length} frames`);
    const gaps=[];
    for (let index=1;index<presented[slot].length;index+=1) {
      assert.ok(presented[slot][index]>presented[slot][index-1],
        `soak player ${slot} repeated or reversed tic ${presented[slot][index-1]}`);
      if (presented[slot][index]!==presented[slot][index-1]+1) gaps.push(index);
    }
    assert.ok(gaps.length<=evidence[slot].resyncs.length,
      `soak player ${slot} skipped without a recorded authoritative resync`);
    const finalStart=evidence[slot].resyncs.at(-1)?.atCount??0;
    assert.ok(presented[slot].length-finalStart>=40,
      `soak player ${slot} final post-resync run is too short`);
    for (let index=Math.max(1,finalStart+1);index<presented[slot].length;index+=1)
      assert.equal(presented[slot][index],presented[slot][index-1]+1,
        `soak player ${slot} final run skipped tic ${presented[slot][index-1]}`);
    assert.ok(ends[slot]-starts[slot]>=seconds*25,
      `soak player ${slot} advanced ${ends[slot]-starts[slot]} tics`);
  }

  const sql=`set serveroutput on size unlimited feedback off heading off linesize 32767\n`+
    `declare t number;f number;c number;cmd number;b number;w varchar2(16);`+
    `disconnected number;deadline number;left_ number;initials number;begin\n`+
    `select m.current_tic,`+
    `(select count(*) from doom_match_frame f where f.match_id=m.match_id),`+
    `(select count(*) from doom_match_checkpoint c where c.match_id=m.match_id),`+
    `(select count(*) from doom_match_command d where d.match_id=m.match_id),`+
    `(select coalesce(sum(f.response_bytes),0) from doom_match_frame f where f.match_id=m.match_id),`+
    `(select count(*) from doom_match_command d where d.match_id=m.match_id and `+
    `d.command_source='NEUTRAL_DISCONNECTED'),`+
    `(select count(*) from doom_match_command d where d.match_id=m.match_id and `+
    `d.command_source='NEUTRAL_DEADLINE'),`+
    `(select count(*) from doom_match_command d where d.match_id=m.match_id and `+
    `d.command_source='NEUTRAL_LEFT'),`+
    `(select count(*) from doom_match_command d where d.match_id=m.match_id and `+
    `d.command_source='NEUTRAL_INITIAL'),`+
    `(select worker_status from doom_match_worker_control w where w.match_id=m.match_id) `+
    `into t,f,c,cmd,b,disconnected,deadline,left_,initials,w from doom_match m where m.match_id='${match}';\n`+
    `dbms_output.put_line('SOAK_DB|tic='||t||'|frames='||f||'|checkpoints='||c||'|commands='||cmd||'|bytes='||b||'|disconnectedNeutral='||disconnected||'|deadlineNeutral='||deadline||'|leftNeutral='||left_||'|initialNeutral='||initials||'|worker='||w);end;\n/\n`;
  const output=execFileSync('scripts/db_sql.sh',['-'],{input:sql,encoding:'utf8'});
  const row=output.match(/SOAK_DB\|tic=(\d+)\|frames=(\d+)\|checkpoints=(\d+)\|commands=(\d+)\|bytes=(\d+)\|disconnectedNeutral=(\d+)\|deadlineNeutral=(\d+)\|leftNeutral=(\d+)\|initialNeutral=(\d+)\|worker=(\w+)/);
  assert.ok(row,'soak database evidence missing');
  const [,tic,frames,checkpoints,commands,bytes,disconnectedNeutral,
    deadlineNeutral,leftNeutral,initialNeutral,worker]=row;
  assert.equal(worker,'READY');assert.ok(Number(frames)<=258);
  assert.ok(Number(checkpoints)<=2);
  assert.equal(Number(deadlineNeutral),0);assert.equal(Number(leftNeutral),0);
  const totalResyncs=evidence.reduce((sum,value)=>sum+value.resyncs.length,0);
  assert.ok(Number(disconnectedNeutral)===0||totalResyncs>0||maxReconnectSamples>0,
    'disconnect neutralization lacked a recorded client recovery');
  assert.ok(Number(disconnectedNeutral)<=Math.max(1,totalResyncs)*35*30,
    `disconnect neutralization exceeded recovery bound: ${disconnectedNeutral}`);
  assert.ok(Number(commands)>=Number(tic)*2&&Number(commands)<=(Number(tic)+2)*2,
    `command frontier commands=${commands} tic=${tic}`);
  assert.ok(Number(bytes)<=258*65536);
  let memorySummary='';
  if (memoryBaseline!==null) {
    const memoryFinal=workerMemory(match);const allowance=64*1024*1024;
    assert.equal(memoryBaseline.sessions,1);assert.equal(memoryFinal.sessions,1);
    assert.ok(memoryFinal.doomSessions<=memoryBaseline.doomSessions+1,
      `DOOM sessions grew baseline=${memoryBaseline.doomSessions} final=${memoryFinal.doomSessions}`);
    assert.ok(memoryFinal.pga<=memoryBaseline.pga+allowance,
      `worker PGA grew baseline=${memoryBaseline.pga} final=${memoryFinal.pga}`);
    assert.ok(memoryFinal.uga<=memoryBaseline.uga+allowance,
      `worker UGA grew baseline=${memoryBaseline.uga} final=${memoryFinal.uga}`);
    assert.ok(memoryFinal.javaSession<=memoryBaseline.javaSession+allowance,
      `worker Java session heap grew baseline=${memoryBaseline.javaSession} final=${memoryFinal.javaSession}`);
    memorySummary=` memory=${memoryBaseline.pga}/${memoryFinal.pga}`+
      ` java=${memoryBaseline.javaSession}/${memoryFinal.javaSession}`+
      ` gc=${memoryBaseline.gc}/${memoryFinal.gc}`;
  }
  process.stdout.write(`PASS P13.5-MULTIPLAYER-SOAK seconds=${seconds} `+
    `tics=${starts.join('/')}-${ends.join('/')} maxLag=${maxLag} `+
    `maxReconnectSeconds=${maxReconnectSamples*5} `+
    `resyncs=${evidence.map(value=>value.resyncs.length).join('/')} `+
    `frames=${frames} checkpoints=${checkpoints} bytes=${bytes} `+
    `disconnectedNeutral=${disconnectedNeutral} initialNeutral=${initialNeutral}${memorySummary}\n`);
} finally {
  await browser.close();
}
