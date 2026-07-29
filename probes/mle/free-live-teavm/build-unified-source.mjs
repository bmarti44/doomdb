#!/usr/bin/env node
import crypto from 'node:crypto';
import fs from 'node:fs';
import path from 'node:path';
import process from 'node:process';

const project = path.resolve(process.argv[2] ?? '.');
const packagePath = path.join('doomdb', 'mle', 'renderer');
const output = path.join(project, 'target', 'unified-src', packagePath);
const world = path.join(project, 'target', 'world-raster-src', packagePath);
const compositor = path.join(
  project, 'target', 'compositor-src', packagePath);
const source = path.join(project, 'src', 'main', 'java', packagePath);
const liveRenderWidth = Number.parseInt(
  process.env.PMLE_FREE_LIVE_RENDER_WIDTH ?? '106', 10);
if (![64, 106, 160].includes(liveRenderWidth)) {
  throw new Error('PMLE_FREE_LIVE_RENDER_WIDTH must be 64, 106, or 160');
}
const livePixelScale = Math.floor(320 / liveRenderWidth);
const livePlaneMode =
  process.env.PMLE_FREE_LIVE_PLANE_MODE ?? 'VISPLANE';
if (!['VISPLANE', 'VIEW_SECTOR'].includes(livePlaneMode)) {
  throw new Error(
    'PMLE_FREE_LIVE_PLANE_MODE must be VISPLANE or VIEW_SECTOR');
}

function copy(name, from) {
  const input = path.join(from, name);
  const bytes = fs.readFileSync(input);
  fs.writeFileSync(path.join(output, name), bytes);
  return crypto.createHash('sha256').update(bytes).digest('hex');
}

function replaceExact(sourceText, before, after, label) {
  const at = sourceText.indexOf(before);
  if (at < 0 || sourceText.indexOf(before, at + before.length) >= 0) {
    throw new Error(`unified transform ${label} must match exactly once`);
  }
  return sourceText.replace(before, after);
}

function replaceExactCount(sourceText, before, after, expected, label) {
  const matches = sourceText.split(before).length - 1;
  if (matches !== expected) {
    throw new Error(
      `unified transform ${label} matched ${matches}, expected ${expected}`,
    );
  }
  return sourceText.replaceAll(before, after);
}

function removeMatchingLines(sourceText, expression, expected, label) {
  const matches = sourceText.match(expression) ?? [];
  if (matches.length !== expected) {
    throw new Error(
      `unified transform ${label} matched ${matches.length}, expected ${expected}`,
    );
  }
  return sourceText.replace(expression, '');
}

fs.rmSync(path.join(project, 'target', 'unified-src'), {
  recursive: true, force: true,
});
fs.mkdirSync(output, {recursive: true});
let worldSource = fs.readFileSync(
  path.join(world, 'FreeLiveWorldRasterCore.java'), 'utf8');
