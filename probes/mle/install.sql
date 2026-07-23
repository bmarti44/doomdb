whenever oserror exit failure rollback
whenever sqlerror exit sql.sqlcode rollback
set define off echo off verify off feedback off

begin
  execute immediate 'drop procedure doom_mle_bench_commands';
exception when others then if sqlcode <> -4043 then raise; end if;
end;
/
begin
  execute immediate 'drop procedure doom_mle_bench_columns';
exception when others then if sqlcode <> -4043 then raise; end if;
end;
/
begin
  execute immediate 'drop procedure doom_mle_bench_tape';
exception when others then if sqlcode <> -4043 then raise; end if;
end;
/
begin
  execute immediate 'drop procedure doom_mle_bench_cached_tape';
exception when others then if sqlcode <> -4043 then raise; end if;
end;
/
begin
  execute immediate 'drop procedure doom_mle_bench_render';
exception when others then if sqlcode <> -4043 then raise; end if;
end;
/
begin
  execute immediate 'drop function doom_mle_bench_arithmetic';
exception when others then if sqlcode <> -4043 then raise; end if;
end;
/
begin
  execute immediate 'drop function doom_mle_bench_counter';
exception when others then if sqlcode <> -4043 then raise; end if;
end;
/
begin
  execute immediate 'drop function doom_mle_bench_capability';
exception when others then if sqlcode <> -4043 then raise; end if;
end;
/
begin
  execute immediate 'drop mle module doom_mle_bench';
exception when others then if sqlcode not in (-4080, -4103) then raise; end if;
end;
/
begin
  execute immediate 'drop mle env doom_mle_bench_env';
exception when others then if sqlcode not in (-4080, -4103, -4104, -4105) then raise; end if;
end;
/

create mle env doom_mle_bench_env pure;

create mle module doom_mle_bench
language javascript as

const WIDTH = 320;
const HEIGHT = 200;
const FRAME_BYTES = WIDTH * HEIGHT;
const CHUNK_BYTES = FRAME_BYTES / 2;
const TEXTURE_SIZE = 64;
const texture = new Uint8Array(TEXTURE_SIZE * TEXTURE_SIZE);
const colormaps = new Uint8Array(32 * 256);
const frame = new Uint8Array(FRAME_BYTES);
const cachedColumns = new Array(256);
const renderCommands = new Uint8Array(WIDTH * 2);
const REAL_COLUMN_COMMANDS = 1416;
const REAL_SPAN_COMMANDS = 667;
const TAPE_RECORD_BYTES = 16;
const drawTape = new Uint8Array(
  (REAL_COLUMN_COMMANDS + REAL_SPAN_COMMANDS) * TAPE_RECORD_BYTES);
let invocationCounter = 0;

for (let i = 0; i < texture.length; i++) {
  texture[i] = (Math.imul(i, 73) + (i >>> 3) + 19) & 255;
}
for (let light = 0; light < 32; light++) {
  for (let color = 0; color < 256; color++) {
    colormaps[(light << 8) | color] = Math.max(0, color - light * 3);
  }
}
for (let columnIndex = 0; columnIndex < cachedColumns.length; columnIndex++) {
  const column = new Uint8Array(HEIGHT);
  const textureX = columnIndex & 63;
  const lightBase = ((columnIndex >>> 3) & 31) << 8;
  let textureY = (columnIndex * 11) & 63;
  for (let y = 0; y < HEIGHT; y++) {
    textureY = (textureY + 3) & 63;
    column[y] = colormaps[lightBase | texture[(textureY << 6) | textureX]];
  }
  cachedColumns[columnIndex] = column;
}

function publishFrame(chunk0, chunk1, checksumOut, checksum) {
  chunk0.value = frame.slice(0, CHUNK_BYTES);
  chunk1.value = frame.slice(CHUNK_BYTES);
  checksumOut.value = checksum | 0;
}

export function capability() {
  const navigatorUserAgent = typeof navigator === 'object'
    ? (navigator.userAgent ?? navigator.useragent ?? null)
    : null;
  return JSON.stringify({
    navigator: typeof navigator,
    navigatorUserAgent,
    webAssembly: typeof WebAssembly,
    arrayBuffer: typeof ArrayBuffer,
    uint8Array: typeof Uint8Array,
    sharedArrayBuffer: typeof SharedArrayBuffer,
    atomics: typeof Atomics,
    bigInt: typeof BigInt,
    performanceNow: typeof performance?.now
  });
}

