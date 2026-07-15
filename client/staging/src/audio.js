import { getAsset } from './api.js';
import { decodeBytes } from './codec.js';
export class AudioPresenter {
    context = null;
    enabled = false;
    muted = false;
    cursor = null;
    cache = new Map();
    async enable() {
        if (this.context === null)
            this.context = new AudioContext();
        await this.context.resume();
        this.enabled = true;
    }
    setMuted(value) {
        this.muted = value;
    }
    load(name) {
        const saved = this.cache.get(name);
        if (saved !== undefined)
            return saved;
        const request = getAsset(name).then(asset => {
            if (!asset.mediaType.toLowerCase().startsWith('audio/')) {
                throw new TypeError('audio asset media type is invalid');
            }
            if (this.context === null)
                throw new Error('audio context is unavailable');
            return this.context.decodeAudioData(decodeBytes(asset.payload).buffer);
        });
        this.cache.set(name, request);
        return request;
    }
    async consume(events) {
        for (const event of events) {
            const [tic, ordinal, name, volume, separation] = event;
            if (this.cursor !== null && (tic < this.cursor[0] ||
                (tic === this.cursor[0] && ordinal <= this.cursor[1]))) {
                throw new Error('audio event order is invalid');
            }
            this.cursor = [tic, ordinal];
            if (!this.enabled || this.muted)
                continue;
            const context = this.context;
            if (context === null)
                throw new Error('audio context is unavailable');
            const source = context.createBufferSource();
            const gain = context.createGain();
            const panner = context.createStereoPanner();
            source.buffer = await this.load(name);
            gain.gain.value = volume / 255;
            panner.pan.value = Math.max(-1, Math.min(1, (separation - 128) / 127));
            source.connect(gain);
            gain.connect(panner);
            panner.connect(context.destination);
            source.start(context.currentTime);
        }
    }
}
