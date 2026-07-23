import assert from 'node:assert/strict';
import {chromium} from '@playwright/test';

const base = process.env.DOOMDB_HTTP_BASE ?? 'http://127.0.0.1:8080';
const browser = await chromium.launch({headless: true});
try {
  const page = await browser.newPage();
  await page.goto(`${base}/play/multiplayer.html`);
  const result = await page.evaluate(async () => {
    const started = performance.now();
    const {createBrowserAuthorityEngines} =
      await import('/play/teavm-browser.js');
    const engines = await createBrowserAuthorityEngines({
      state: 'ACTIVE', mode: 'COOP', skill: 3, episode: 1, map: 1,
      maxPlayers: 2, memberCount: 2, readyCount: 2, requesterSlot: 0,
      membershipEpoch: 1, generation: 1, currentTic: 0,
      workerMode: 'PACED_INPUT'
    });
    const commands = new Uint8Array(32);
    const verifierTic =
      engines.verifier.stepMultiplayerAuthoritative(2, 3, commands);
    const presenterTic =
      engines.presenter.stepMultiplayerAuthoritative(2, 3, commands);
    const frame = engines.presenter.renderPlayerFrame(0);
    const hud = frame.slice(320 * 168);
    const hudSha256 = Array.from(new Uint8Array(
      await crypto.subtle.digest('SHA-256', hud)),
    value => value.toString(16).padStart(2, '0')).join('');
    return {
      elapsedMs: performance.now() - started,
      verifierTic, presenterTic,
      canonicalBytes: engines.verifier.canonicalStateLength(),
      frameBytes: frame.length,
      nonzero: frame.reduce((count, value) => count + (value === 0 ? 0 : 1), 0),
      hudSha256, hudDistinct: new Set(hud).size
    };
  });
  assert.equal(result.verifierTic, 1);
  assert.equal(result.presenterTic, 1);
  assert.ok(result.canonicalBytes > 0);
  assert.equal(result.frameBytes, 320 * 200);
  assert.ok(result.nonzero > 0);
  assert.equal(result.hudDistinct, 75);
  assert.equal(result.hudSha256,
    'dd2e30a5ca3d0ecdfbce78bf82bdc03898bffc19d201e571fee769eea50bf032');
  console.log(`PMLE_BROWSER_DUAL_CONTEXT|PASS|elapsed_ms=${
    result.elapsedMs.toFixed(3)}|canonical_bytes=${result.canonicalBytes}`
    + `|frame_bytes=${result.frameBytes}|nonzero=${result.nonzero}`
    + `|hud_sha256=${result.hudSha256}|hud_distinct=${result.hudDistinct}`);
} finally {
  await browser.close();
}