export function counter() {
  invocationCounter++;
  return invocationCounter;
}

export function arithmetic(iterations, seed) {
  let value = seed | 0;
  const count = iterations | 0;
  for (let i = 0; i < count; i++) {
    value = (Math.imul(value ^ i, 1664525) + 1013904223) | 0;
    value = (value + (value >>> 16)) | 0;
  }
  return value;
}

export function render(seed, chunk0, chunk1, checksumOut) {
  const phase = seed | 0;
  let checksum = 0;

  // A deterministic lower-bound surrogate for the real software renderer:
  // every output pixel performs perspective-like coordinate arithmetic, an
  // arbitrary texture gather, a light-table gather, and a framebuffer store.
  // It intentionally excludes BSP traversal, clipping, sprites, HUD, audio,
  // simulation, hashing, persistence, AQ, ORDS, and browser work.
  for (let x = 0; x < WIDTH; x++) {
    const ray = (Math.imul(x + phase, 1103515245) + 12345) | 0;
    const light = ((ray >>> 19) + (x >>> 4)) & 31;
    const textureX = (ray >>> 7) & 63;
    let textureY = (phase + x * 3) & 63;
    let step = ((ray >>> 23) & 7) + 1;

    for (let y = 0; y < HEIGHT; y++) {
      textureY = (textureY + step) & 63;
      const sample = texture[(textureY << 6) | textureX];
      const pixel = colormaps[(light << 8) | sample];
      frame[y * WIDTH + x] = pixel;
      checksum = (checksum + pixel + x + y) | 0;
      step = (step + ((y ^ x) & 1)) & 63;
      if (step === 0) step = 1;
    }
  }

  publishFrame(chunk0, chunk1, checksumOut, checksum);
}

export function renderColumns(seed, dynamicColumns, chunk0, chunk1, checksumOut) {
  const phase = seed | 0;
  const misses = Math.max(0, Math.min(WIDTH, dynamicColumns | 0));
  let checksum = 0;

  // Doom's public DMF frame is column-major. Cached columns use the runtime's
  // native bulk copy. The first `misses` columns execute the unavoidable
  // texture/light gathers for a newly visible or newly scaled column. Varying
  // misses maps the exact cache-hit ratio needed to fit the frame budget.
  for (let x = 0; x < WIDTH; x++) {
    const destination = x * HEIGHT;
    if (x >= misses) {
      const column = cachedColumns[(x + phase) & 255];
      frame.set(column, destination);
      checksum = (checksum + column[0] + column[HEIGHT - 1]) | 0;
      continue;
    }

    const ray = (Math.imul(x + phase, 1103515245) + 12345) | 0;
    const lightBase = (((ray >>> 19) + (x >>> 4)) & 31) << 8;
    const textureX = (ray >>> 7) & 63;
    let textureY = (phase + x * 3) & 63;
    const step = ((ray >>> 23) & 7) + 1;
    for (let y = 0; y < HEIGHT; y++) {
      textureY = (textureY + step) & 63;
      frame[destination + y] =
        colormaps[lightBase | texture[(textureY << 6) | textureX]];
    }
    checksum = (checksum + frame[destination] + frame[destination + HEIGHT - 1]) | 0;
  }

  publishFrame(chunk0, chunk1, checksumOut, checksum);
}

export function commands(seed, commandOut, checksumOut) {
  const phase = seed | 0;
  let checksum = 0;
  for (let x = 0; x < WIDTH; x++) {
    const sourceColumn = (x + phase) & 255;
    const light = ((x + phase) >>> 3) & 31;
    renderCommands[x * 2] = sourceColumn;
    renderCommands[x * 2 + 1] = light;
    checksum = (checksum + sourceColumn + light) | 0;
  }
  commandOut.value = renderCommands.slice();
  checksumOut.value = checksum;
}

