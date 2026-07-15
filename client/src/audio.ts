import {getAsset} from './api.js';
import {decodeBytes, type AudioTuple} from './codec.js';

type Cursor = readonly [number, number];

export class AudioPresenter {
  private context: AudioContext | null = null;
  private enabled = false;
  private muted = false;
  private cursor: Cursor | null = null;
  private readonly cache = new Map<string, Promise<AudioBuffer>>();

  async enable(): Promise<void> {
    if (this.context === null) this.context = new AudioContext();
    await this.context.resume();
    this.enabled = true;
  }

  setMuted(value: boolean): void {
    this.muted = value;
  }

  private load(name: string): Promise<AudioBuffer> {
    const saved = this.cache.get(name);
    if (saved !== undefined) return saved;
    const request = getAsset(name).then(asset => {
      if (asset.mediaType.length === 0) throw new TypeError('audio asset type is invalid');
      if (this.context === null) throw new Error('audio context is unavailable');
      const bytes = decodeBytes(asset.payload);
      if (asset.mediaType.toLowerCase() === 'audio/x-doom') {
        if (bytes.length < 8) throw new TypeError('audio asset header is invalid');
        const view = new DataView(bytes.buffer);
        const format = view.getUint16(0, true);
        const rate = view.getUint16(2, true);
        const count = view.getUint32(4, true);
        if (format !== 3 || rate < 4000 || rate > 48000 || count < 1 || count > bytes.length - 8) {
          throw new TypeError('audio asset data is invalid');
        }
        const buffer = this.context.createBuffer(1, count, rate);
        const channel = buffer.getChannelData(0);
        for (let index = 0; index < count; index += 1) {
          channel[index] = (bytes[index + 8]! - 128) / 128;
        }
        return buffer;
      }
      return this.context.decodeAudioData(bytes.buffer);
    });
    this.cache.set(name, request);
    return request;
  }

  async consume(events: AudioTuple[]): Promise<void> {
    for (const event of events) {
      const [tic, ordinal, name, volume, separation] = event;
      if (this.cursor !== null && (tic < this.cursor[0] ||
          (tic === this.cursor[0] && ordinal <= this.cursor[1]))) {
        throw new Error('audio event order is invalid');
      }
      this.cursor = [tic, ordinal];
      if (!this.enabled || this.muted) continue;
      const context = this.context;
      if (context === null) throw new Error('audio context is unavailable');
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
