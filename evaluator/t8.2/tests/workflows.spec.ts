import {test, expect} from '@playwright/test';
import {installStrictPageGuards} from '../../playwright/strict-page.mjs';

const base = process.env.DOOM_T82_BASE_URL;
if (!base) throw Error('DOOM_T82_BASE_URL is required; browser workflows never skip');
const origin = new URL(base).origin;

async function boot(page: any, viewport: {width: number; height: number}) {
  await page.setViewportSize(viewport);
  const strict = installStrictPageGuards(page), bad: string[] = [], requests: string[] = [];
  page.on('response', (response: any) => {
    if (response.status() >= 400) bad.push(`${response.status()} ${response.url()}`);
  });
  page.on('request', (request: any) =>
    requests.push(`${request.method()} ${new URL(request.url()).pathname}`));
  await page.goto(new URL('/health.txt', origin).href);
  await page.evaluate(({base}) => {
    document.body.innerHTML = '<canvas id="doom" width="320" height="200"></canvas>';
    const w: any = window;
    w.__seq = 0;
    w.__value = (document: any, key: string) => document[key] ?? document[key.toUpperCase()]
      ?? document.items?.[0]?.[key] ?? document.items?.[0]?.[key.toUpperCase()];
    w.__post = async (name: string, body: any) => {
      const stem = name.replace(/^\//, '').replace(/\/$/, '');
      let response: Response | undefined;
      for (const path of [stem.toUpperCase(), `${stem.toLowerCase()}/`]) {
        response = await fetch(new URL(path, base), {
          method: 'POST', headers: {'content-type': 'application/json'},
          body: JSON.stringify(body), redirect: 'error'
        });
        if (response.status !== 404) break;
      }
      if (!response?.ok) throw Error(`${response?.status} ${await response?.text()}`);
      return response.json();
    };
    w.__bytes = (document: any, key = 'p_payload') =>
      Uint8Array.from(atob(w.__value(document, key)), (value: string) => value.charCodeAt(0));
    w.__loadPalette = async () => {
      if (w.__palette) return;
      const bytes = w.__bytes(await w.__post('get_asset', {p_asset_name: 'PLAYPAL'}));
      if (bytes.length < 768) throw Error('PLAYPAL too short');
      w.__palette = bytes.slice(0, 768);
    };
    w.__decode = async (document: any) => {
      let bytes = w.__bytes(document);
      if (bytes[0] === 31 && bytes[1] === 139) {
        const stream = new Blob([bytes]).stream().pipeThrough(new DecompressionStream('gzip'));
        const legacy = JSON.parse(new TextDecoder().decode(
          new Uint8Array(await new Response(stream).arrayBuffer())));
        const indices = new Uint8Array(64000);
        for (let x = 0; x < 320; x += 1) for (const [y, length, color] of legacy.cols[x])
          indices.fill(color, x * 200 + y, x * 200 + y + length);
        return {...legacy, indices};
      }
      if (new TextDecoder().decode(bytes.slice(0, 4)) !== 'DMF3') throw Error('DMF3 magic');
      const view = new DataView(bytes.buffer, bytes.byteOffset, bytes.byteLength);
      const audioLength = view.getUint16(138);
      const offset = 140 + audioLength;
      if (bytes.length - offset !== 64000) throw Error('DMF3 frame length');
      const text = (start: number, end: number) =>
        new TextDecoder().decode(bytes.slice(start, end));
      return {v: 3, tic: view.getInt32(4), w: 320, h: 200,
        mode: bytes[8] === 1 ? 'DEAD' : bytes[9] === 1 ? 'INTERMISSION' : 'GAME',
        state_sha: text(10, 74), frame_sha: text(74, 138),
        audio: JSON.parse(text(140, offset)), complete: bytes[9], indices: bytes.slice(offset)};
    };
    w.__paint = (frame: any) => {
      if (!w.__palette || !/^[0-9a-f]{64}$/.test(frame.state_sha)
          || !/^[0-9a-f]{64}$/.test(frame.frame_sha)) throw Error('frame contract');
      const rgba = new Uint8ClampedArray(256000);
      for (let x = 0; x < 320; x += 1) for (let y = 0; y < 200; y += 1) {
        const color = frame.indices[x * 200 + y], pixel = (y * 320 + x) * 4;
        rgba[pixel] = w.__palette[color * 3];
        rgba[pixel + 1] = w.__palette[color * 3 + 1];
        rgba[pixel + 2] = w.__palette[color * 3 + 2];
        rgba[pixel + 3] = 255;
      }
      (document.querySelector('#doom') as HTMLCanvasElement).getContext('2d')!
        .putImageData(new ImageData(rgba, 320, 200), 0, 0);
      return {p: frame, rgba: Array.from(rgba)};
    };
    w.__new = async (skill = 3) => {
      await w.__loadPalette();
      const result = await w.__post('new_game', {p_skill: skill});
      w.__session = w.__value(result, 'p_session');
      return w.__paint(await w.__decode(result));
    };
    w.__step = async (patch: any = {}) => {
      const command = {seq: ++w.__seq, turn: 0, forward: 0, strafe: 0, run: 0,
        fire: 0, use: 0, weapon: 0, pause: 0, automap: 0, menu: 'NONE', cheat: '',
        ...patch};
      return w.__paint(await w.__decode(await w.__post('step', {
        p_session: w.__session, p_commands: JSON.stringify({v: 1, commands: [command]})
      })));
    };
  }, {base});
  return {strict, requests, finish() {
    strict();
    expect(bad).toEqual([]);
    expect(requests.filter(value => value.startsWith('POST ')).every(value =>
      /\/doom_api\/(?:new_game|step|save_game|load_game|get_asset)\/?$/i.test(value))).toBe(true);
  }};
}

async function canvasHash(page: any) {
  return page.evaluate(async () => {
    const context = (document.querySelector('#doom') as HTMLCanvasElement).getContext('2d')!;
    const bytes = context.getImageData(0, 0, 320, 200).data;
    const digest = await crypto.subtle.digest('SHA-256', bytes);
    return [...new Uint8Array(digest)].map(value => value.toString(16).padStart(2, '0')).join('');
  });
}

test('[T82-PLAYWRIGHT-DESKTOP] public control and persistence canvas workflow',
  async ({page}, info) => {
    info.annotations.push({type: 'doom-assertions', description: '92'});
    const gate = await boot(page, {width: 1280, height: 720});
    const spawn = await page.evaluate(() => (window as any).__new(3));
    expect(spawn.p.mode).toBe('GAME');
    expect(spawn.rgba).toHaveLength(256000);
    const spawnHash = await canvasHash(page);
    const paused = await page.evaluate(() => (window as any).__step({pause: 1}));
    expect(await canvasHash(page)).not.toBe(spawnHash);
    const held = await page.evaluate(() => (window as any).__step(
      {forward: 1, strafe: 1, run: 1, fire: 1, use: 1}));
    expect(held.p.tic).toBe(paused.p.tic + 1);
    await page.evaluate(() => (window as any).__step({pause: 1}));
    const normalMap = await page.evaluate(() => (window as any).__step({automap: 1}));
    const normalMapHash = await canvasHash(page);
    await page.evaluate(() => (window as any).__step({cheat: 'FULLMAP'}));
    expect(await canvasHash(page)).not.toBe(normalMapHash);
    const normalAgain = await page.evaluate(() => (window as any).__step({cheat: 'FULLMAP'}));
    expect(normalAgain.p.state_sha).not.toBe(normalMap.p.state_sha);
    for (const cheat of ['GOD', 'GOD', 'ALL', 'NOCLIP', 'NOCLIP'])
      await page.evaluate(cheat => (window as any).__step({cheat}), cheat);
    const saved = await page.evaluate(async () => {
      const w: any = window;
      return w.__post('save_game', {p_session: w.__session, p_slot: 3});
    });
    const savedSha = await page.evaluate((result: any) =>
      (window as any).__value(result, 'p_state_sha'), saved);
    expect(savedSha).toMatch(/^[0-9a-f]{64}$/);
    const commands = [{turn: 1}, {forward: 1, run: 1}, {fire: 1},
      {turn: -1, strafe: 1, use: 1}];
    const branch = [];
    for (const command of commands)
      branch.push(await page.evaluate(command => (window as any).__step(command), command));
    const loaded = await page.evaluate(async () => {
      const w: any = window;
      return w.__paint(await w.__decode(await w.__post('load_game',
        {p_session: w.__session, p_slot: 3})));
    });
    expect(loaded.p.state_sha).toBe(savedSha);
    const branch2 = [];
    for (const command of commands)
      branch2.push(await page.evaluate(command => (window as any).__step(command), command));
    expect(branch2.map((frame: any) => [frame.p.state_sha, frame.p.frame_sha, frame.p.audio]))
      .toEqual(branch.map((frame: any) => [frame.p.state_sha, frame.p.frame_sha, frame.p.audio]));
    gate.finish();
  });

test('[T82-PLAYWRIGHT-MOBILE] responsive raw-DMF3 control canvas', async ({page}, info) => {
  info.annotations.push({type: 'doom-assertions', description: '72'});
  const gate = await boot(page, {width: 390, height: 844});
  const spawn = await page.evaluate(() => (window as any).__new(2));
  expect(spawn.rgba).toHaveLength(256000);
  const menu = await page.evaluate(() => (window as any).__step({menu: 'OPTIONS'}));
  expect(menu.p.frame_sha).toMatch(/^[0-9a-f]{64}$/);
  const closed = await page.evaluate(() => (window as any).__step({menu: 'OPTIONS'}));
  expect(closed.p.state_sha).not.toBe(menu.p.state_sha);
  const automap = await page.evaluate(() => (window as any).__step({automap: 1}));
  expect(automap.p.frame_sha).not.toBe(closed.p.frame_sha);
  expect(await page.locator('canvas').evaluate((canvas: any) => [canvas.width, canvas.height]))
    .toEqual([320, 200]);
  gate.finish();
});
