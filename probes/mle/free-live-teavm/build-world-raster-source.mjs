#!/usr/bin/env node
import fs from 'node:fs';
import crypto from 'node:crypto';
import path from 'node:path';
import process from 'node:process';
import {execFileSync} from 'node:child_process';

const project = path.resolve(process.argv[2] ?? '.');
const repository = path.resolve(project, '..', '..', '..');
const packagePath = path.join('doomdb', 'mle', 'renderer');
const sourceRoot = path.join(project, 'src', 'main', 'java', packagePath);
const outputRoot = path.join(
  project, 'target', 'world-raster-src', packagePath);
const baselineCommit = '163e11d';
const baselinePath =
  'probes/mle/free-live-teavm/src/main/java/doomdb/mle/renderer/' +
  'FreeLiveRendererReachabilityProbe.java';
const baselineSha256 =
  'b8e21988b295c2a84c79e5145456f641b06a837a9b2f4058a3c4255736c518de';
const packBuilderPath = 'probes/mle/build-free-live-render-pack.mjs';
const packBuilderSha256 =
  'c86f91218a508aff59c544e9695ec0452f5b217b5bdcb83cc5c3e4e21eda4f37';
const engineName = 'FreeLiveWorldRasterCore.java';
const entryName = 'FreeLiveWorldRasterModule.java';
const liveRenderWidth = Number.parseInt(
  process.env.PMLE_FREE_LIVE_RENDER_WIDTH ?? '106', 10);
if (![64, 106].includes(liveRenderWidth)) {
  throw new Error('PMLE_FREE_LIVE_RENDER_WIDTH must be 64 or 106');
}
const lazyPlaneColumns =
  process.env.PMLE_FREE_LIVE_LAZY_PLANE_COLUMNS === 'YES';

function sha256(value) {
  return crypto.createHash('sha256').update(value).digest('hex');
}

function replaceExact(source, before, after, label) {
  const at = source.indexOf(before);
  if (at < 0 || source.indexOf(before, at + before.length) >= 0) {
    throw new Error(`world-raster transform ${label} must match exactly once`);
  }
  return source.replace(before, after);
}

function replaceCount(source, before, after, expected, label) {
  const matches = source.split(before).length - 1;
  if (matches !== expected) {
    throw new Error(
      `world-raster transform ${label} matched ${matches}, expected ${expected}`,
    );
  }
  return source.replaceAll(before, after);
}

function removeMatchingLines(source, expression, expected, label) {
  const matches = source.match(expression) ?? [];
  if (matches.length !== expected) {
    throw new Error(
      `world-raster transform ${label} matched ${matches.length}, expected ${expected}`,
    );
  }
  return source.replace(expression, '');
}

fs.mkdirSync(outputRoot, {recursive: true});
const baseline = execFileSync(
  'git', ['show', `${baselineCommit}:${baselinePath}`],
  {cwd: repository, encoding: 'utf8', maxBuffer: 4 * 1024 * 1024},
);
if (sha256(baseline) !== baselineSha256) {
  throw new Error('pinned world-raster baseline SHA-256 mismatch');
}
const originalName = 'FreeLiveRendererReachabilityProbe.java';
const originalPath = path.join(outputRoot, originalName);
fs.writeFileSync(originalPath, baseline);
execFileSync(
  'patch',
  ['--batch', '--forward', '-p1', '-i',
    path.join(project, 'patches', '0001-slim-coarse-vertical-raster.patch')],
  {cwd: outputRoot, stdio: 'inherit'},
);
let engine = fs.readFileSync(originalPath, 'utf8')
  .replaceAll('FreeLiveRendererReachabilityProbe', 'FreeLiveWorldRasterCore')
  .replace(/^import org\.teavm\.jso\.JSExport;\n/m, '')
  .replace(/^import org\.teavm\.jso\.JSByRef;\n/m, '')
  .replace(/^\s*@JSExport\n/gm, '')
  .replace(/^\s*@JSByRef\n/gm, '');
