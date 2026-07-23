#!/usr/bin/env node
import assert from 'node:assert/strict';
import fs from 'node:fs';
import {chromium} from '@playwright/test';

const base = process.env.DOOMDB_DASHBOARD_URL ?? 'http://127.0.0.1:8080/';
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
    '06ac33331d9a…');
  assert.equal(await page.locator('#presentation-artifact').textContent(),
    'bd35d27784db…');
  assert.equal(await page.locator('#ledger-state').textContent(),
    'PASS · 13,272');
  assert.equal(await page.locator('#soak-state').textContent(), 'PASS · 30 min');
  assert.equal(await page.locator('a[href="/play/"]').first().getAttribute('href'),
    '/play/');
  assert.equal(await page.locator('a[href="/play/multiplayer.html"]').first()
    .getAttribute('href'), '/play/multiplayer.html');
  assert.deepEqual(errors, []);
  await page.screenshot({path: screenshot, fullPage: true});
  console.log(`PASS MLE-DASHBOARD-LIVE url=${base} screenshot=${screenshot}`);
} finally {
  await browser.close();
}