export function productionTape(seed, tapeOut, checksumOut) {
  const phase = seed | 0;
  let checksum = 0;
  let offset = 0;
  // The measured Mocha frame issues 1,416 columns and 667 spans. This compact
  // fixed-width tape models that real cardinality and deliberately exceeds
  // RAW(32767), exercising the BLOB boundary required by the actual renderer.
  for (let command = 0; command < REAL_COLUMN_COMMANDS; command++) {
    const x = (command + phase) % WIDTH;
    const yl = (Math.imul(command, 17) + phase) % 120;
    const count = 8 + ((command + phase) % (HEIGHT - yl - 7));
    drawTape[offset] = 1;
    drawTape[offset + 1] = x & 255;
    drawTape[offset + 2] = x >>> 8;
    drawTape[offset + 3] = yl;
    drawTape[offset + 4] = count;
    drawTape[offset + 5] = command & 63;
    drawTape[offset + 6] = (command >>> 3) & 31;
    drawTape[offset + 7] = (command + phase) & 63;
    const frac = Math.imul(command + phase, 1103515245) | 0;
    const step = ((command & 7) + 1) << 10;
    for (let byte = 0; byte < 4; byte++) {
      drawTape[offset + 8 + byte] = frac >>> (byte * 8);
      drawTape[offset + 12 + byte] = step >>> (byte * 8);
    }
    checksum = (checksum + x + yl + count + frac + step) | 0;
    offset += TAPE_RECORD_BYTES;
  }
  for (let command = 0; command < REAL_SPAN_COMMANDS; command++) {
    const y = (command + phase) % HEIGHT;
    const x1 = Math.imul(command, 13) % 240;
    const count = 8 + (command % (WIDTH - x1 - 7));
    drawTape[offset] = 2;
    drawTape[offset + 1] = y;
    drawTape[offset + 2] = x1 & 255;
    drawTape[offset + 3] = x1 >>> 8;
    drawTape[offset + 4] = count & 255;
    drawTape[offset + 5] = count >>> 8;
    drawTape[offset + 6] = command & 63;
    drawTape[offset + 7] = (command >>> 3) & 31;
    const xfrac = Math.imul(command + phase, 1664525) | 0;
    const yfrac = Math.imul(command + phase, 22695477) | 0;
    for (let byte = 0; byte < 4; byte++) {
      drawTape[offset + 8 + byte] = xfrac >>> (byte * 8);
      drawTape[offset + 12 + byte] = yfrac >>> (byte * 8);
    }
    checksum = (checksum + y + x1 + count + xfrac + yfrac) | 0;
    offset += TAPE_RECORD_BYTES;
  }
  tapeOut.value = drawTape.slice();
  checksumOut.value = checksum;
}

export function cachedProductionTape(tapeOut) {
  tapeOut.value = drawTape.slice();
}
/

create function doom_mle_bench_capability return varchar2
as mle module doom_mle_bench
env doom_mle_bench_env
signature 'capability()';
/

create function doom_mle_bench_counter return number
as mle module doom_mle_bench
env doom_mle_bench_env
signature 'counter()';
/

create function doom_mle_bench_arithmetic(
  p_iterations in number,
  p_seed in number
) return number
as mle module doom_mle_bench
env doom_mle_bench_env
signature 'arithmetic(number, number)';
/

create procedure doom_mle_bench_render(
  p_seed in number,
  p_chunk0 out raw,
  p_chunk1 out raw,
  p_checksum out number
)
as mle module doom_mle_bench
env doom_mle_bench_env
signature 'render(number, Out<Uint8Array>, Out<Uint8Array>, Out<number>)';
/

create procedure doom_mle_bench_columns(
  p_seed in number,
  p_dynamic_columns in number,
  p_chunk0 out raw,
  p_chunk1 out raw,
  p_checksum out number
)
as mle module doom_mle_bench
env doom_mle_bench_env
signature 'renderColumns(number, number, Out<Uint8Array>, Out<Uint8Array>, Out<number>)';
/

create procedure doom_mle_bench_commands(
  p_seed in number,
  p_commands out raw,
  p_checksum out number
)
as mle module doom_mle_bench
env doom_mle_bench_env
signature 'commands(number, Out<Uint8Array>, Out<number>)';
/

create procedure doom_mle_bench_tape(
  p_seed in number,
  p_tape out blob,
  p_checksum out number
)
as mle module doom_mle_bench
env doom_mle_bench_env
signature 'productionTape(number, Out<Uint8Array>, Out<number>)';
/

create procedure doom_mle_bench_cached_tape(p_tape out blob)
as mle module doom_mle_bench
env doom_mle_bench_env
signature 'cachedProductionTape(Out<Uint8Array>)';
/
