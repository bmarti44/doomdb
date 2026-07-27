#!/usr/bin/env node

// The live renderer intentionally uses Doom's one-step-per-column 16.16
// sampler instead of an interpreted integer division for every pixel. Verify
// the only permitted visual residue: a one-texel fixed-point rounding edge.
const textureHeights = [64, 72, 128, 256];
let samples = 0;
let identical = 0;
let maximumCircularDelta = 0;

for (const textureHeight of textureHeights) {
  for (let wallHeight = 1; wallHeight <= 4096; wallHeight += 1) {
    const visibleHeight = Math.min(168, wallHeight);
    for (let offset = 0; offset < textureHeight; offset += 7) {
      for (let clipped = -visibleHeight; clipped <= visibleHeight;
        clipped += 13) {
        const step = Math.trunc(8388608 / wallHeight);
        const fraction = (offset << 16) + Math.imul(clipped, step);
        for (let pixel = 0; pixel < visibleHeight; pixel += 11) {
          let exact = Math.floor(
            (offset * wallHeight + (clipped + pixel) * 128) / wallHeight,
          ) % textureHeight;
          if (exact < 0) exact += textureHeight;
          let fixed = ((fraction + Math.imul(pixel, step)) >> 16)
            % textureHeight;
          if (fixed < 0) fixed += textureHeight;
          const linearDelta = Math.abs(exact - fixed);
          const circularDelta = Math.min(
            linearDelta,
            textureHeight - linearDelta,
          );
          samples += 1;
          if (circularDelta === 0) identical += 1;
          maximumCircularDelta = Math.max(
            maximumCircularDelta,
            circularDelta,
          );
        }
      }
    }
  }
}

if (maximumCircularDelta > 1 || identical / samples < 0.995) {
  throw new Error(
    `fixed-step residue exceeded contract samples=${samples}`
      + ` identical=${identical} maximum=${maximumCircularDelta}`,
  );
}

process.stdout.write(
  'PMLE_FREE_LIVE_FIXED_STEP|PASS'
    + `|samples=${samples}`
    + `|identical=${identical}`
    + `|identical_pct=${(identical * 100 / samples).toFixed(4)}`
    + `|maximum_circular_texel_delta=${maximumCircularDelta}\n`,
);
