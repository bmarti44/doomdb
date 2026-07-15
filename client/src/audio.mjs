const ASSET_NAME = /^(?:DS[A-Z0-9]{1,30}|D_[A-Z0-9]{1,29})$/;

function validateTuple(tuple) {
  if (!Array.isArray(tuple) || tuple.length !== 5) throw new TypeError('invalid audio tuple');
  const [tic, ordinal, asset, volume, separation] = tuple;
  if (!Number.isInteger(tic) || tic < 0 || !Number.isInteger(ordinal) || ordinal < 0 ||
      typeof asset !== 'string' || !ASSET_NAME.test(asset) ||
      !Number.isInteger(volume) || volume < 0 || volume > 255 ||
      !Number.isInteger(separation) || separation < 0 || separation > 255) {
    throw new TypeError('invalid audio tuple');
  }
  return {tic, ordinal, asset, volume, separation};
}

function decodeBase64(payload) {
  if (typeof payload !== 'string' || !/^[A-Za-z0-9+/]*={0,2}$/.test(payload)) {
    throw new TypeError('invalid asset payload');
  }
  const binary = globalThis.atob(payload);
  const bytes = new Uint8Array(binary.length);
  for (let index = 0; index < binary.length; index += 1) bytes[index] = binary.charCodeAt(index);
  return bytes.buffer;
}

export function createAudioPresenter({endpoint} = {}) {
  if (typeof endpoint !== 'string' || endpoint.length === 0) {
    throw new TypeError('audio endpoint is required');
  }
  const AudioContextConstructor = globalThis.AudioContext || globalThis.webkitAudioContext;
  if (typeof AudioContextConstructor !== 'function') throw new Error('AudioContext is unavailable');

  const context = new AudioContextConstructor();
  const cache = new Map();
  const queue = [];
  let cursor = null;
  let enabled = false;
  let enabling = null;
  let draining = null;

  function loadAsset(asset) {
    if (!cache.has(asset)) {
      cache.set(asset, fetch(endpoint, {
        method: 'POST',
        headers: {'content-type': 'application/json'},
        body: JSON.stringify({p_asset_name: asset})
      }).then(async response => {
        if (!response.ok) throw new Error(`GET_ASSET failed: ${response.status}`);
        const document = await response.json();
        if (!document || typeof document.p_media_type !== 'string' ||
            !document.p_media_type.toLowerCase().startsWith('audio/')) {
          throw new TypeError('invalid asset media type');
        }
        return context.decodeAudioData(decodeBase64(document.p_payload));
      }));
    }
    return cache.get(asset);
  }

  function schedule(event, buffer) {
    const source = context.createBufferSource();
    const gain = context.createGain();
    const panner = context.createStereoPanner();
    source.buffer = buffer;
    gain.gain.value = event.volume / 255;
    panner.pan.value = Math.max(-1, Math.min(1, (event.separation - 128) / 127));
    source.connect(gain);
    gain.connect(panner);
    panner.connect(context.destination);
    source.start();
  }

  function flush() {
    if (!enabled) return draining;
    if (!draining) {
      draining = (async () => {
        while (enabled && queue.length > 0) {
          const {event, bufferPromise} = queue[0];
          const buffer = await bufferPromise;
          queue.shift();
          schedule(event, buffer);
        }
      })().finally(() => {
        draining = null;
        if (enabled && queue.length > 0) void flush();
      });
    }
    return draining;
  }

  async function consume(tuples) {
    if (!Array.isArray(tuples)) throw new TypeError('audio timeline must be an array');
    const accepted = [];
    let candidate = cursor;
    for (const tuple of tuples) {
      const event = validateTuple(tuple);
      if (candidate && (event.tic < candidate.tic ||
          (event.tic === candidate.tic && event.ordinal <= candidate.ordinal))) {
        const duplicate = event.tic === candidate.tic && event.ordinal === candidate.ordinal;
        throw new Error(duplicate ? 'duplicate audio event' : 'reordered audio event');
      }
      candidate = {tic: event.tic, ordinal: event.ordinal};
      accepted.push(event);
    }
    cursor = candidate;
    const entries = accepted.map(event => ({event, bufferPromise: loadAsset(event.asset)}));
    queue.push(...entries);
    try {
      await Promise.all(entries.map(entry => entry.bufferPromise));
    } catch (error) {
      for (const entry of entries) {
        const index = queue.indexOf(entry);
        if (index >= 0) queue.splice(index, 1);
      }
      throw error;
    }
    if (enabled) await flush();
  }

  async function enable() {
    if (enabled) return;
    if (!enabling) {
      enabling = context.resume().then(() => {
        enabled = true;
        return flush();
      });
    }
    return enabling;
  }

  return {
    consume, enable, flush,
    get cursor() { return cursor && [cursor.tic, cursor.ordinal]; },
    get queued() { return queue.length; },
    get cacheSize() { return cache.size; }
  };
}
