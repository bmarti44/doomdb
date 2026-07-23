import {chromium} from 'playwright';

const base=process.env.DOOMDB_PLAY_BASE_URL??'http://localhost:8080';
const tics=Number(process.env.DOOMDB_BROWSER_PROFILE_TICS??5000);
if(!Number.isInteger(tics)||tics<100||tics>20000) throw new Error('invalid tic count');

const browser=await chromium.launch({headless:true});
try {
  const page=await browser.newPage({viewport:{width:960,height:720}});
  await page.goto(new URL('/play/multiplayer.html',base).toString(),
    {waitUntil:'networkidle'});
  const result=await page.evaluate(async count=>{
    const {createBrowserAuthorityEngines}=
      await import('/play/teavm-browser.js');
    const engines=await createBrowserAuthorityEngines({
      state:'ACTIVE',mode:'COOP',skill:3,episode:1,map:1,maxPlayers:2,
      memberCount:2,readyCount:2,requesterSlot:0,membershipEpoch:1,
      generation:1,currentTic:0,workerMode:'PACED_INPUT'
    });
    const commands=new Uint8Array(32);
    const windows=[];
    let verifyMs=0,presentStepMs=0,renderMs=0;
    for(let tic=1;tic<=count;tic+=1){
      commands[1]=(tic%35)<18?25:0;
      let started=performance.now();
      engines.verifier.stepMultiplayerAuthoritative(2,3,commands);
      verifyMs+=performance.now()-started;
      started=performance.now();
      engines.presenter.stepMultiplayerAuthoritative(2,3,commands);
      presentStepMs+=performance.now()-started;
      started=performance.now();
      engines.presenter.renderPlayerFrame(0);
      renderMs+=performance.now()-started;
      if(tic%500===0){
        windows.push({tic,verifyMs,presentStepMs,renderMs});
        verifyMs=0;presentStepMs=0;renderMs=0;
        await new Promise(resolve=>setTimeout(resolve,0));
      }
    }
    return windows;
  },tics);
  for(const window of result){
    process.stdout.write(`PMLE_BROWSER_REPLICA_PROFILE|tic=${window.tic}`+
      `|verify_ms_per_tic=${(window.verifyMs/500).toFixed(4)}`+
      `|present_step_ms_per_tic=${(window.presentStepMs/500).toFixed(4)}`+
      `|render_ms_per_tic=${(window.renderMs/500).toFixed(4)}`+
      `|total_ms_per_tic=${((window.verifyMs+window.presentStepMs+
        window.renderMs)/500).toFixed(4)}\n`);
  }
} finally {
  await browser.close();
}
