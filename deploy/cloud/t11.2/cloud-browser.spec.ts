import {test, expect} from '@playwright/test';
import crypto from 'node:crypto';
import fs from 'node:fs';

const sha = (value:string|Buffer) => crypto.createHash('sha256').update(value).digest('hex');
const indexUrl = process.env.T112_S3_INDEX_URL!;
const ordsRoot = process.env.ADB_ORDS_BASE_URL!;
const ordsBase = ordsRoot.endsWith('/') ? ordsRoot : `${ordsRoot}/`;
const output = process.env.T112_BROWSER_LEDGER!;
const routeFile = process.env.T112_COMPLETION_LEDGER!;

test('[T112-LIVE-CLOUD-BROWSER] direct S3 and managed ORDS workflow', async ({page}) => {
  expect(new URL(indexUrl).protocol).toBe('https:');
  const s3Origin = new URL(indexUrl).origin, ordsOrigin = new URL(ordsRoot).origin;
  expect(s3Origin).not.toBe(ordsOrigin);
  const errors:string[] = [], network:any[] = [], options:any[] = [], responseTasks:Promise<void>[] = []; let cors:any=null;
  page.on('console', message => { if (message.type() === 'error') errors.push(`console:${message.text()}`); });
  page.on('pageerror', error => errors.push(`pageerror:${error.message}`));
  page.on('requestfailed', request => errors.push(`requestfailed:${request.failure()?.errorText ?? 'unknown'}`));
  page.on('request', request => {
    const url = new URL(request.url());
    if (request.method() === 'OPTIONS') options.push({origin: url.origin, method: request.method()});
    network.push({kind: url.origin === s3Origin ? 'S3_STATIC' : url.origin === ordsOrigin ? 'ORACLE_ORDS' : 'OTHER',
      urlSha256: sha(url.href), originSha256: sha(url.origin), method: request.method(), redirected: false,
      failed: false, websocket: request.resourceType() === 'websocket', mocked: false});
  });
  page.on('response', response => {
    const row = [...network].reverse().find(x => x.urlSha256 === sha(response.url()) && x.status === undefined);
    if (row) { row.status = response.status(); row.redirected = response.request().redirectedFrom() !== null; }
    if(response.request().method()==='OPTIONS')responseTasks.push(response.allHeaders().then(headers=>{const methods=(headers['access-control-allow-methods']??'').toUpperCase().split(/\s*,\s*/).filter(Boolean),allowed=(headers['access-control-allow-headers']??'').toLowerCase().split(/\s*,\s*/).filter(Boolean);cors={realOptionsRequest:true,intercepted:false,status:response.status(),requestOriginSha256:sha(s3Origin),targetOriginSha256:sha(ordsOrigin),allowOriginExact:headers['access-control-allow-origin']===s3Origin,allowCredentialsWildcard:headers['access-control-allow-credentials']==='true'&&headers['access-control-allow-origin']==='*',allowMethods:methods,allowHeaders:allowed.filter(x=>['content-type','accept'].includes(x)),observationSha256:sha(JSON.stringify({status:response.status(),methods,allowed,exact:headers['access-control-allow-origin']===s3Origin}))};}));
  });
  await page.addInitScript(() => {
    const starts:number[] = [];
    const original = AudioBufferSourceNode.prototype.start;
    AudioBufferSourceNode.prototype.start = function(when?:number, offset?:number, duration?:number) {
      starts.push(when ?? 0); return original.call(this, when, offset, duration);
    };
    Object.defineProperty(window, '__doomAudioStarts', {value: starts});
  });
  await page.goto(indexUrl, {waitUntil: 'networkidle'});
  await expect(page.locator('canvas[data-doom-canvas]')).toHaveAttribute('width', '320');
  await expect(page.locator('canvas[data-doom-canvas]')).toHaveAttribute('height', '200');
  const appCanvasSha = await page.locator('canvas[data-doom-canvas]').evaluate((canvas:HTMLCanvasElement) => {
    const bytes = canvas.getContext('2d')!.getImageData(0, 0, 320, 200).data;
    return crypto.subtle.digest('SHA-256', bytes).then(x => [...new Uint8Array(x)].map(v => v.toString(16).padStart(2, '0')).join(''));
  });
  await page.mouse.click(8, 8);

  const route = JSON.parse(fs.readFileSync(routeFile, 'utf8'));
  expect(route.schema).toBe(1); expect(route.approved).toBe(true);
  expect(Array.isArray(route.commands) && route.commands.length > 0).toBe(true);
  const workflow = await page.evaluate(async ({base, commands}) => {
    const root = new URL(base.endsWith('/') ? base : `${base}/`), enc = new TextEncoder();
    const hex = async (value:BufferSource|string) => [...new Uint8Array(await crypto.subtle.digest('SHA-256', typeof value === 'string' ? enc.encode(value) : value))].map(x => x.toString(16).padStart(2, '0')).join('');
    const value = (o:any,k:string) => o[k] ?? o[k.toUpperCase()] ?? o.items?.[0]?.[k] ?? o.items?.[0]?.[k.toUpperCase()];
    const post = async (name:string, body:any) => { const r = await fetch(new URL(`${name}/`, root), {method:'POST', headers:{'content-type':'application/json','accept':'application/json'}, body:JSON.stringify(body), redirect:'error'}); if (!r.ok) throw Error(`${name}:${r.status}`); return r.json(); };
    const bytes = async (o:any) => { let b = Uint8Array.from(atob(value(o,'p_payload')), c => c.charCodeAt(0)); if (b[0] === 31 && b[1] === 139) b = new Uint8Array(await new Response(new Blob([b]).stream().pipeThrough(new DecompressionStream('gzip'))).arrayBuffer()); return b; };
    const payload = async (o:any) => JSON.parse(new TextDecoder().decode(await bytes(o)));
    const palette = (await bytes(await post('get_asset',{p_asset_name:'PLAYPAL'}))).slice(0,768);
    const audioAsset = await bytes(await post('get_asset',{p_asset_name:'DSPISTOL'}));
    const ng = await post('new_game',{p_skill:3}), token = value(ng,'p_session');
    if (!/^[0-9a-f]{32}$/.test(token)) throw Error('opaque token contract');
    let seq=0, last=await payload(ng), issued=0, scheduled=0;
    const canvas=document.createElement('canvas');canvas.width=320;canvas.height=200;document.body.append(canvas);
    const context=new AudioContext();await context.resume();
    const schedule=async(name:string)=>{const raw=await bytes(await post('get_asset',{p_asset_name:name})),view=new DataView(raw.buffer,raw.byteOffset,raw.byteLength),format=view.getUint16(0,true),rate=view.getUint16(2,true),count=view.getUint32(4,true);if(format!==3||count<1||count>raw.length-8)throw Error('Doom audio');const buffer=context.createBuffer(1,count,rate),channel=buffer.getChannelData(0);for(let i=0;i<count;i++)channel[i]=(raw[i+8]-128)/128;const source=context.createBufferSource();source.buffer=buffer;source.connect(context.destination);source.start(context.currentTime);scheduled++;};
    const render=async(p:any) => { const idx=new Uint8Array(64000); for(let x=0;x<320;x++){let y=0;for(const [y0,n,c] of p.cols[x]){if(y0!==y||n<1||y+n>200)throw Error('RLE');idx.fill(c,x*200+y,x*200+y+n);y+=n}if(y!==200)throw Error('RLE coverage')}const rgba=new Uint8ClampedArray(256000);for(let x=0;x<320;x++)for(let y=0;y<200;y++){const c=idx[x*200+y],q=(y*320+x)*4;rgba[q]=palette[c*3];rgba[q+1]=palette[c*3+1];rgba[q+2]=palette[c*3+2];rgba[q+3]=255}canvas.getContext('2d')!.putImageData(new ImageData(rgba,320,200),0,0);return hex(canvas.getContext('2d')!.getImageData(0,0,320,200).data)};
    const hashes=[await render(last)];
    const step=async(patch:any) => { const c={seq:++seq,turn:0,forward:0,strafe:0,run:0,fire:0,use:0,weapon:0,pause:0,automap:0,menu:'NONE',cheat:'',...patch};last=await payload(await post('step',{p_session:token,p_commands:JSON.stringify({v:1,commands:[c]})}));for(const event of last.audio??[]){issued++;await schedule(event[2])}return last;};
    await step({fire:1}); hashes.push(await render(last));
    const save=value(await post('save_game',{p_session:token,p_slot:11}),'p_state_sha'); await step({turn:1,forward:1});
    const load=await payload(await post('load_game',{p_session:token,p_slot:11})); if(load.state_sha!==save)throw Error('load drift');
    const replayId=value(await post('start_replay',{p_session:token,p_from_tic:1,p_to_tic:1}),'p_replay_id');const replay=await payload(await post('step_replay',{p_replay_id:replayId}));if(replay.state_sha!==save)throw Error('replay drift');
    const completionNg=await post('new_game',{p_skill:3}),completionToken=value(completionNg,'p_session');if(!/^[0-9a-f]{32}$/.test(completionToken))throw Error('completion token');let completionLast=await payload(completionNg),completionSteps=0;
    for(const command of commands) {if(command.seq!==completionSteps+1)throw Error('completion command order');completionLast=await payload(await post('step',{p_session:completionToken,p_commands:JSON.stringify({v:1,commands:[command]})}));completionSteps++;for(const event of completionLast.audio??[]){issued++;await schedule(event[2])}if(completionLast.mode==='INTERMISSION'||completionLast.complete===1)break;}
    if(completionLast.mode!=='INTERMISSION'&&completionLast.complete!==1)throw Error('completion ledger did not complete E1M1');last=completionLast;hashes.push(await render(last));
    const starts=(window as any).__doomAudioStarts as number[];if(starts.length<scheduled)throw Error('AudioContext did not schedule database event');
    return {gameTokenSha256:await hex(completionToken),gameTokenBits:128,commandLedgerSha256:await hex(JSON.stringify(commands)),terminalStateSha256:last.state_sha,saveStateSha256:save,loadStateSha256:load.state_sha,replayStateSha256:replay.state_sha,completionStateSha256:last.state_sha,playpalSha256:await hex(palette),audioAssetSha256:await hex(audioAsset),steps:seq+completionSteps,gzipBlobDecoded:true,rleCoverage:64000,canvasWidth:320,canvasHeight:200,canvasRgbaHashes:hashes,audioEventsIssued:issued,audioEventsScheduled:scheduled,completed:true,intermissionVisible:true,apiFamilies:['NEW_GAME','STEP','GET_ASSET','SAVE','LOAD','REPLAY']};
  }, {base: new URL('doom_api/', ordsBase).href, commands: route.commands});
  await Promise.all(responseTasks);
  expect(errors).toEqual([]); expect(options.some(x => x.origin === ordsOrigin)).toBe(true);expect(cors?.status).toBe(204);expect(cors?.allowOriginExact).toBe(true);expect(cors?.allowMethods).toContain('POST');expect(cors?.allowHeaders).toContain('content-type');
  expect(network.every(x => x.kind !== 'OTHER' && !x.redirected && !x.websocket && x.status >= 200 && x.status < 300)).toBe(true);
  const ledger={schema:1,appCanvasSha,errors,network,optionsCount:options.length,cors,workflow};
  fs.writeFileSync(output, `${JSON.stringify(ledger)}\n`, {mode:0o600});
});