worldSource = replaceExact(
  worldSource,
  `            if (raster || captureCommands || captureResolvedCommands
                || captureNativeTape) {
`,
  `            if (raster) {
`,
  'live-solid-wall-raster-only',
);
worldSource = replaceExact(
  worldSource,
  `            if ((raster || captureCommands || captureResolvedCommands
                || captureNativeTape) && !clipOnly) {
`,
  `            if (raster && !clipOnly) {
`,
  'live-two-sided-wall-raster-only',
);
worldSource = replaceExact(
  worldSource,
  `    if (captureCommands) {
      appendCommand(
          screenX, texture, textureX, wallHeight, projectedTop,
          drawTop, drawBottom, lightMap, verticalOffset);
      return;
    }
    if (captureResolvedCommands) {
      appendResolvedCommand(
          screenX, texture, textureX, wallHeight, projectedTop,
          drawTop, drawBottom, lightMap, verticalOffset);
      return;
    }
    if (captureNativeTape) {
      appendNativeTape(
          screenX, texture, textureX, wallHeight, projectedTop,
          drawTop, drawBottom, lightMap, verticalOffset);
      return;
    }
    drawWallPixels(
`,
  `    drawWallPixels(
`,
  'live-wall-pixel-direct-dispatch',
);
worldSource = removeMatchingLines(
  worldSource,
  /^\s*rasterPixelWrites = 0;\n/gm,
  1,
  'live-raster-counter-reset',
);
worldSource = removeMatchingLines(
  worldSource,
  /^\s*rasterPixelWrites \+= [^\n]+;\n/gm,
  4,
  'live-raster-counter-updates',
);
worldSource = replaceExact(
  worldSource,
  `    activeWidth = raster ? LIVE_RENDER_WIDTH : WIDTH;
    pixelScale = WIDTH / activeWidth;
    int viewSector = raster && planes
        ? pointSector(playerX, playerY) : -1;
    boolean recordVisplanes = raster && planes && walls;
    if (recordVisplanes) {
      startPlaneFrame();
    } else if (raster && planes) {
      drawPlaneBackground(
          viewSector, playerX, playerY, viewZ, directionX, directionY);
    }
    if (!walls) {
      return raster
          ? (frame[sample % PIXELS] & 255)
              | ((frame[(sample * 997) % PIXELS] & 255) << 8)
          : 0;
    }
`,
  livePlaneMode === 'VISPLANE'
    ? `    activeWidth = LIVE_RENDER_WIDTH;
    pixelScale = WIDTH / LIVE_RENDER_WIDTH;
    startPlaneFrame();
`
    : `    activeWidth = LIVE_RENDER_WIDTH;
    pixelScale = WIDTH / LIVE_RENDER_WIDTH;
    int viewSector = pointSector(playerX, playerY);
    drawPlaneBackground(
        viewSector, playerX, playerY, viewZ, directionX, directionY);
`,
  'live-render-view-constants',
);
worldSource = replaceExactCount(
  worldSource,
  '            if (recordVisplanes) {\n',
  livePlaneMode === 'VISPLANE'
    ? '            {\n'
    : '            if (false) {\n',
  2,
  'live-record-plane-ranges',
);
worldSource = replaceExact(
  worldSource,
  `    if (recordVisplanes) {
      drawRecordedPlanes(
          playerX, playerY, viewZ, directionX, directionY);
    }
    if (raster) {
      checksum ^= (frame[sample % PIXELS] & 255)
          | ((frame[(sample * 997) % PIXELS] & 255) << 8);
    }
`,
  livePlaneMode === 'VISPLANE'
    ? `    drawRecordedPlanes(
        playerX, playerY, viewZ, directionX, directionY);
    checksum ^= (frame[sample % PIXELS] & 255)
        | ((frame[(sample * 997) % PIXELS] & 255) << 8);
`
    : `    checksum ^= (frame[sample % PIXELS] & 255)
        | ((frame[(sample * 997) % PIXELS] & 255) << 8);
`,
  'live-render-view-tail',
);
worldSource = replaceExact(
  worldSource,
  `  private static int[] wallDepthRangeStart;
  private static int[] wallDepthRangeEnd;
  private static int wallDepthRangeCount;
`,
  `  private static int[] partialDepthHead;
  private static int[] partialDepthStart;
  private static int[] partialDepthEnd;
  private static int[] partialDepthNext;
  private static double[] partialDepthValue;
  private static int partialDepthCount;
`,
  'live-compact-partial-depth-fields',
);
worldSource = replaceExact(
  worldSource,
  `    wallDepthRangeStart = new int[LIVE_RENDER_WIDTH * 2];
    wallDepthRangeEnd = new int[LIVE_RENDER_WIDTH * 2];
    java.util.Arrays.fill(wallDepth, Double.POSITIVE_INFINITY);
`,
  `    partialDepthHead = new int[LIVE_RENDER_WIDTH];
    partialDepthStart = new int[LIVE_RENDER_WIDTH * 2];
    partialDepthEnd = new int[LIVE_RENDER_WIDTH * 2];
    partialDepthNext = new int[LIVE_RENDER_WIDTH * 2];
    partialDepthValue = new double[LIVE_RENDER_WIDTH * 2];
    java.util.Arrays.fill(wallDepth, Double.POSITIVE_INFINITY);
`,
  'live-compact-partial-depth-allocation',
);
worldSource = replaceExact(
  worldSource,
  `      solidDepth[x] = Double.POSITIVE_INFINITY;
    }
    for (int range = 0; range < wallDepthRangeCount; range++) {
      java.util.Arrays.fill(
          wallDepth, wallDepthRangeStart[range], wallDepthRangeEnd[range],
          Double.POSITIVE_INFINITY);
    }
    wallDepthRangeCount = 0;
`,
  `      solidDepth[x] = Double.POSITIVE_INFINITY;
      partialDepthHead[x] = -1;
    }
    partialDepthCount = 0;
`,
  'live-compact-partial-depth-reset',
);
worldSource = replaceExact(
  worldSource,
  `    if (recordPartialDepth) {
      if (wallDepthRangeCount == wallDepthRangeStart.length) {
        wallDepthRangeStart = java.util.Arrays.copyOf(
            wallDepthRangeStart, wallDepthRangeCount * 2);
        wallDepthRangeEnd = java.util.Arrays.copyOf(
            wallDepthRangeEnd, wallDepthRangeCount * 2);
      }
      int start = screenX * VIEW_HEIGHT + drawTop;
      int end = screenX * VIEW_HEIGHT + drawBottom + 1;
      wallDepthRangeStart[wallDepthRangeCount] = start;
      wallDepthRangeEnd[wallDepthRangeCount] = end;
      wallDepthRangeCount++;
      java.util.Arrays.fill(wallDepth, start, end, depth);
    }
`,
  `    if (recordPartialDepth) {
      if (partialDepthCount == partialDepthStart.length) {
        partialDepthStart = java.util.Arrays.copyOf(
            partialDepthStart, partialDepthCount * 2);
        partialDepthEnd = java.util.Arrays.copyOf(
            partialDepthEnd, partialDepthCount * 2);
        partialDepthNext = java.util.Arrays.copyOf(
            partialDepthNext, partialDepthCount * 2);
        partialDepthValue = java.util.Arrays.copyOf(
            partialDepthValue, partialDepthCount * 2);
      }
      int range = partialDepthCount++;
      partialDepthStart[range] = drawTop;
      partialDepthEnd[range] = drawBottom + 1;
      partialDepthValue[range] = depth;
      partialDepthNext[range] = partialDepthHead[screenX];
      partialDepthHead[screenX] = range;
    }
`,
  'live-compact-partial-depth-record',
);
worldSource = replaceExact(
  worldSource,
  `  public static double[] wallDepthByRef() {
    return wallDepth;
  }
`,
  `  public static double[] wallDepthByRef() {
    return wallDepth;
  }

  public static int[] partialDepthHeadByRef() {
    return partialDepthHead;
  }

  public static int[] partialDepthStartByRef() {
    return partialDepthStart;
  }

  public static int[] partialDepthEndByRef() {
    return partialDepthEnd;
  }

  public static int[] partialDepthNextByRef() {
    return partialDepthNext;
  }

  public static double[] partialDepthValueByRef() {
    return partialDepthValue;
  }
`,
  'live-compact-partial-depth-exports',
);
worldSource = replaceExactCount(
  worldSource,
  '            if (raster) {\n',
  '            {\n',
  1,
  'live-solid-wall-direct',
);
worldSource = replaceExact(
  worldSource,
  '            if (raster && !clipOnly) {\n',
  '            if (!clipOnly) {\n',
  'live-two-sided-wall-direct',
);
fs.writeFileSync(
  path.join(output, 'FreeLiveWorldRasterCore.java'), worldSource);
