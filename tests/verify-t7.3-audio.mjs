import assert from 'node:assert/strict';

const requests = [];
const log = [];
globalThis.atob = value => Buffer.from(value, 'base64').toString('binary');
globalThis.fetch = async (url, options) => {
  requests.push([url, options]);
  return {
    ok: true,
    async json() { return {p_payload: 'AQIDBA==', p_media_type: 'audio/wav'}; }
  };
};
globalThis.AudioContext = class {
  constructor() { this.destination = {}; }
  async resume() { log.push('resume'); }
  async decodeAudioData(bytes) { log.push(['decode', bytes.byteLength]); return {bytes}; }
  createBufferSource() {
    const node = {connect() { return node; }, start() { log.push('start'); }};
    return node;
  }
  createGain() {
    const node = {gain: {value: 0}, connect() { log.push(['gain', node.gain.value]); return node; }};
    return node;
  }
  createStereoPanner() {
    const node = {pan: {value: 0}, connect() { log.push(['pan', node.pan.value]); return node; }};
    return node;
  }
};

const {createAudioPresenter} = await import('../client/src/audio.mjs');
const presenter = createAudioPresenter({endpoint: '/ords/doom/doom_api/get_asset/'});
await presenter.consume([[7,0,'DSPISTOL',255,128],[7,1,'DSPISTOL',128,255]]);
assert.equal(presenter.queued, 2);
assert.equal(requests.length, 1);
assert.equal(log.filter(item => item === 'start').length, 0);
await presenter.enable();
assert.equal(log.filter(item => item === 'start').length, 2);
assert.deepEqual(log.filter(item => Array.isArray(item) && item[0] === 'decode'), [['decode',4]]);
assert.deepEqual(log.filter(item => Array.isArray(item) && item[0] === 'gain').map(item => item[1]), [1,128/255]);
assert.deepEqual(log.filter(item => Array.isArray(item) && item[0] === 'pan').map(item => item[1]), [0,1]);
await presenter.enable();
presenter.flush();
assert.equal(log.filter(item => item === 'start').length, 2);
await assert.rejects(() => presenter.consume([[7,1,'DSPISTOL',255,128]]), /duplicate/);
await assert.rejects(() => presenter.consume([[6,0,'DSPISTOL',255,128]]), /reordered/);
await assert.rejects(() => presenter.consume([[8,0,'bad',255,128]]), /invalid audio tuple/);
assert.equal(requests.length, 1);
assert.equal(requests[0][1].method, 'POST');
assert.equal(requests[0][1].headers['content-type'], 'application/json');
assert.equal(requests[0][1].body, '{"p_asset_name":"DSPISTOL"}');

const orderedLog = [];
let resolveFirst;
globalThis.fetch = async (url, options) => {
  requests.push([url, options]);
  const asset = JSON.parse(options.body).p_asset_name;
  if (asset === 'DSFIRST') await new Promise(resolve => { resolveFirst = resolve; });
  return {ok: true, async json() {
    return {p_payload: asset === 'DSFIRST' ? 'AQ==' : 'Ag==', p_media_type: 'audio/wav'};
  }};
};
globalThis.AudioContext = class {
  constructor() { this.destination = {}; }
  async resume() {}
  async decodeAudioData(bytes) { return {tag: new Uint8Array(bytes)[0]}; }
  createBufferSource() {
    const node = {buffer: null, connect() { return node; }, start() { orderedLog.push(node.buffer.tag); }};
    return node;
  }
  createGain() { const node = {gain: {value: 0}, connect() { return node; }}; return node; }
  createStereoPanner() { const node = {pan: {value: 0}, connect() { return node; }}; return node; }
};
const ordered = createAudioPresenter({endpoint: '/ords/doom/doom_api/get_asset/'});
await ordered.enable();
const first = ordered.consume([[1,0,'DSFIRST',255,128]]);
const second = ordered.consume([[1,1,'DSSECOND',255,128]]);
await new Promise(resolve => setTimeout(resolve, 0));
assert.deepEqual(orderedLog, []);
resolveFirst();
await Promise.all([first, second]);
assert.deepEqual(orderedLog, [1,2]);
process.stdout.write('PASS T7.3-AUDIO-UNIT (strict cursor, cache, decode, gesture, one-time scheduling)\n');
