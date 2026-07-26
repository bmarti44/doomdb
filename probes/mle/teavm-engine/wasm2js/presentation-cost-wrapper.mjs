import * as engine from 'doom_wasm2js_presentation_cost_engine';

let jsTexture;
let jsColormap;
let jsFrame;

function initializeJsKernel() {
  if (jsTexture) return;
  jsTexture = new Uint8Array(65536);
  jsColormap = new Uint8Array(256);
  jsFrame = new Uint8Array(320 * 200);
  for (let index = 0; index < jsTexture.length; index += 1) {
    jsTexture[index] = (index * 73 + 19) & 0xff;
  }
  for (let index = 0; index < jsColormap.length; index += 1) {
    jsColormap[index] = (index * 29 + 7) & 0xff;
  }
}

// Exact operation-for-operation JS control for the generated wasm2js kernel.
// Neither arm is an exact Doom renderer: this is a cost lower bound only.
export function renderCostJs(frames) {
  if (!Number.isInteger(frames) || frames < 1 || frames > 1000) return -1;
  initializeJsKernel();
  let checksum = 0x13579bdf | 0;
  for (let frameIndex = 0; frameIndex < frames; frameIndex += 1) {
    const phase = (Math.imul(frameIndex, 17) + checksum) | 0;
    for (let y = 0; y < 200; y += 1) {
      const row = Math.imul(y, 320);
      const v = (Math.imul(y, 97) + (phase << 2)) | 0;
      for (let x = 0; x < 320; x += 1) {
        const u = (Math.imul(x, 257) + phase + (y << 3)) | 0;
        const textureIndex = (u + (v & 0xff00)) & 0xffff;
        const sample = jsTexture[textureIndex];
        const mapped = jsColormap[(sample + ((x ^ y) & 31)) & 0xff];
        jsFrame[row + x] = mapped;
      }
    }
    checksum = (
      Math.imul(checksum, 31)
      + jsFrame[Math.imul(frameIndex, 997) % jsFrame.length]
    ) | 0;
  }
  return checksum;
}

export function renderCostWasm2js(frames) {
  return engine.doom_render_cost_kernel(frames);
}

export function loweringStatus() {
  const values = [
    engine.doom_i64_constant_high(),
    engine.doom_i64_field_high(),
    engine.doom_i64_field_copy_high(),
    engine.doom_i64_array_high(),
    engine.doom_i64_call_high(),
    engine.doom_i64_flag_or_high(),
  ];
  const expected = [15, 15, 23, 7, 15, 15];
  if (values.some((value, index) => value !== expected[index])) {
    throw new Error(`wasm2js i64 lowering mismatch: ${values.join(',')}`);
  }
  return `i64=exact|values=${values.join(',')}`;
}

export function memoryStatus() {
  return `linear_memory_bytes=${engine.memory.buffer.byteLength}`;
}

export function release() {
  jsTexture = undefined;
  jsColormap = undefined;
  jsFrame = undefined;
  const result = engine.doom_release();
  if (result !== 0) {
    throw new Error(`wasm2js release failed: ${result}`);
  }
}