const worldSha =
  crypto.createHash('sha256').update(worldSource).digest('hex');
let compositorSource = fs.readFileSync(
  path.join(compositor, 'FreeLiveCompositorCore.java'), 'utf8');
compositorSource = replaceExact(
  compositorSource,
  `  private static double[] wallDepth;
`,
  `  private static double[] wallDepth;
  private static int[] partialDepthHead;
  private static int[] partialDepthStart;
  private static int[] partialDepthEnd;
  private static int[] partialDepthNext;
  private static double[] partialDepthValue;
`,
  'live-compositor-partial-depth-fields',
);
compositorSource = replaceExact(
  compositorSource,
  `  public static int bindJavaTargets(
      byte[] targetFrame, double[] targetSolidDepth,
      double[] targetWallDepth) {
`,
  `  public static int bindJavaTargets(
      byte[] targetFrame, double[] targetSolidDepth,
      double[] targetWallDepth, int[] targetPartialDepthHead,
      int[] targetPartialDepthStart, int[] targetPartialDepthEnd,
      int[] targetPartialDepthNext, double[] targetPartialDepthValue) {
`,
  'live-compositor-partial-depth-bind-signature',
);
compositorSource = replaceExact(
  compositorSource,
  `        || targetWallDepth == null
        || targetWallDepth.length != LIVE_RENDER_WIDTH * VIEW_HEIGHT) {
`,
  `        || targetWallDepth == null
        || targetWallDepth.length != LIVE_RENDER_WIDTH * VIEW_HEIGHT
        || targetPartialDepthHead == null
        || targetPartialDepthHead.length != LIVE_RENDER_WIDTH
        || targetPartialDepthStart == null || targetPartialDepthEnd == null
        || targetPartialDepthNext == null || targetPartialDepthValue == null
        || targetPartialDepthStart.length != targetPartialDepthEnd.length
        || targetPartialDepthStart.length != targetPartialDepthNext.length
        || targetPartialDepthStart.length != targetPartialDepthValue.length) {
`,
  'live-compositor-partial-depth-bind-validation',
);
compositorSource = replaceExact(
  compositorSource,
  `    wallDepth = targetWallDepth;
    return targetFrame.length;
`,
  `    wallDepth = targetWallDepth;
    partialDepthHead = targetPartialDepthHead;
    partialDepthStart = targetPartialDepthStart;
    partialDepthEnd = targetPartialDepthEnd;
    partialDepthNext = targetPartialDepthNext;
    partialDepthValue = targetPartialDepthValue;
    return targetFrame.length;
`,
  'live-compositor-partial-depth-bind',
);
compositorSource = replaceExact(
  compositorSource,
  `        || frame == null || solidDepth == null || wallDepth == null) {
`,
  `        || frame == null || solidDepth == null || wallDepth == null
        || partialDepthHead == null || partialDepthStart == null
        || partialDepthEnd == null || partialDepthNext == null
        || partialDepthValue == null) {
`,
  'live-compositor-partial-depth-ready',
);
compositorSource = replaceExact(
  compositorSource,
  `      int outputX = x * ${livePixelScale};
      for (int y = Math.max(0, top);
           y <= Math.min(VIEW_HEIGHT - 1, bottom); y++) {
        if (depth >= wallDepth[x * VIEW_HEIGHT + y]) continue;
        int sourceY = (y - top) * height / screenHeight;
        int encoded = spriteTexels[
            sourceBase + sourceY * width + sourceX];
        if (encoded == 0) continue;
`,
  `      int outputX = x * ${livePixelScale};
      int firstPartialDepth = partialDepthHead[x];
      for (int y = Math.max(0, top);
           y <= Math.min(VIEW_HEIGHT - 1, bottom); y++) {
        int sourceY = (y - top) * height / screenHeight;
        int encoded = spriteTexels[
            sourceBase + sourceY * width + sourceX];
        if (encoded == 0) continue;
        boolean occluded = false;
        for (int range = firstPartialDepth;
             range >= 0; range = partialDepthNext[range]) {
          if (y >= partialDepthStart[range] && y < partialDepthEnd[range]
              && depth >= partialDepthValue[range]) {
            occluded = true;
            break;
          }
        }
        if (occluded) continue;
`,
  'live-compositor-compact-partial-depth-test',
);
fs.writeFileSync(
  path.join(output, 'FreeLiveCompositorCore.java'), compositorSource);
