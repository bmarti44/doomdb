export type AudioTuple = readonly [number, number, string, number, number];

export type Frame = {
  tic: number;
  mode: string;
  complete: 0 | 1;
  frameSha: string;
  indices: Uint8Array<ArrayBuffer>;
  audio: AudioTuple[];
};

type DecodedFrame = Frame & {transportIndices: Uint8Array<ArrayBuffer>};

const rleFrameKeys = ['audio', 'cols', 'complete', 'frame_sha', 'h', 'mode', 'state_sha', 'tic', 'v', 'w'];
const packedFrameKeys = ['audio', 'complete', 'frame_b64', 'frame_sha', 'h', 'mode', 'state_sha', 'tic', 'v', 'w'];

function base64Bytes(encoded: string): Uint8Array<ArrayBuffer> {
  if (!/^[A-Za-z0-9+/]*={0,2}$/.test(encoded)) throw new TypeError('payload base64 is invalid');
  const binary = atob(encoded);
  const bytes = new Uint8Array(binary.length);
  for (let index = 0; index < binary.length; index += 1) bytes[index] = binary.charCodeAt(index);
  return bytes;
}

export function decodeBytes(encoded: string): Uint8Array<ArrayBuffer> {
  return base64Bytes(encoded);
}

function audioTuples(value: unknown, tic: number): AudioTuple[] {
  if (!Array.isArray(value)) throw new TypeError('payload audio is invalid');
  return value.map((entry, ordinal) => {
    if (!Array.isArray(entry) || entry.length !== 5) throw new TypeError('payload audio tuple is invalid');
    const [eventTic, eventOrdinal, asset, volume, separation] = entry as unknown[];
    if (eventTic !== tic || eventOrdinal !== ordinal || typeof asset !== 'string' ||
        !/^(?:DS|D_)[A-Z0-9_]+$/.test(asset) || !Number.isInteger(volume) ||
        !Number.isInteger(separation) || (volume as number) < 0 || (volume as number) > 255 ||
        (separation as number) < 0 || (separation as number) > 255) {
      throw new TypeError('payload audio tuple is invalid');
    }
    return [eventTic, eventOrdinal, asset, volume, separation] as AudioTuple;
  });
}

function frameFrom(value: unknown): DecodedFrame {
  if (typeof value !== 'object' || value === null || Array.isArray(value)) {
    throw new TypeError('payload JSON is invalid');
  }
  const document = value as Record<string, unknown>;
  const keys = Object.keys(document).sort().join('|');
  const rle = document.v === 1 && keys === rleFrameKeys.join('|');
  const packed = document.v === 2 && keys === packedFrameKeys.join('|');
  if (!rle && !packed) {
    throw new TypeError('payload frame fields are invalid');
  }
  if (document.w !== 320 || document.h !== 200 ||
      !Number.isInteger(document.tic) || typeof document.mode !== 'string' ||
      typeof document.frame_sha !== 'string' || !/^[0-9a-f]{64}$/.test(document.frame_sha) ||
      typeof document.state_sha !== 'string' || !/^[0-9a-f]{64}$/.test(document.state_sha) ||
      (document.complete !== 0 && document.complete !== 1)) {
    throw new TypeError('payload frame envelope is invalid');
  }
  const indices = new Uint8Array(320 * 200);
  const transportIndices = new Uint8Array(320 * 200);
  if (rle) {
    if (!Array.isArray(document.cols) || document.cols.length !== 320) {
      throw new TypeError('payload frame envelope is invalid');
    }
    for (let x = 0; x < 320; x += 1) {
      const column: unknown = document.cols[x];
      if (!Array.isArray(column)) throw new TypeError('payload column is invalid');
      let y = 0;
      for (const item of column) {
        if (!Array.isArray(item) || item.length !== 3) throw new TypeError('payload run is invalid');
        const [y0, length, color] = item as unknown[];
        if (y0 !== y || !Number.isInteger(length) || !Number.isInteger(color) ||
            (length as number) < 1 || y + (length as number) > 200 ||
            (color as number) < 0 || (color as number) > 255) {
          throw new TypeError('payload run value is invalid');
        }
        for (let offset = 0; offset < (length as number); offset += 1) {
          indices[(y + offset) * 320 + x] = color as number;
          transportIndices[x * 200 + y + offset] = color as number;
        }
        y += length as number;
      }
      if (y !== 200) throw new TypeError('payload column coverage is invalid');
    }
  } else {
    if (typeof document.frame_b64 !== 'string') throw new TypeError('payload frame envelope is invalid');
    const packedBytes = base64Bytes(document.frame_b64);
    if (packedBytes.length !== transportIndices.length) throw new TypeError('payload packed frame is invalid');
    transportIndices.set(packedBytes);
    for (let x = 0; x < 320; x += 1) {
      for (let y = 0; y < 200; y += 1) indices[y * 320 + x] = packedBytes[x * 200 + y] as number;
    }
  }
  const tic = document.tic as number;
  return {
    tic,
    mode: document.mode,
    complete: document.complete as 0 | 1,
    frameSha: document.frame_sha,
    indices,
    audio: audioTuples(document.audio, tic),
    transportIndices
  };
}

