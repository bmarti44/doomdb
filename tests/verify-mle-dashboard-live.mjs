#!/usr/bin/env node
import assert from 'node:assert/strict';
import fs from 'node:fs';
import {chromium} from '@playwright/test';

const base = process.env.DOOMDB_DASHBOARD_URL ?? 'http://127.0.0.1:8080/';
const versions = JSON.parse(fs.readFileSync('versions.lock', 'utf8'));
const status = JSON.parse(fs.readFileSync('client/dist/mle-status.json', 'utf8'));
const authorityPrefix = versions.teaVM.outputSha256.slice(0, 12);
const screenshot =
  'artifacts/performance/pmle-dashboard/dashboard-2026-07-23.png';
fs.mkdirSync(new URL('../artifacts/performance/pmle-dashboard/', import.meta.url),
  {recursive: true});

const browser = await chromium.launch({headless: true});
try {
  const page = await browser.newPage({viewport: {width: 1440, height: 1200}});
  const errors = [];
  page.on('pageerror', error => errors.push(`page: ${error.message}`));
  page.on('console', message => {
    if (message.type() === 'error') errors.push(`console: ${message.text()}`);
  });
  const response = await page.goto(base, {waitUntil: 'networkidle'});
  assert.equal(response?.status(), 200);
  await page.locator('#evidence-state').waitFor({state: 'visible'});
  await page.waitForFunction(() =>
    document.querySelector('#evidence-state')?.textContent?.startsWith('PASS'));
  assert.equal(await page.locator('#authority-artifact').textContent(),
    `${authorityPrefix}…`);
  assert.equal(await page.locator('#presentation-artifact').textContent(),
    'e55d5f1138fa…');
  assert.equal(await page.locator('#ledger-state').textContent(),
    'PASS · current authority · 13,272');
  assert.equal(await page.locator('#soak-state').textContent(),
    status.gates.finalWorkerSoak === 'PASS_CURRENT_AUTHORITY'
      ? `PASS · ${authorityPrefix.slice(0, 4)}`
      : `PENDING · ${authorityPrefix.slice(0, 4)} RERUN`);
  assert.equal(await page.locator('a[href="/play/"]').first().getAttribute('href'),
    '/play/');
  assert.equal(await page.locator(
    'a[href="/play/multiplayer.html#mode=DEATHMATCH"]').first()
    .getAttribute('href'), '/play/multiplayer.html#mode=DEATHMATCH');
  assert.deepEqual(errors, []);
  await page.screenshot({path: screenshot, fullPage: true});
  console.log(`PASS MLE-DASHBOARD-LIVE url=${base} screenshot=${screenshot}`);
} finally {
  await browser.close();
}
