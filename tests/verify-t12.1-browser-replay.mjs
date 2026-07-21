#!/usr/bin/env node
import assert from 'node:assert/strict';
import crypto from 'node:crypto';
import fs from 'node:fs';
import path from 'node:path';
import {chromium} from '@playwright/test';

const root = path.resolve(import.meta.dirname, '..');
const replayPath = path.join(root, 'artifacts/performance/t12.1/mocha-replay-300.json');
const replay = JSON.parse(fs.readFileSync(replayPath, 'utf8'));
assert.equal(replay.schema, 2); assert.equal(replay.frames.length, 300);
const base = process.env.DOOM_PLAY_ORIGIN ?? 'http://localhost:8080';
const browser = await chromium.launch({headless: true});

const percentile = (values, fraction) => values.slice().sort((a, b) => a - b)[
  Math.ceil(values.length * fraction) - 1];
const sha = value => crypto.createHash('sha256').update(value).digest('hex');

async function capture(run) {
  const page = await browser.newPage({viewport: {width: 1280, height: 800}});
  await page.goto(`${base}/health.txt`, {waitUntil: 'domcontentloaded'});
  try {
    return await page.evaluate(async ({frames, run}) => {
      const [api, codec, canvasModule, paletteModule] = await Promise.all([
        import('/play/api.js'), import('/play/codec.js'),
        import('/play/canvas.js'), import('/play/palette.js')
      ]);
      const paletteAsset = await api.getAsset('PLAYPAL');
      const palette = paletteModule.createPalette(codec.decodeBytes(paletteAsset.payload));
      const canvas = canvasModule.createDoomCanvas();
      document.body.replaceChildren(canvas);
      const digest = async encoded => {
        const binary = atob(encoded), bytes = new Uint8Array(binary.length);
        for (let index = 0; index < binary.length; index += 1)
          bytes[index] = binary.charCodeAt(index);
        const hash = new Uint8Array(await crypto.subtle.digest('SHA-256', bytes));
        return Array.from(hash, value => value.toString(16).padStart(2, '0')).join('');
      };
      const game = await api.newGame(frames[0].request.p_skill);
      const initial = await codec.decodePayload(game.payload);
      const chain = [{frame: 0, tic: initial.tic, stateSha: initial.stateSha,
        frameSha: initial.frameSha, payloadSha: await digest(game.payload)}];
      const tasks = new Map();
      const launch = sequence => {
        const command = {...frames[sequence].request, seq: sequence};
        tasks.set(sequence, (async () => {
          await api.submitStep(game.session, command);
          let payload;
          do { payload = await api.pollFrame(game.session, sequence, 1000); }
          while (payload === null);
          const decoded = await codec.decodePayload(payload);
          return {decoded, payload, payloadSha: await digest(payload)};
        })());
      };
      launch(1); launch(2);
      const paints = [];
      let target = performance.now();
      for (let sequence = 1; sequence < frames.length; sequence += 1) {
        const result = await tasks.get(sequence);
        tasks.delete(sequence);
        if (sequence + 2 < frames.length) launch(sequence + 2);
        target += 31.8;
        const wait = target - performance.now();
        if (wait > 0) await new Promise(resolve => setTimeout(resolve, wait));
        canvasModule.blit(canvas,
          paletteModule.applyPalette(result.decoded.indices, palette));
        paints.push(performance.now());
        chain.push({frame: sequence, tic: result.decoded.tic,
          stateSha: result.decoded.stateSha, frameSha: result.decoded.frameSha,
          payloadSha: result.payloadSha});
      }
      return {run, chain, paints};
    }, {frames: replay.frames, run});
  } finally { await page.close(); }
}

try {
  const first = await capture(1), second = await capture(2);
  for (const result of [first, second]) {
    assert.equal(result.chain.length, 300);
    assert.deepEqual(result.chain.map(row => row.frame),
      Array.from({length: 300}, (_, index) => index));
    assert.deepEqual(result.chain.map(row => row.tic),
      Array.from({length: 300}, (_, index) => index));
    assert.equal(new Set(result.chain.slice(1).map(row => row.frameSha)).size, 299,
      `run ${result.run} repeated a gameplay frame`);
  }
  assert.deepEqual(second.chain, first.chain,
    'independent browser runs produced different state/frame/payload chains');
  const summaries = [first, second].map(result => {
    const gaps = result.paints.slice(1).map((at, index) => at - result.paints[index]);
    const fps = (result.paints.length - 1) * 1000 /
      (result.paints.at(-1) - result.paints[0]);
    assert.ok(fps >= 30, `run ${result.run} displayed ${fps.toFixed(2)} FPS`);
    return {run: result.run, frames: result.chain.length, fps,
      gapP50Ms: percentile(gaps, .5), gapP95Ms: percentile(gaps, .95),
      stateChainSha256: sha(JSON.stringify(result.chain.map(row => row.stateSha))),
      frameChainSha256: sha(JSON.stringify(result.chain.map(row => row.frameSha))),
      payloadChainSha256: sha(JSON.stringify(result.chain.map(row => row.payloadSha))),
      terminalStateSha: result.chain.at(-1).stateSha,
      terminalFrameSha: result.chain.at(-1).frameSha,
      terminalPayloadSha: result.chain.at(-1).payloadSha};
  });
  const output = {schema: 1, task: 'T12.1-BROWSER-TWO-RUN', replaySha256:
    '1ad47bc8e2a5b7518d68b937a333492d66d7d539f827980086d4b4fdad327fe3',
    identicalChains: true, summaries};
  const artifact = path.join(root, '.artifacts/t12.1/browser-two-run.json');
  fs.mkdirSync(path.dirname(artifact), {recursive: true});
  fs.writeFileSync(artifact, `${JSON.stringify(output)}\n`, {mode: 0o600});
  process.stdout.write(`PASS T12.1-BROWSER-TWO-RUN ${JSON.stringify(output)}\n`);
} finally { await browser.close(); }