function ascii(bytes: Uint8Array<ArrayBuffer>, start: number, length: number): string {
  return new TextDecoder('ascii', {fatal: true}).decode(bytes.subarray(start, start + length));
}

function binaryFrameFrom(bytes: Uint8Array<ArrayBuffer>): DecodedFrame {
  const magic = bytes.length >= 4 ? ascii(bytes, 0, 4) : '';
  if ((magic !== 'DMF3' && magic !== 'DMF4') || bytes.length < 140) {
    throw new TypeError('payload binary header is invalid');
  }
  const view = new DataView(bytes.buffer, bytes.byteOffset, bytes.byteLength);
  const tic = view.getInt32(4, false), modeByte = bytes[8], complete = bytes[9];
  const stateSha = ascii(bytes, 10, 64), frameSha = ascii(bytes, 74, 64);
  const audioLength = view.getUint16(138, false), frameStart = 140 + audioLength;
  if (tic < 0 || (modeByte !== 0 && modeByte !== 1) ||
      (complete !== 0 && complete !== 1) ||
      !/^[0-9a-f]{64}$/.test(stateSha) || !/^[0-9a-f]{64}$/.test(frameSha) ||
      frameStart > bytes.length ||
      (magic === 'DMF3' && bytes.length !== frameStart + 320 * 200)) {
    throw new TypeError('payload binary envelope is invalid');
  }
  let audio: unknown;
  try {
    audio = JSON.parse(new TextDecoder('utf-8', {fatal: true})
      .decode(bytes.subarray(140, frameStart))) as unknown;
  } catch (cause) {
    throw new TypeError('payload binary audio is invalid', {cause});
  }
  const transportIndices = new Uint8Array(320 * 200);
  if (magic === 'DMF3') {
    transportIndices.set(bytes.subarray(frameStart));
  } else {
    let source = frameStart, target = 0;
    while (source < bytes.length && target < transportIndices.length) {
      const control = bytes[source++] as number;
      const length = (control & 0x7f) + 1;
      if ((control & 0x80) !== 0) {
        if (source >= bytes.length || target + length > transportIndices.length)
          throw new TypeError('payload binary RLE is invalid');
        transportIndices.fill(bytes[source++] as number, target, target + length);
      } else {
        if (source + length > bytes.length || target + length > transportIndices.length)
          throw new TypeError('payload binary RLE is invalid');
        transportIndices.set(bytes.subarray(source, source + length), target);
        source += length;
      }
      target += length;
    }
    if (source !== bytes.length || target !== transportIndices.length)
      throw new TypeError('payload binary RLE coverage is invalid');
  }
  const indices = new Uint8Array(320 * 200);
  for (let x = 0; x < 320; x += 1) {
    for (let y = 0; y < 200; y += 1) indices[y * 320 + x] = transportIndices[x * 200 + y] as number;
  }
  return {tic, mode: modeByte === 0 ? 'game' : 'dead', complete: complete as 0 | 1,
    frameSha, indices, audio: audioTuples(audio, tic), transportIndices};
}

async function sha256(bytes: Uint8Array<ArrayBuffer>): Promise<string> {
  const digest = new Uint8Array(await crypto.subtle.digest('SHA-256', bytes));
  return Array.from(digest, value => value.toString(16).padStart(2, '0')).join('');
}

export async function decodePayload(encoded: string): Promise<Frame> {
  const bytes = base64Bytes(encoded);
  let inflated: Uint8Array<ArrayBuffer>;
  const raw = bytes.length >= 4 && /^(?:DMF3|DMF4)$/.test(ascii(bytes, 0, 4));
  if (raw) {
    inflated = bytes;
  } else {
    try {
      const stream = new Blob([bytes]).stream().pipeThrough(new DecompressionStream('gzip'));
      inflated = new Uint8Array(await new Response(stream).arrayBuffer());
    } catch (cause) {
      throw new TypeError('gzip payload decode failed', {cause});
    }
  }
  let decoded: DecodedFrame;
  if (inflated.length >= 4 && /^(?:DMF3|DMF4)$/.test(ascii(inflated, 0, 4))) {
    decoded = binaryFrameFrom(inflated);
  } else {
    let document: unknown;
    try {
      document = JSON.parse(new TextDecoder('utf-8', {fatal: true}).decode(inflated)) as unknown;
    } catch (cause) {
      throw new TypeError('gzip payload decode failed', {cause});
    }
    decoded = frameFrom(document);
  }
  // Each producer has exactly one canonical frame_sha orientation. The raw
  // binary envelope comes only from the Mocha adapter, which hashes its native
  // row-major framebuffer. Every gzip-wrapped envelope (legacy JSON and the
  // SQL retained worker's gzip DMF3) hashes the column-major transport bytes.
  // Accepting either orientation for any payload would let a transposed frame
  // validate.
  const expectedSha = await sha256(raw ? decoded.indices : decoded.transportIndices);
  if (decoded.frameSha !== expectedSha) {
    throw new TypeError('payload frame hash is invalid');
  }
  return {
    tic: decoded.tic,
    mode: decoded.mode,
    complete: decoded.complete,
    frameSha: decoded.frameSha,
    indices: decoded.indices,
    audio: decoded.audio
  };
}
