import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {ConfirmedAuthorityMirror} from '../client/staging/authority-mirror.js';

class FakeEngine {
  tic = 0;
  lastMembership = -1;
  stepMultiplayerAuthoritative(_players, membership, commands) {
    assert.equal(commands.length, 32);
    this.lastMembership = membership;
    return ++this.tic;
  }
  canonical() { return Buffer.from(`canonical:${this.tic}`); }
  canonicalState() {
    return `canonicalBytes=${this.canonical().length}|canonicalThinkers=1`
      + `|canonicalState=${this.tic.toString(16).padStart(32, '0')}`;
  }
  canonicalStateLength() { return this.canonical().length; }
  canonicalStateChunk(offset, length) {
    return new Uint8Array(this.canonical().subarray(offset, offset + length));
  }
  renderPlayerFrame(player) { return new Uint8Array(320 * 200).fill(player + this.tic); }
}

const zero = '00'.repeat(32), one = '11'.repeat(32), two = '22'.repeat(32);
const verifier = new FakeEngine(), presenter = new FakeEngine();
const mirror = new ConfirmedAuthorityMirror(verifier, presenter, 1,
  {tic: 0, generation: 1, membershipEpoch: 7, chainSha: zero});
const first = {tic: 1, generation: 1, membershipEpoch: 7,
  membershipBitmap: 3, activePlayers: 2, complete: 0,
  previousChainSha: zero, chainSha: one,
  canonicalStateSha: createHash('sha256').update(
    'canonicalBytes=11|canonicalThinkers=1|canonicalState=00000000000000000000000000000001'
  ).digest('hex'),
  commands: new Uint8Array(32), audio: []};
const presentation = await mirror.apply(first);
assert.equal(presentation.tic, 1);assert.equal(presentation.frame[0], 2);
assert.equal(verifier.lastMembership, 3);assert.equal(presenter.lastMembership, 3);
assert.equal(mirror.frontier.chainSha, one);
assert.throws(() => new ConfirmedAuthorityMirror(verifier, verifier, 1,
  {tic: 0, generation: 1, membershipEpoch: 7, chainSha: zero}),
  /must be independent/);

const divergent = {...first, tic: 2, previousChainSha: one, chainSha: two,
  canonicalStateSha: zero};
await assert.rejects(mirror.apply(divergent), /canonical state diverged/);
assert.equal(mirror.frontier.tic, 1);
await assert.rejects(mirror.apply(divergent), /requires recovery/);
console.log('PASS confirmed-only TeaVM authority mirror/failure recovery fence');
