import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {execFileSync} from 'node:child_process';
import fs from 'node:fs';
import {chromium} from 'playwright';

const base=process.env.DOOMDB_PLAY_BASE_URL??'http://localhost:8080';
const matchFile=process.env.DOOMDB_MATCH_ID_FILE;
assert.ok(matchFile,'DOOMDB_MATCH_ID_FILE is required');
const canonical=JSON.parse(fs.readFileSync('artifacts/p13.3-coop-e1m1-route.json','utf8'));
const routeBytes=fs.readFileSync(canonical.baseRoute.path);
assert.equal(createHash('sha256').update(routeBytes).digest('hex'),canonical.baseRoute.sha256);
const route=JSON.parse(routeBytes);
const byte=value=>((value%256)+256)%256;
let turnHeld=0;
const ticcmd=command=>{
  const forward=Math.abs(command.forward)>1?command.forward:command.forward*(command.run?50:25);
  const side=Math.abs(command.strafe)>1?command.strafe:command.strafe*(command.run?40:24);
  const mouseTurn=Math.abs(command.turn)>1;
  if (command.turn===0||mouseTurn) turnHeld=0;else turnHeld+=1;
  const turnMagnitude=mouseTurn?Math.abs(command.turn)*256:
    turnHeld<6?320:(command.run?1280:640);
  const turn=command.turn===0?0:-Math.sign(command.turn)*turnMagnitude;
  const buttons=(command.fire?1:0)|(command.use?2:0)|
    (command.weapon>0?4|((command.weapon-1)<<3):0);
  return [byte(forward),byte(side),(turn>>8)&255,turn&255,0,0,0,buttons]
    .map(value=>value.toString(16).padStart(2,'0')).join('').toUpperCase();
};
const player0=route.runs.flatMap(run=>Array.from({length:run.repeat},()=>ticcmd(run.command)))
  .slice(0,canonical.commandCount);
for (const transform of canonical.player0Transforms) {
  const offset=transform.axis==='forward'?0:2;
  for (let tic=transform.firstTic;tic<=transform.lastTic;tic+=1) {
    const vector=player0[tic-1];const adjusted=byte(parseInt(vector.slice(offset,offset+2),16)+transform.delta);
    player0[tic-1]=vector.slice(0,offset)+adjusted.toString(16).padStart(2,'0').toUpperCase()+
      vector.slice(offset+2);
  }
}
const player1=Array.from({length:canonical.commandCount},()=> '0000000000000000');
for (const run of canonical.player1Runs)
  for (let tic=run.firstTic;tic<=run.lastTic;tic+=1) player1[tic-1]=run.ticcmdHex;

