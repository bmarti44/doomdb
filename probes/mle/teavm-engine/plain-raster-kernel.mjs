let texture;
let colormap;
let framebuffer;

function initialize() {
  if (texture !== undefined) return;
  texture = new Uint8Array(65536);
  colormap = new Uint8Array(256);
  framebuffer = new Uint8Array(320 * 200);
  for (let index = 0; index < texture.length; index += 1) {
    texture[index] = (Math.imul(index, 73) + 19) & 0xff;
  }
  for (let index = 0; index < colormap.length; index += 1) {
    colormap[index] = (Math.imul(index, 29) + 7) & 0xff;
  }
}

// Compiler-shape probe only: two byte gathers, integer texture-coordinate
// arithmetic, and one retained 320x200 framebuffer store per pixel.
export function rasterFrame(frames) {
  if (!Number.isInteger(frames) || frames < 1 || frames > 1000) return -1;
  initialize();
  let checksum = 0x13579bdf | 0;
  for (let frameIndex = 0; frameIndex < frames; frameIndex += 1) {
    const phase = (Math.imul(frameIndex, 17) + checksum) | 0;
    for (let y = 0; y < 200; y += 1) {
      const row = Math.imul(y, 320);
      const v = (Math.imul(y, 97) + (phase << 2)) | 0;
      for (let x = 0; x < 320; x += 1) {
        const u = (Math.imul(x, 257) + phase + (y << 3)) | 0;
        const textureIndex = (u + (v & 0xff00)) & 0xffff;
        const sample = texture[textureIndex];
        framebuffer[row + x] =
          colormap[(sample + ((x ^ y) & 31)) & 0xff];
      }
    }
    checksum = (
      Math.imul(checksum, 31)
      + framebuffer[Math.imul(frameIndex, 997) % framebuffer.length]
    ) | 0;
  }
  return checksum;
}

export function footprint() {
  initialize();
  return texture.byteLength + colormap.byteLength + framebuffer.byteLength;
}

export function release() {
  texture = undefined;
  colormap = undefined;
  framebuffer = undefined;
}
