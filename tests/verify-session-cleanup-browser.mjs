#!/usr/bin/env node
import assert from 'node:assert/strict';
import crypto from 'node:crypto';
import {chromium} from '@playwright/test';

const appUrl=new URL(process.env.DOOMDB_HOSTED_APP_URL ??
  'https://G53C2244DAB9063-DOOMDB.adb.us-ashburn-1.oraclecloudapps.com/ords/doom/app/');
assert.equal(appUrl.protocol,'https:');
assert.match(appUrl.pathname,/\/ords\/doom\/app\/$/);
const apiRoot=new URL('../doom_api/',appUrl);
const soloUrl=new URL('./solo.html#solo=1&skill=3',appUrl);
const sha=value=>crypto.createHash('sha256').update(value).digest('hex');

async function post(path,body) {
  const response=await fetch(new URL(path,apiRoot),{
    method:'POST',
    headers:{'content-type':'application/json','accept':'application/json'},
    body:JSON.stringify(body)
  });
  assert.equal(response.ok,true,`${path} returned HTTP ${response.status}`);
  return response.json();
}

async function credentials(page) {
  return page.evaluate(() => {
    const match=localStorage.getItem('doomdb.solo.current');
    if(match===null)return null;
    const raw=localStorage.getItem(`doomdb.match.${match}`);
    if(raw===null)return null;
    const value=JSON.parse(raw);
    return typeof value.playerCapability==='string'
      ? {match,playerCapability:value.playerCapability}:null;
  });
}

async function waitForCredentials(page,priorMatch=null) {
  await page.waitForFunction(prior => {
    const match=localStorage.getItem('doomdb.solo.current');
    if(match===null||match===prior)return false;
    const raw=localStorage.getItem(`doomdb.match.${match}`);
    if(raw===null)return false;
    return typeof JSON.parse(raw).playerCapability==='string';
  },priorMatch,{timeout:180_000});
  const value=await credentials(page);
  assert.ok(value!==null);
  return value;
}

async function waitForState(identity,states,timeoutMs=90_000) {
  const deadline=performance.now()+timeoutMs;
  let latest='';
  while(performance.now()<deadline) {
    const status=await post('MATCH_STATUS',{
      p_match:identity.match,p_capability:identity.playerCapability
    });
    latest=String(status.p_match_state);
    if(states.includes(latest))return status;
    await new Promise(resolve=>setTimeout(resolve,250));
  }
  assert.fail(`match did not reach ${states.join('/')} (last=${latest})`);
}

async function leave(identity) {
  try {
    await post('LEAVE_MATCH',{
      p_match:identity.match,
      p_player_capability:identity.playerCapability
    });
  } catch {
    // The database abandonment reconciler is the fail-safe. The test's state
    // waits below still fail closed if explicit cleanup did not take effect.
  }
}

const terminal=['FINISHED','CANCELLED','TERMINATED'];
const browser=await chromium.launch({headless:true});
let first=null,second=null,third=null;
try {
  const context=await browser.newContext({
    locale:'en-US',timezoneId:'UTC',serviceWorkers:'block'
  });
  const page=await context.newPage();
  await page.goto(soloUrl.href,{waitUntil:'domcontentloaded'});
  first=await waitForCredentials(page);
  await waitForState(first,['ACTIVE'],180_000);

  const refreshStarted=performance.now();
  await page.reload({waitUntil:'domcontentloaded'});
  second=await waitForCredentials(page,first.match);
  const firstTerminal=await waitForState(first,terminal);
  await waitForState(second,['ACTIVE'],180_000);
  const refreshReleaseMs=Math.round(performance.now()-refreshStarted);
  assert.notEqual(second.match,first.match);

  const closeStarted=performance.now();
  await page.close({runBeforeUnload:true});
  const secondTerminal=await waitForState(second,terminal,90_000);
  const closeReleaseMs=Math.round(performance.now()-closeStarted);

  // Prove the only Free-tier game slot is reusable after a real tab close.
  const capacityPage=await context.newPage();
  await capacityPage.goto(soloUrl.href,{waitUntil:'domcontentloaded'});
  third=await waitForCredentials(capacityPage);
  await waitForState(third,['ACTIVE'],180_000);
  await leave(third);
  await waitForState(third,terminal);
  await capacityPage.close({runBeforeUnload:true});
  await context.close();

  process.stdout.write(
    'PASS SESSION-CLEANUP-BROWSER'
      + ` refresh_old=${sha(first.match)}`
      + ` refresh_new=${sha(second.match)}`
      + ` close_match=${sha(second.match)}`
      + ` capacity_reuse=${sha(third.match)}`
      + ` refresh_release_ms=${refreshReleaseMs}`
      + ` close_release_ms=${closeReleaseMs}`
      + ` refresh_state=${firstTerminal.p_match_state}`
      + ` close_state=${secondTerminal.p_match_state}\n`);
} finally {
  if(first!==null)await leave(first);
  if(second!==null)await leave(second);
  if(third!==null)await leave(third);
  await browser.close();
}