const browser=await chromium.launch({headless:true});
const contexts=await Promise.all([player0,player1].map(async vectors=>{
  const context=await browser.newContext({viewport:{width:1000,height:760}});
  await context.addInitScript(commands=>{
    window.__doomRouteTrace=[];
    addEventListener('doom:multiplayer-present',event=>window.__doomRouteTrace.push(event.detail));
    const nativeFetch=window.fetch.bind(window);
    window.fetch=(input,init)=>{
      const url=typeof input==='string'?input:input instanceof URL?input.href:input.url;
      if (/\/SUBMIT_MATCH_BATCH$/i.test(new URL(url,location.href).pathname)&&init?.body) {
        const body=JSON.parse(String(init.body));const first=Number(body.p_first_tic);
        body.p_ticcmd_hex=Array.from({length:4},(_,offset)=>
          commands[first+offset-1]??'0000000000000000').join('');
        init={...init,body:JSON.stringify(body)};
      }
      return nativeFetch(input,init);
    };
  },vectors);
  return context;
}));
const [host,guest]=await Promise.all(contexts.map(context=>context.newPage()));
let match='';
try {
  await host.goto(`${base}/play/multiplayer`,{waitUntil:'networkidle'});
  await host.locator('[data-create] input[name=name]').fill('ROUTE HOST');
  await host.locator('[data-create] select[name=skill]').selectOption(String(canonical.skill));
  await host.getByRole('button',{name:'Create two-player match'}).click();
  await host.locator('[data-room]').waitFor({state:'visible'});
  const share=await host.locator('[data-share]').inputValue();
  match=new URL(share).hash.slice('#join='.length).split('.')[0]??'';
  assert.match(match,/^[0-9a-f]{32}$/);
  fs.writeFileSync(matchFile,`${match}\n`,{encoding:'ascii',mode:0o600});
  await guest.goto(share,{waitUntil:'networkidle'});
  await guest.locator('[data-join] input[name=name]').fill('ROUTE GUEST');
  await guest.getByRole('button',{name:'Join co-op'}).click();
  await guest.locator('[data-room]').waitFor({state:'visible'});
  await host.waitForFunction(()=>document.querySelector('[data-room-status]')?.textContent?.includes('2/2 joined'));
  await Promise.all([host,guest].map(page=>page.waitForFunction(()=>{
    const button=document.querySelector('[data-ready]');
    return button instanceof HTMLButtonElement&&!button.disabled;
  })));
  await Promise.all([host,guest].map(page=>page.locator('[data-ready]').click()));
  await Promise.all([host,guest].map(page=>page.waitForFunction(target=>
    window.__doomRouteTrace.some(row=>row.tic===target),canonical.commandCount,{timeout:180000})));
  const traces=await Promise.all([host,guest].map(page=>page.evaluate(()=>window.__doomRouteTrace)));
  for (let slot=0;slot<2;slot+=1) {
    const throughTerminal=traces[slot].filter(row=>row.tic<=canonical.commandCount);
    assert.equal(throughTerminal[0].tic,1);
    assert.equal(throughTerminal.at(-1).tic,canonical.commandCount);
    for (let index=1;index<throughTerminal.length;index+=1)
      assert.equal(throughTerminal[index].tic,throughTerminal[index-1].tic+1,
        `browser ${slot} skipped tic ${throughTerminal[index-1].tic}`);
    assert.equal(throughTerminal.at(-1).frameSha,
      slot===0?canonical.accepted.player0FrameSha256:canonical.accepted.player1FrameSha256);
  }
  const sql=`set serveroutput on size unlimited feedback off heading off linesize 32767\n`+
    `declare tic_ number;state_ varchar2(64);f0 varchar2(64);f1 varchar2(64);membership_ varchar2(2);begin `+
    `select t.tic,t.state_sha,rawtohex(t.membership_bitmap) into tic_,state_,membership_ from doom_match_tic t `+
    `where t.match_id='${match}' and t.tic=${canonical.commandCount};`+
    `select max(case player_slot when 0 then frame_sha end),max(case player_slot when 1 then frame_sha end) `+
    `into f0,f1 from doom_match_frame where match_id='${match}' and tic=${canonical.commandCount};`+
    `dbms_output.put_line('ROUTE_DB|tic='||tic_||'|state='||state_||'|f0='||f0||'|f1='||f1||'|membership='||membership_);end;\n/\n`;
  const output=execFileSync('scripts/db_sql.sh',['-'],{input:sql,encoding:'utf8'});
  const row=output.match(/ROUTE_DB\|tic=(\d+)\|state=([0-9a-f]+)\|f0=([0-9a-f]+)\|f1=([0-9a-f]+)\|membership=([0-9A-F]+)/i);
  assert.ok(row,'browser-route database evidence missing');
  assert.deepEqual(row.slice(1),[String(canonical.commandCount),canonical.accepted.stateSha256,
    canonical.accepted.player0FrameSha256,canonical.accepted.player1FrameSha256,
    canonical.accepted.membershipHex]);
  process.stdout.write(`PASS P13.3-COOP-BROWSER-ROUTE tic=${canonical.commandCount} `+
    `frames=${traces.map(rows=>rows.filter(row=>row.tic<=canonical.commandCount).length).join('/')} `+
    `stateSha=${canonical.accepted.stateSha256}\n`);
} finally {
  await browser.close();
}