const compositorSha =
  crypto.createHash('sha256').update(compositorSource).digest('hex');
let entrySource = fs.readFileSync(
  path.join(source, 'FreeLiveUnifiedRendererModule.java'), 'utf8');
entrySource = replaceExact(
  entrySource,
  `        FreeLiveWorldRasterCore.solidDepthByRef(),
        FreeLiveWorldRasterCore.wallDepthByRef());
`,
  `        FreeLiveWorldRasterCore.solidDepthByRef(),
        FreeLiveWorldRasterCore.wallDepthByRef(),
        FreeLiveWorldRasterCore.partialDepthHeadByRef(),
        FreeLiveWorldRasterCore.partialDepthStartByRef(),
        FreeLiveWorldRasterCore.partialDepthEndByRef(),
        FreeLiveWorldRasterCore.partialDepthNextByRef(),
        FreeLiveWorldRasterCore.partialDepthValueByRef());
`,
  'live-entry-compact-partial-depth-bind',
);
entrySource = replaceExact(
  entrySource,
  `  @JSExport
  @JSByRef
  public static double[] wallDepthByRef() {
    return FreeLiveWorldRasterCore.wallDepthByRef();
  }
`,
  `  @JSExport
  @JSByRef
  public static double[] wallDepthByRef() {
    return FreeLiveWorldRasterCore.wallDepthByRef();
  }

  /** Diagnostic coverage only; not used by the production frame path. */
  @JSExport
  public static int partialDepthPixelCount() {
    int total = 0;
    int[] head = FreeLiveWorldRasterCore.partialDepthHeadByRef();
    int[] start = FreeLiveWorldRasterCore.partialDepthStartByRef();
    int[] end = FreeLiveWorldRasterCore.partialDepthEndByRef();
    int[] next = FreeLiveWorldRasterCore.partialDepthNextByRef();
    for (int x = 0; x < head.length; x++) {
      for (int range = head[x]; range >= 0; range = next[range]) {
        total += end[range] - start[range];
      }
    }
    return total;
  }
`,
  'live-entry-compact-partial-depth-diagnostic',
);
fs.writeFileSync(
  path.join(output, 'FreeLiveUnifiedRendererModule.java'), entrySource);
const entrySha =
  crypto.createHash('sha256').update(entrySource).digest('hex');
process.stdout.write(
  'PMLE_FREE_LIVE_UNIFIED_SOURCE|PASS' +
  `|world_sha256=${worldSha}` +
  `|compositor_sha256=${compositorSha}` +
  `|entry_sha256=${entrySha}` +
  `|plane_mode=${livePlaneMode}\n`,
);
