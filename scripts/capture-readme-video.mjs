#!/usr/bin/env node
// Capture pixel-exact README footage of the local /play/ client. Records the
// 320x200 canvas bitmap itself (captureStream + VP9), so the output is the
// authentic database-selected framebuffer at the client's real presentation
// cadence, not a screen scrape. Produces two clips: the title/menu intro and
// live gameplay (skipping the engine-construction wait between them).
//
// Usage: node scripts/capture-readme-video.mjs <outdir> [choreography.json]
import { chromium } from '@playwright/test';
import { writeFileSync, readFileSync, mkdirSync } from 'node:fs';
import { join } from 'node:path';

const outDir = process.argv[2] ?? 'media';
mkdirSync(outDir, { recursive: true });
const choreography = process.argv[3] ?
  JSON.parse(readFileSync(process.argv[3], 'utf8')) : [
    ['wait', 500],
    ['down', 'KeyW'], ['wait', 1500],
    ['tap', 'KeyF', 180], ['wait', 700],
    ['down', 'KeyD'], ['wait', 250], ['up', 'KeyD'], ['wait', 900],
    ['tap', 'KeyF', 180], ['wait', 600],
    ['down', 'KeyD'], ['wait', 250], ['up', 'KeyD'], ['wait', 900],
    ['tap', 'KeyF', 180], ['wait', 500],
    ['up', 'KeyW'], ['wait', 300],
    ['tap', 'KeyF', 180], ['wait', 500],
    ['tap', 'KeyF', 180], ['wait', 500],
    ['down', 'KeyA'], ['wait', 200], ['up', 'KeyA'], ['wait', 300],
    ['tap', 'KeyF', 180], ['wait', 600],
    ['tap', 'KeyF', 180], ['wait', 900]
  ];

const browser = await chromium.launch();
const page = await browser.newPage({ viewport: { width: 1280, height: 840 } });
page.on('pageerror', error => console.error(`[pageerror] ${error.message}`));

await page.goto('http://localhost:8080/play/', { waitUntil: 'domcontentloaded' });
await page.evaluate(() => {
  window.__presented = [];
  window.addEventListener('doom:present', event => {
    window.__presented.push(event.detail.at);
  });
});

const startRecorder = () => page.evaluate(() => {
  const canvas = document.querySelector('canvas[data-doom-canvas]');
  const recorder = new MediaRecorder(canvas.captureStream(), {
    mimeType: 'video/webm;codecs=vp9',
    videoBitsPerSecond: 12_000_000
  });
  const chunks = [];
  recorder.ondataavailable = event => { if (event.data.size) chunks.push(event.data); };
  window.__recording = { recorder, chunks };
  window.__captureStart = window.__presented.length;
  recorder.start(250);
  // A static canvas emits no captureStream frames; nudge identical repaints so
  // held shots (title screen) still occupy real time in the clip.
  const context = canvas.getContext('2d');
  window.__nudge = window.setInterval(() =>
    context.drawImage(canvas, 0, 0), 100);
});

const stopRecorder = async (file) => {
  const result = await page.evaluate(async () => {
    window.clearInterval(window.__nudge);
    const { recorder, chunks } = window.__recording;
    await new Promise(resolve => { recorder.onstop = resolve; recorder.stop(); });
    const bytes = new Uint8Array(await new Blob(chunks).arrayBuffer());
    let binary = '';
    for (let i = 0; i < bytes.length; i += 32768)
      binary += String.fromCharCode(...bytes.subarray(i, i + 32768));
    const presented = window.__presented.slice(window.__captureStart);
    const spanMs = presented.length > 1 ? presented.at(-1) - presented[0] : 0;
    return {
      base64: btoa(binary),
      frames: presented.length,
      fps: spanMs > 0 ? ((presented.length - 1) * 1000 / spanMs) : 0
    };
  });
  writeFileSync(file, Buffer.from(result.base64, 'base64'));
  console.log(`wrote ${file}: ${result.frames} authoritative frames, ` +
    `${result.fps.toFixed(2)} FPS presented`);
};

// Clip 1: title screen and authentic WAD menus.
await page.waitForFunction(() =>
  document.body.textContent.includes('press Enter to start'), null, { timeout: 60_000 });
await startRecorder();
await page.waitForTimeout(1800);
await page.keyboard.press('Enter');
await page.waitForFunction(() =>
  document.body.textContent.includes('MAIN MENU'), null, { timeout: 30_000 });
await page.waitForTimeout(1500);
await page.keyboard.press('Enter');
await page.waitForFunction(() =>
  document.body.textContent.includes('Choose a skill level'), null, { timeout: 30_000 });
await page.waitForTimeout(1600);
await page.keyboard.press('Enter');
await stopRecorder(join(outDir, 'intro.webm'));

// Clip 2: live gameplay once the pipeline is warm.
console.log('waiting for the Oracle worker to serve frames…');
await page.waitForFunction(() => window.__presented.length >= 10, null, { timeout: 120_000 });
await page.waitForTimeout(4000);
console.log('pipeline warm, capturing gameplay');
await startRecorder();
for (const [action, a, b] of choreography) {
  if (action === 'wait') await page.waitForTimeout(a);
  else if (action === 'down') await page.keyboard.down(a);
  else if (action === 'up') await page.keyboard.up(a);
  else if (action === 'tap') {
    await page.keyboard.down(a);
    await page.waitForTimeout(b ?? 120);
    await page.keyboard.up(a);
  }
}
await stopRecorder(join(outDir, 'gameplay.webm'));
await browser.close();