engine = replaceExact(
  engine,
  `  private static char[] sectorFloorAsset;
  private static char[] sectorCeilingAsset;
  private static char[] subsectorSector;
`,
  `  private static char[] sectorFloorAsset;
  private static char[] sectorCeilingAsset;
  private static char[] subsectorSector;
  private static char[] lineRightSide;
  private static char[] lineLeftSide;
  private static char[] runtimeWallToAsset;
  private static char[] runtimeFlatToAsset;
  private static char[] dynamicSideTop;
  private static char[] dynamicSideBottom;
  private static char[] dynamicSideMiddle;
  private static int[] dynamicSideTextureOffset;
  private static int[] dynamicSideRowOffset;
  private static short[] baselineSectorFloor;
  private static short[] baselineSectorCeiling;
  private static byte[] baselineSectorLight;
  private static char[] baselineSectorFloorAsset;
  private static char[] baselineSectorCeilingAsset;
  private static char[] baselineSideTop;
  private static char[] baselineSideBottom;
  private static char[] baselineSideMiddle;
  private static int[] baselineSideTextureOffset;
  private static int[] baselineSideRowOffset;
  private static int sideCount;
  private static boolean liveDynamicsActive;
`,
  'dynamic-world-fields',
);
engine = replaceExact(
  engine,
  `    if (u32(0) != MAGIC || u32(4) != 4 || u32(76) != pack.length) {
`,
  `    if (u32(0) != MAGIC || u32(4) != 5 || u32(76) != pack.length) {
`,
  'dynamic-pack-version',
);
engine = replaceExact(
  engine,
  `    sectorFloorAsset = chars(u32(280), sectorCount);
    sectorCeilingAsset = chars(u32(284), sectorCount);
    subsectorSector = chars(u32(296), subsectorCount);
    colormaps = bytes(u32(136), 8192);
`,
  `    sectorFloorAsset = chars(u32(280), sectorCount);
    sectorCeilingAsset = chars(u32(284), sectorCount);
    subsectorSector = chars(u32(296), subsectorCount);
    int live = u32(300);
    if (live < 304 || live > pack.length - 40
        || u32(live) != 0x314d4c44
        || u32(live + 8) != lineCount
        || u32(live + 36) != pack.length) {
      throw new IllegalStateException("DLM1 dynamic mapping mismatch");
    }
    sideCount = u32(live + 4);
    int runtimeWallCount = u32(live + 12);
    int runtimeFlatCount = u32(live + 16);
    lineRightSide = chars(u32(live + 20), lineCount);
    lineLeftSide = chars(u32(live + 24), lineCount);
    runtimeWallToAsset = chars(u32(live + 28), runtimeWallCount);
    runtimeFlatToAsset = chars(u32(live + 32), runtimeFlatCount);
    if (sideCount < 1 || runtimeWallCount < 1 || runtimeFlatCount < 1) {
      throw new IllegalStateException("DLM1 mapping cardinality mismatch");
    }
    dynamicSideTop = new char[sideCount];
    dynamicSideBottom = new char[sideCount];
    dynamicSideMiddle = new char[sideCount];
    dynamicSideTextureOffset = new int[sideCount];
    dynamicSideRowOffset = new int[sideCount];
    for (int line = 0; line < lineCount; line++) {
      int right = lineRightSide[line];
      if (right != 0xffff) {
        dynamicSideTop[right] = lineRightUpper[line];
        dynamicSideBottom[right] = lineRightLower[line];
        dynamicSideMiddle[right] = lineRightMiddle[line];
        dynamicSideTextureOffset[right] = lineXOffset[line];
        dynamicSideRowOffset[right] = lineYOffset[line];
      }
      int left = lineLeftSide[line];
      if (left != 0xffff) {
        dynamicSideTop[left] = lineLeftUpper[line];
        dynamicSideBottom[left] = lineLeftLower[line];
        dynamicSideMiddle[left] = lineLeftMiddle[line];
        dynamicSideTextureOffset[left] = lineLeftXOffset[line];
        dynamicSideRowOffset[left] = lineLeftYOffset[line];
      }
    }
    baselineSectorFloor = sectorFloor.clone();
    baselineSectorCeiling = sectorCeiling.clone();
    baselineSectorLight = sectorLight.clone();
    baselineSectorFloorAsset = sectorFloorAsset.clone();
    baselineSectorCeilingAsset = sectorCeilingAsset.clone();
    baselineSideTop = dynamicSideTop.clone();
    baselineSideBottom = dynamicSideBottom.clone();
    baselineSideMiddle = dynamicSideMiddle.clone();
    baselineSideTextureOffset = dynamicSideTextureOffset.clone();
    baselineSideRowOffset = dynamicSideRowOffset.clone();
    colormaps = bytes(u32(136), 8192);
`,
  'dynamic-pack-mappings',
);
engine = replaceExact(
  engine,
  '  private static final int LIVE_RENDER_WIDTH = 160;\n',
  `  private static final int LIVE_RENDER_WIDTH = ${liveRenderWidth};\n`,
  'retained-horizontal-width',
);
if (lazyPlaneColumns) {
  engine = replaceExact(
    engine,
    `  private static int[] planeStamp;
  private static int[] planeMinX;
`,
    `  private static int[] planeStamp;
  private static int[] planeColumnStamp;
  private static int[] planeMinX;
`,
    'lazy-plane-column-stamp-field',
  );
  engine = replaceExact(
    engine,
    `    planeStamp = new int[planeCount];
    planeMinX = new int[planeCount];
`,
    `    planeStamp = new int[planeCount];
    planeColumnStamp = new int[planeCount * LIVE_RENDER_WIDTH];
    planeMinX = new int[planeCount];
`,
    'lazy-plane-column-stamp-allocation',
  );
  engine = replaceExact(
    engine,
    `      for (int index = 0; index < planeStamp.length; index++) {
        planeStamp[index] = 0;
      }
      planeSerial = 1;
`,
    `      for (int index = 0; index < planeStamp.length; index++) {
        planeStamp[index] = 0;
      }
      java.util.Arrays.fill(planeColumnStamp, 0);
      planeSerial = 1;
`,
    'lazy-plane-column-stamp-wrap',
  );
  engine = replaceExact(
    engine,
    `      int base = plane * LIVE_RENDER_WIDTH;
      for (int column = 0; column < activeWidth; column++) {
        planeTop[base + column] = VIEW_HEIGHT;
        planeBottom[base + column] = -1;
      }
`,
    '',
    'lazy-plane-column-remove-full-clear',
  );
  engine = replaceExact(
    engine,
    `    int at = plane * LIVE_RENDER_WIDTH + x;
    planeTop[at] = (short) Math.min(planeTop[at], top);
    planeBottom[at] = (short) Math.max(planeBottom[at], bottom);
`,
    `    int at = plane * LIVE_RENDER_WIDTH + x;
    if (planeColumnStamp[at] != planeSerial) {
      planeColumnStamp[at] = planeSerial;
      planeTop[at] = VIEW_HEIGHT;
      planeBottom[at] = -1;
    }
    planeTop[at] = (short) Math.min(planeTop[at], top);
    planeBottom[at] = (short) Math.max(planeBottom[at], bottom);
`,
    'lazy-plane-column-initialize-on-write',
  );
  engine = replaceExact(
    engine,
    `        int top = x <= maximum ? planeTop[base + x] : VIEW_HEIGHT;
        int bottom = x <= maximum ? planeBottom[base + x] : -1;
`,
    `        boolean populated = x <= maximum
            && planeColumnStamp[base + x] == planeSerial;
        int top = populated ? planeTop[base + x] : VIEW_HEIGHT;
        int bottom = populated ? planeBottom[base + x] : -1;
`,
    'lazy-plane-column-read',
  );
  engine = replaceExact(
    engine,
    `        previousTop = x <= maximum ? planeTop[base + x] : VIEW_HEIGHT;
        previousBottom = x <= maximum ? planeBottom[base + x] : -1;
`,
    `        previousTop = populated ? planeTop[base + x] : VIEW_HEIGHT;
        previousBottom = populated ? planeBottom[base + x] : -1;
`,
    'lazy-plane-column-next',
  );
}
engine = replaceExact(
  engine,
  `    lightToBank = new int[32];
    for (int index = 0; index < lightToBank.length; index++) {
      lightToBank[index] = -1;
    }
    lightBankCount = 0;
    for (byte value : sectorLight) {
      int light = value & 255;
      int map = Math.max(0, Math.min(31, (255 - light) / 8));
      if (lightToBank[map] < 0) lightToBank[map] = lightBankCount++;
    }
`,
  `    lightToBank = new int[32];
    lightBankCount = 32;
    for (int index = 0; index < lightToBank.length; index++) {
      lightToBank[index] = index;
    }
`,
  'all-dynamic-light-banks',
);
engine = replaceExact(
  engine,
  `  private static int[] clipTop;
  private static int[] clipBottom;
`,
  `  private static int[] clipTop;
  private static int[] clipBottom;
  private static double[] solidDepth;
  private static double[] wallDepth;
  private static int[] wallDepthRangeStart;
  private static int[] wallDepthRangeEnd;
  private static int wallDepthRangeCount;
`,
  'retained-depth-fields',
);
engine = replaceExact(
  engine,
  `    clipTop = new int[WIDTH];
    clipBottom = new int[WIDTH];
`,
  `    clipTop = new int[WIDTH];
    clipBottom = new int[WIDTH];
    solidDepth = new double[LIVE_RENDER_WIDTH];
    wallDepth = new double[LIVE_RENDER_WIDTH * VIEW_HEIGHT];
    wallDepthRangeStart = new int[LIVE_RENDER_WIDTH * 2];
    wallDepthRangeEnd = new int[LIVE_RENDER_WIDTH * 2];
    java.util.Arrays.fill(wallDepth, Double.POSITIVE_INFINITY);
`,
  'retained-depth-allocation',
);
engine = replaceExact(
  engine,
  `    for (int x = 0; x < activeWidth; x++) {
      clipTop[x] = 0;
      clipBottom[x] = VIEW_HEIGHT - 1;
    }
`,
  `    for (int x = 0; x < activeWidth; x++) {
      clipTop[x] = 0;
      clipBottom[x] = VIEW_HEIGHT - 1;
      solidDepth[x] = Double.POSITIVE_INFINITY;
    }
    for (int range = 0; range < wallDepthRangeCount; range++) {
      java.util.Arrays.fill(
          wallDepth, wallDepthRangeStart[range], wallDepthRangeEnd[range],
          Double.POSITIVE_INFINITY);
    }
    wallDepthRangeCount = 0;
`,
  'retained-depth-reset',
);
engine = replaceExact(
  engine,
  `          if (far == 0xffff) {
            int texture = middle;
`,
  `          double signedWallDistance = numerator / current;
          double wallDistance = Math.abs(signedWallDistance);
          if (far == 0xffff) {
            solidDepth[x] = wallDistance;
            int texture = middle;
`,
  'retained-solid-depth',
);
engine = replaceCount(
  engine,
  '                  x, line, fromRight, numerator / current,\n',
  '                  x, line, fromRight, signedWallDistance,\n',
  2,
  'reuse-signed-wall-distance',
);
engine = replaceExact(
  engine,
  `        int middle = fromRight ? lineRightMiddle[line] : lineLeftMiddle[line];
        if (far != 0xffff && middle == 0xffff
            && sectorFloor[near] == sectorFloor[far]
            && sectorCeiling[near] == sectorCeiling[far]) continue;
        int upper = fromRight ? lineRightUpper[line] : lineLeftUpper[line];
        int lower = fromRight ? lineRightLower[line] : lineLeftLower[line];
`,
  `        int side = fromRight ? lineRightSide[line] : lineLeftSide[line];
        int yOffset = liveDynamicsActive && side != 0xffff
            ? dynamicSideRowOffset[side]
            : (fromRight ? lineYOffset[line] : lineLeftYOffset[line]);
        int middle = liveDynamicsActive && side != 0xffff
            ? dynamicSideMiddle[side]
            : (fromRight ? lineRightMiddle[line] : lineLeftMiddle[line]);
        if (far != 0xffff && middle == 0xffff
            && sectorFloor[near] == sectorFloor[far]
            && sectorCeiling[near] == sectorCeiling[far]) continue;
        int upper = liveDynamicsActive && side != 0xffff
            ? dynamicSideTop[side]
            : (fromRight ? lineRightUpper[line] : lineLeftUpper[line]);
        int lower = liveDynamicsActive && side != 0xffff
            ? dynamicSideBottom[side]
            : (fromRight ? lineRightLower[line] : lineLeftLower[line]);
`,
  'dynamic-sidedef-selection',
);
engine = replaceExact(
  engine,
  '                  fromRight ? lineYOffset[line] : lineLeftYOffset[line]);\n',
  '                  yOffset);\n',
  'dynamic-solid-wall-row-offset',
);
engine = replaceExact(
  engine,
  `                int yOffset = fromRight
                    ? lineYOffset[line] : lineLeftYOffset[line];
`,
  '',
  'dynamic-two-sided-wall-row-offset',
);
engine = replaceExact(
  engine,
  `                  clipTop[x], clipBottom[x], lightMap(near),
                  yOffset);
`,
  `                  clipTop[x], clipBottom[x], lightMap(near),
                  yOffset, wallDistance, false);
`,
  'solid-wall-depth-argument',
);
engine = replaceExact(
  engine,
  `                      clipTop[x], clipBottom[x], lightMap, yOffset);
`,
  `                      clipTop[x], clipBottom[x], lightMap, yOffset,
                      wallDistance, true);
`,
  'upper-portal-wall-depth-argument',
);
engine = replaceExact(
  engine,
  `                      nearBottom, clipTop[x], clipBottom[x], lightMap, yOffset);
`,
  `                      nearBottom, clipTop[x], clipBottom[x], lightMap, yOffset,
                      wallDistance, true);
`,
  'lower-portal-wall-depth-argument',
);
engine = replaceExact(
  engine,
  `  private static void drawWallSegment(
      int screenX, int texture, int textureX, int wallHeight,
      int projectedTop, int projectedBottom, int clipTopValue,
      int clipBottomValue, int lightMap, int verticalOffset) {
`,
  `  private static void drawWallSegment(
      int screenX, int texture, int textureX, int wallHeight,
      int projectedTop, int projectedBottom, int clipTopValue,
      int clipBottomValue, int lightMap, int verticalOffset, double depth,
      boolean recordPartialDepth) {
`,
  'partial-wall-depth-signature',
);
engine = replaceExact(
  engine,
  `    drawWallPixels(
        screenX, texture, textureX, wallHeight, projectedTop,
        drawTop, drawBottom, lightMap, verticalOffset);
  }
`,
  `    drawWallPixels(
        screenX, texture, textureX, wallHeight, projectedTop,
        drawTop, drawBottom, lightMap, verticalOffset);
    if (recordPartialDepth) {
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
  }
`,
  'partial-wall-depth-fill',
);
engine = replaceExact(
  engine,
  `    return (int) Math.floor(along)
        + (fromRight ? lineXOffset[line] : lineLeftXOffset[line]);
`,
  `    int side = fromRight ? lineRightSide[line] : lineLeftSide[line];
    int textureOffset = liveDynamicsActive && side != 0xffff
        ? dynamicSideTextureOffset[side]
        : (fromRight ? lineXOffset[line] : lineLeftXOffset[line]);
    return (int) Math.floor(along) + textureOffset;
`,
  'dynamic-wall-texture-offset',
);
engine = replaceExact(
  engine,
  `  public static int renderFrameCoarseVertical(int pose) {
    if (litTextures == null || litFlats == null) {
      throw new IllegalStateException("renderer textures are not finalized");
    }
    coarseVerticalRaster = true;
    try {
      return render(pose, true, true, true);
    } finally {
      coarseVerticalRaster = false;
    }
  }
`,
  `  public static int renderFrameCoarseVertical(int pose) {
    if (litTextures == null || litFlats == null) {
      throw new IllegalStateException("renderer textures are not finalized");
    }
    coarseVerticalRaster = true;
    try {
      return render(pose, true, true, true);
    } finally {
      coarseVerticalRaster = false;
    }
  }

  public static int resetDynamicWorldState() {
    if (baselineSectorFloor == null || baselineSideTop == null) {
      throw new IllegalStateException("dynamic world baseline is not finalized");
    }
    System.arraycopy(
        baselineSectorFloor, 0, sectorFloor, 0, baselineSectorFloor.length);
    System.arraycopy(
        baselineSectorCeiling, 0, sectorCeiling, 0,
        baselineSectorCeiling.length);
    System.arraycopy(
        baselineSectorLight, 0, sectorLight, 0, baselineSectorLight.length);
    System.arraycopy(
        baselineSectorFloorAsset, 0, sectorFloorAsset, 0,
        baselineSectorFloorAsset.length);
    System.arraycopy(
        baselineSectorCeilingAsset, 0, sectorCeilingAsset, 0,
        baselineSectorCeilingAsset.length);
    System.arraycopy(
        baselineSideTop, 0, dynamicSideTop, 0, baselineSideTop.length);
    System.arraycopy(
        baselineSideBottom, 0, dynamicSideBottom, 0,
        baselineSideBottom.length);
    System.arraycopy(
        baselineSideMiddle, 0, dynamicSideMiddle, 0,
        baselineSideMiddle.length);
    System.arraycopy(
        baselineSideTextureOffset, 0, dynamicSideTextureOffset, 0,
        baselineSideTextureOffset.length);
    System.arraycopy(
        baselineSideRowOffset, 0, dynamicSideRowOffset, 0,
        baselineSideRowOffset.length);
    return baselineSectorFloor.length + baselineSideTop.length;
  }

  public static int loadCompactSnapshot(Uint8Array snapshot) {
    validateCompactSnapshot(snapshot);
    loadCompactDynamics(snapshot);
    return snapshot.getLength();
  }

  public static int renderLoadedCompactFrameCoarse(Uint8Array snapshot) {
    validateCompactSnapshot(snapshot);
    int magic = snapshotI32(snapshot, 0);
    boolean world = magic == 0x324c5644
        || magic == 0x334c5644 || magic == 0x364c5644;
    int pose = world ? 36 : 12;
    coarseVerticalRaster = true;
    liveDynamicsActive = world;
    try {
      clearRetainedView();
      int checksum = renderView(
          snapshotI32(snapshot, pose),
          snapshotI32(snapshot, pose + 4),
          snapshotI32(snapshot, pose + 12),
          snapshotI32(snapshot, pose + 16),
          snapshotI32(snapshot, 8),
          true, true, true);
      expandRetainedColumns();
      return checksum;
    } finally {
      coarseVerticalRaster = false;
      liveDynamicsActive = false;
    }
  }

  private static void validateCompactSnapshot(Uint8Array snapshot) {
    if (litTextures == null || litFlats == null) {
      throw new IllegalStateException("renderer textures are not finalized");
    }
    if (snapshot == null || snapshotI32(snapshot, 8) < 0) {
      throw new IllegalArgumentException("invalid retained world snapshot");
    }
    int magic = snapshotI32(snapshot, 0);
    if (magic == 0x34505644) {
      if (snapshot.getLength() != 44 || snapshotI32(snapshot, 4) != 4) {
        throw new IllegalArgumentException("invalid DVP4 retained pose");
      }
      return;
    }
    int sectors = snapshotI32(snapshot, 16);
    int mobjs = snapshotI32(snapshot, 20);
    int sectorOffset = snapshotI32(snapshot, 24);
    int mobjOffset = snapshotI32(snapshot, 28);
    int length = snapshotI32(snapshot, 32);
    int sides = snapshotI32(snapshot, 192);
    int sideOffset = snapshotI32(snapshot, 196);
    boolean fullSides = magic == 0x324c5644
        && snapshotI32(snapshot, 4) == 2 && sides == sideCount;
    boolean sectorsOnly = magic == 0x334c5644
        && snapshotI32(snapshot, 4) == 3 && sides == 0;
    boolean dirtyWorld = magic == 0x364c5644
        && snapshotI32(snapshot, 4) == 6
        && sectors >= 0 && sectors <= sectorCount
        && sides >= 0 && sides <= sideCount;
    int sectorRecordBytes = dirtyWorld ? 18 : 16;
    int sideRecordBytes = dirtyWorld ? 18 : 8;
    if ((!fullSides && !sectorsOnly && !dirtyWorld)
        || (!dirtyWorld && sectors != sectorCount) || mobjs != 0
        || sectorOffset != 208
        || snapshotI32(snapshot, 200) != sideRecordBytes
        || snapshotI32(snapshot, 204)
            != (dirtyWorld ? sectorRecordBytes : sectorOffset)
        || sideOffset != sectorOffset + sectors * sectorRecordBytes
        || mobjOffset != sideOffset + sides * sideRecordBytes
        || length != mobjOffset || length != snapshot.getLength()) {
      throw new IllegalArgumentException("invalid DVL2 retained world");
    }
  }

  private static void loadCompactDynamics(Uint8Array snapshot) {
    int magic = snapshotI32(snapshot, 0);
    if (magic != 0x324c5644
        && magic != 0x334c5644 && magic != 0x364c5644) return;
    int sectors = snapshotI32(snapshot, 16);
    int sectorOffset = snapshotI32(snapshot, 24);
    int sides = snapshotI32(snapshot, 192);
    int sideOffset = snapshotI32(snapshot, 196);
    for (int sector = 0; sector < sectors; sector++) {
      int at = sectorOffset + sector * (magic == 0x364c5644 ? 18 : 16);
      int target = magic == 0x364c5644 ? snapshotU16(snapshot, at) : sector;
      int values = magic == 0x364c5644 ? at + 2 : at;
      if (target < 0 || target >= sectorCount) {
        throw new IllegalArgumentException("invalid DVL6 sector index");
      }
      sectorFloor[target] =
          (short) (snapshotI32(snapshot, values) >> 16);
      sectorCeiling[target] =
          (short) (snapshotI32(snapshot, values + 4) >> 16);
      sectorLight[target] = (byte) snapshotI16(snapshot, values + 8);
      sectorFloorAsset[target] = translatedFlat(
          snapshotU16(snapshot, values + 10), sectorFloorAsset[target]);
      sectorCeilingAsset[target] = translatedFlat(
          snapshotU16(snapshot, values + 12), sectorCeilingAsset[target]);
    }
    if (magic == 0x324c5644) {
      for (int side = 0; side < sides; side++) {
        int at = sideOffset + side * 8;
        dynamicSideTop[side] = translatedWall(snapshotU16(snapshot, at));
        dynamicSideBottom[side] =
            translatedWall(snapshotU16(snapshot, at + 2));
        dynamicSideMiddle[side] =
            translatedWall(snapshotU16(snapshot, at + 4));
      }
    } else if (magic == 0x364c5644) {
      for (int dirty = 0; dirty < sides; dirty++) {
        int at = sideOffset + dirty * 18;
        int side = snapshotU16(snapshot, at);
        if (side < 0 || side >= sideCount) {
          throw new IllegalArgumentException("invalid DVL6 side index");
        }
        dynamicSideTop[side] =
            translatedWall(snapshotU16(snapshot, at + 2));
        dynamicSideBottom[side] =
            translatedWall(snapshotU16(snapshot, at + 4));
        dynamicSideMiddle[side] =
            translatedWall(snapshotU16(snapshot, at + 6));
        dynamicSideTextureOffset[side] = snapshotI32(snapshot, at + 10) >> 16;
        dynamicSideRowOffset[side] = snapshotI32(snapshot, at + 14) >> 16;
      }
    }
  }

  private static int snapshotI16(Uint8Array snapshot, int offset) {
    int value = snapshotU16(snapshot, offset);
    return value >= 32768 ? value - 65536 : value;
  }

  private static int snapshotU16(Uint8Array snapshot, int offset) {
    return (snapshot.get(offset) & 255)
        | ((snapshot.get(offset + 1) & 255) << 8);
  }

  private static char translatedWall(int runtimeTexture) {
    if (runtimeTexture == 0 || runtimeTexture >= runtimeWallToAsset.length) {
      return 0xffff;
    }
    return runtimeWallToAsset[runtimeTexture];
  }

  private static char translatedFlat(int runtimeLump, char fallback) {
    if (runtimeLump >= runtimeFlatToAsset.length) return fallback;
    char asset = runtimeFlatToAsset[runtimeLump];
    return asset == 0xffff ? fallback : asset;
  }

  private static void expandRetainedColumns() {
    // Expand each interpreted sample with native bulk copies. The tail loop
    // covers widths such as 106 whose integer scale leaves two output columns.
    int scale = WIDTH / LIVE_RENDER_WIDTH;
    for (int column = 0; column < LIVE_RENDER_WIDTH; column++) {
      int source = column * scale * FRAME_HEIGHT;
      for (int copy = 1; copy < scale; copy++) {
        System.arraycopy(
            frame, source, frame, source + copy * FRAME_HEIGHT, FRAME_HEIGHT);
      }
    }
    int source = (LIVE_RENDER_WIDTH - 1) * scale * FRAME_HEIGHT;
    for (int column = LIVE_RENDER_WIDTH * scale; column < WIDTH; column++) {
      System.arraycopy(
          frame, source, frame, column * FRAME_HEIGHT, FRAME_HEIGHT);
    }
  }

  private static void clearRetainedView() {
    int scale = WIDTH / LIVE_RENDER_WIDTH;
    for (int column = 0; column < LIVE_RENDER_WIDTH; column++) {
      int target = column * scale * FRAME_HEIGHT;
      System.arraycopy(
          backgroundColumn, 0, frame, target, backgroundColumn.length);
    }
  }

  public static double[] solidDepthByRef() {
    return solidDepth;
  }

  public static double[] wallDepthByRef() {
    return wallDepth;
  }
`,
  'retained-render-entry',
);
engine = replaceExact(
  engine,
  `  private static int lightMap(int sector) {
    return Math.max(0, Math.min(31, (255 - (sectorLight[sector] & 255)) / 8));
  }
`,
  `  private static int lightMap(int sector) {
    // The unsigned light is always 0..255, so the quotient is already 0..31.
    // Avoid interpreted min/max and division in every wall/plane light lookup.
    return (255 - (sectorLight[sector] & 255)) >>> 3;
  }
`,
  'exact-light-map-shift',
);
engine = removeMatchingLines(
  engine,
  /^\s*frame\[[^\n]*FRAME_HEIGHT[^\n]*\] = [^\n]+;\n/gm,
  18,
  'single-column-interpreted-raster',
);
if (engine.includes('@JSExport') || engine.includes('@JSByRef')) {
  throw new Error('world-raster source still contains delegate exports');
}
fs.writeFileSync(path.join(outputRoot, engineName), engine);
fs.unlinkSync(originalPath);
fs.copyFileSync(path.join(sourceRoot, entryName), path.join(outputRoot, entryName));
const packBuilder = execFileSync(
  'git', ['show', `${baselineCommit}:${packBuilderPath}`],
  {cwd: repository, encoding: 'utf8', maxBuffer: 4 * 1024 * 1024},
);
if (sha256(packBuilder) !== packBuilderSha256) {
  throw new Error('pinned world-raster pack builder SHA-256 mismatch');
}
const toolRoot = path.join(project, 'target', 'world-raster-tools');
fs.mkdirSync(toolRoot, {recursive: true});
fs.writeFileSync(path.join(toolRoot, 'build-free-live-render-pack.mjs'), packBuilder);
process.stdout.write(
  'PMLE_FREE_LIVE_WORLD_SOURCE|PASS' +
  `|baseline_commit=${baselineCommit}|baseline_sha256=${baselineSha256}` +
  `|pack_builder_sha256=${packBuilderSha256}` +
  `|engine_bytes=${Buffer.byteLength(engine)}` +
  `|engine_sha256=${sha256(engine)}\n`,
);
