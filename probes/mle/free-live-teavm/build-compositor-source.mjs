#!/usr/bin/env node
import crypto from 'node:crypto';
import fs from 'node:fs';
import path from 'node:path';
import process from 'node:process';

const project = path.resolve(process.argv[2] ?? '.');
const packagePath = path.join('doomdb', 'mle', 'renderer');
const sourceRoot = path.join(project, 'src', 'main', 'java', packagePath);
const outputRoot = path.join(
  project, 'target', 'compositor-src', packagePath);
const sourcePath = path.join(
  sourceRoot, 'FreeLiveRendererReachabilityProbe.java');
const source = fs.readFileSync(sourcePath, 'utf8');
const liveRenderWidth = Number.parseInt(
  process.env.PMLE_FREE_LIVE_RENDER_WIDTH ?? '106', 10);
if (![64, 106].includes(liveRenderWidth)) {
  throw new Error('PMLE_FREE_LIVE_RENDER_WIDTH must be 64 or 106');
}
const livePixelScale = Math.floor(320 / liveRenderWidth);
const liveSpriteWrites = Array.from(
  {length: livePixelScale},
  (_, copy) =>
    `        frame[(outputX + ${copy}) * FRAME_HEIGHT + y] = pixel;`,
).join('\n');

function sha256(value) {
  return crypto.createHash('sha256').update(value).digest('hex');
}

function replaceExact(value, before, after, label) {
  const at = value.indexOf(before);
  if (at < 0 || value.indexOf(before, at + before.length) >= 0) {
    throw new Error(`compositor transform ${label} must match exactly once`);
  }
  return value.replace(before, after);
}

fs.mkdirSync(outputRoot, {recursive: true});
let core = source
  .replaceAll(
    'FreeLiveRendererReachabilityProbe', 'FreeLiveCompositorCore')
  .replace(/^import org\.teavm\.jso\.JSExport;\n/m, '')
  .replace(/^import org\.teavm\.jso\.JSByRef;\n/m, '')
  .replace(/^\s*@JSExport\n/gm, '')
  .replace(/^\s*@JSByRef\n/gm, '');
core = replaceExact(
  core,
  '  private static final int LIVE_RENDER_WIDTH = 160;\n',
  `  private static final int LIVE_RENDER_WIDTH = ${liveRenderWidth};\n`,
  'width',
);
core = replaceExact(
  core,
  `  private static char[] spriteTexels;
`,
  `  private static char[] spriteTexels;
  private static int[] brightAssetRunStart;
  private static int[] brightAssetRunEnd;
  private static int[] brightRunPixelStart;
  private static short[] brightRunX;
  private static short[] brightRunY;
  private static short[] brightRunLength;
  private static byte[] brightRunPixels;
  private static int brightRunCount;
  private static int brightPixelCount;
`,
  'bright-sprite-run-fields',
);
core = replaceExact(
  core,
  `  private static boolean statusBarInitialized;
`,
  `  private static boolean statusBarInitialized;
  private static int[] lastStatusState = new int[10];
`,
  'retained-status-state-field',
);
core = replaceExact(
  core,
  `    spriteTexels = decodeTransparentTexels(
        encodedSpriteTextures, spriteTextureElements);
    int length = encodedSpriteTextures.length;
`,
  `    spriteTexels = decodeTransparentTexels(
        encodedSpriteTextures, spriteTextureElements);
    buildBrightSpriteRuns();
    int length = encodedSpriteTextures.length;
`,
  'bright-sprite-run-build',
);
core = replaceExact(
  core,
  '    int outputX = x * 2;\n',
  `    int outputX = x * ${livePixelScale};\n`,
  'sprite-output-width',
);
core = replaceExact(
  core,
  `        frame[outputX * FRAME_HEIGHT + y] = pixel;
        frame[(outputX + 1) * FRAME_HEIGHT + y] = pixel;
`,
  `${liveSpriteWrites}
`,
  'sprite-output-pixels',
);
core = replaceExact(
  core,
  `  public static int renderWorldSnapshot(Uint8Array snapshot) {
`,
  `  public static int composeCompactSnapshot(Uint8Array snapshot) {
    validateCompositorSnapshot(snapshot);
    drawWorldSprites(snapshot, 208, snapshotI32(snapshot, 20));
    drawPlayerSprites(snapshot);
    drawStatusBar(snapshot);
    return (frame[snapshotI32(snapshot, 8) % PIXELS] & 255)
        | ((frame[(snapshotI32(snapshot, 8) * 997) % PIXELS] & 255) << 8);
  }

  public static int composeWorldSpritesStage(Uint8Array snapshot) {
    validateCompositorSnapshot(snapshot);
    drawWorldSprites(snapshot, 208, snapshotI32(snapshot, 20));
    return frame[0] & 255;
  }

  public static int composeWeaponStage(Uint8Array snapshot) {
    validateCompositorSnapshot(snapshot);
    drawPlayerSprites(snapshot);
    return frame[VIEW_HEIGHT - 1] & 255;
  }

  public static int composeStatusStage(Uint8Array snapshot) {
    validateCompositorSnapshot(snapshot);
    drawStatusBar(snapshot);
    return frame[PIXELS - 1] & 255;
  }

  public static int resetPresentationState() {
    statusBarInitialized = false;
    for (int index = 0; index < lastStatusState.length; index++) {
      lastStatusState[index] = 0;
    }
    return lastStatusState.length;
  }

  public static int bindJavaTargets(
      byte[] targetFrame, double[] targetSolidDepth,
      double[] targetWallDepth) {
    if (targetFrame == null || targetFrame.length != PIXELS
        || targetSolidDepth == null
        || targetSolidDepth.length != LIVE_RENDER_WIDTH
        || targetWallDepth == null
        || targetWallDepth.length != LIVE_RENDER_WIDTH * VIEW_HEIGHT) {
      throw new IllegalArgumentException("invalid Java compositor targets");
    }
    if (frame != targetFrame) {
      statusBarInitialized = false;
    }
    frame = targetFrame;
    solidDepth = targetSolidDepth;
    wallDepth = targetWallDepth;
    return targetFrame.length;
  }

  private static void validateCompositorSnapshot(Uint8Array snapshot) {
    if (spriteTexels == null || uiTexels == null
        || frame == null || solidDepth == null || wallDepth == null) {
      throw new IllegalStateException("compositor assets are not finalized");
    }
    int mobjs = snapshot == null || snapshot.getLength() < 208
        ? -1 : snapshotI32(snapshot, 20);
    if (snapshot == null || snapshot.getLength() < 208
        || snapshotI32(snapshot, 0) != 0x344c5644
        || snapshotI32(snapshot, 4) != 4
        || snapshotI32(snapshot, 16) != 0
        || snapshotI32(snapshot, 24) != 208
        || snapshotI32(snapshot, 28) != 208
        || snapshotI32(snapshot, 192) != 0
        || mobjs < 0 || mobjs > worldSpriteOrder.length
        || snapshotI32(snapshot, 32) != 208 + mobjs * 24
        || snapshotI32(snapshot, 32) != snapshot.getLength()) {
      throw new IllegalArgumentException("invalid DVC4 compositor snapshot");
    }
  }

  public static double[] solidDepthByRef() {
    return solidDepth;
  }

  public static double[] wallDepthByRef() {
    return wallDepth;
  }

  public static int renderWorldSnapshot(Uint8Array snapshot) {
`,
  'compose-entry',
);
core = replaceExact(
  core,
  '      int at = mobjOffset + mobj * 32;\n',
  '      int at = mobjOffset + mobj * 24;\n',
  'compact-mobj-record-size',
);
core = replaceExact(
  core,
  '          snapshot, mobjOffset + worldSpriteOrder[index] * 32,\n',
  '          snapshot, mobjOffset + worldSpriteOrder[index] * 24,\n',
  'compact-mobj-ordered-record-size',
);
core = replaceExact(
  core,
  '    int sector = snapshotI16(snapshot, at + 30);\n',
  '    int sector = snapshotI16(snapshot, at + 20);\n',
  'compact-mobj-sector',
);
core = replaceExact(
  core,
  `  private static void blitSprite(
      int asset, int left, int top, int map) {
    int width = spriteWidth[asset];
`,
  `  private static void buildBrightSpriteRuns() {
    int maximum = spriteTextureElements;
    brightAssetRunStart = new int[spriteBase.length];
    brightAssetRunEnd = new int[spriteBase.length];
    brightRunPixelStart = new int[maximum];
    brightRunX = new short[maximum];
    brightRunY = new short[maximum];
    brightRunLength = new short[maximum];
    brightRunPixels = new byte[maximum];
    brightRunCount = 0;
    brightPixelCount = 0;
    for (int asset = 0; asset < spriteBase.length; asset++) {
      brightAssetRunStart[asset] = brightRunCount;
      int width = spriteWidth[asset];
      int height = spriteHeight[asset];
      int base = spriteBase[asset];
      for (int x = 0; x < width; x++) {
        int y = 0;
        while (y < height) {
          while (y < height
              && spriteTexels[base + y * width + x] == 0) y++;
          if (y >= height) break;
          int first = y;
          int pixels = brightPixelCount;
          while (y < height) {
            int encoded = spriteTexels[base + y * width + x];
            if (encoded == 0) break;
            brightRunPixels[brightPixelCount++] =
                colormaps[(encoded - 1) & 255];
            y++;
          }
          brightRunPixelStart[brightRunCount] = pixels;
          brightRunX[brightRunCount] = (short) x;
          brightRunY[brightRunCount] = (short) first;
          brightRunLength[brightRunCount] = (short) (y - first);
          brightRunCount++;
        }
      }
      brightAssetRunEnd[asset] = brightRunCount;
    }
    byte[] verified = new byte[spriteTextureElements];
    for (int asset = 0; asset < spriteBase.length; asset++) {
      int width = spriteWidth[asset];
      int base = spriteBase[asset];
      for (int run = brightAssetRunStart[asset];
           run < brightAssetRunEnd[asset]; run++) {
        int x = brightRunX[run];
        int y = brightRunY[run];
        int length = brightRunLength[run];
        int source = brightRunPixelStart[run];
        for (int pixel = 0; pixel < length; pixel++) {
          verified[base + (y + pixel) * width + x] =
              brightRunPixels[source + pixel];
        }
      }
    }
    for (int index = 0; index < spriteTextureElements; index++) {
      int encoded = spriteTexels[index];
      int expected = encoded == 0 ? 0 : colormaps[(encoded - 1) & 255] & 255;
      if ((verified[index] & 255) != expected) {
        throw new IllegalStateException(
            "bright sprite run mismatch at " + index);
      }
    }
  }

  private static void blitBrightSprite(int asset, int left, int top) {
    int begin = brightAssetRunStart[asset];
    int end = brightAssetRunEnd[asset];
    for (int run = begin; run < end; run++) {
      int screenX = left + brightRunX[run];
      int screenY = top + brightRunY[run];
      int length = brightRunLength[run];
      int source = brightRunPixelStart[run];
      if (screenX < 0 || screenX >= WIDTH
          || screenY >= VIEW_HEIGHT || screenY + length <= 0) continue;
      if (screenY < 0) {
        source -= screenY;
        length += screenY;
        screenY = 0;
      }
      if (screenY + length > VIEW_HEIGHT) {
        length = VIEW_HEIGHT - screenY;
      }
      if (length > 0) {
        System.arraycopy(
            brightRunPixels, source,
            frame, screenX * FRAME_HEIGHT + screenY, length);
      }
    }
  }

  private static void blitSprite(
      int asset, int left, int top, int map) {
    if (map == 0) {
      blitBrightSprite(asset, left, top);
      return;
    }
    int width = spriteWidth[asset];
`,
  'bright-sprite-run-blit',
);
core = replaceExact(
  core,
  `  private static void drawStatusBar(Uint8Array snapshot) {
    if (!statusBarInitialized) {
`,
  `  private static int statusChangeMask(Uint8Array snapshot) {
    int health = Math.max(0, snapshotI32(snapshot, 56));
    int damage = snapshotI32(snapshot, 128);
    int bonus = snapshotI32(snapshot, 132);
    int cheats = snapshotI32(snapshot, 168);
    int refire = snapshotI32(snapshot, 180);
    int tic = snapshotI32(snapshot, 8);
    int face;
    if (health <= 0) face = 1;
    else if ((cheats & 1) != 0) face = 2;
    else if (damage > 20) face = 3;
    else if (damage > 0) face = 4 + ((tic & 8) == 0 ? 0 : 1);
    else if (bonus > 0) face = 6;
    else if (refire > 2) face = 7;
    else face = 8 + (tic / 17) % 3;
    int healthValue = snapshotI32(snapshot, 56);
    int armorValue = snapshotI32(snapshot, 60);
    int weaponValue = snapshotI32(snapshot, 64);
    int ammo0 = snapshotI32(snapshot, 72);
    int ammo1 = snapshotI32(snapshot, 76);
    int ammo2 = snapshotI32(snapshot, 80);
    int ammo3 = snapshotI32(snapshot, 84);
    int cardsValue = snapshotI32(snapshot, 144);
    int fragsValue = snapshotI32(snapshot, 148);
    int changed = 0;
    if (!statusBarInitialized || face != lastStatusState[0]
        || healthValue != lastStatusState[1]) changed |= 1;
    if (!statusBarInitialized || weaponValue != lastStatusState[3]
        || ammo0 != lastStatusState[4] || ammo1 != lastStatusState[5]
        || ammo2 != lastStatusState[6]
        || ammo3 != lastStatusState[7]) changed |= 2 | 64;
    if (!statusBarInitialized || healthValue != lastStatusState[1]) {
      changed |= 4;
    }
    if (!statusBarInitialized || armorValue != lastStatusState[2]) {
      changed |= 8;
    }
    if (!statusBarInitialized || cardsValue != lastStatusState[8]) {
      changed |= 16 | 32 | 64;
    }
    if (!statusBarInitialized || fragsValue != lastStatusState[9]) {
      changed |= 32;
    }
    if (changed != 0) {
      lastStatusState[0] = face;
      lastStatusState[1] = healthValue;
      lastStatusState[2] = armorValue;
      lastStatusState[3] = weaponValue;
      lastStatusState[4] = ammo0;
      lastStatusState[5] = ammo1;
      lastStatusState[6] = ammo2;
      lastStatusState[7] = ammo3;
      lastStatusState[8] = cardsValue;
      lastStatusState[9] = fragsValue;
    }
    return changed;
  }

  private static void drawStatusBar(Uint8Array snapshot) {
    int statusChanges = statusChangeMask(snapshot);
    if (statusChanges == 0) return;
    if (!statusBarInitialized) {
`,
  'retained-status-state',
);
core = replaceExact(
  core,
  `      restoreStatusRect(4, 44, 168, FRAME_HEIGHT);
      restoreStatusRect(51, 90, 168, FRAME_HEIGHT);
      restoreStatusRect(142, 185, 168, FRAME_HEIGHT);
      restoreStatusRect(182, 221, 168, FRAME_HEIGHT);
      restoreStatusRect(238, 269, 168, FRAME_HEIGHT);
      restoreStatusRect(104, 142, 168, FRAME_HEIGHT);
      restoreStatusRect(274, 320, 168, FRAME_HEIGHT);
`,
  `      if ((statusChanges & 2) != 0) {
        restoreStatusRect(4, 44, 168, FRAME_HEIGHT);
      }
      if ((statusChanges & 4) != 0) {
        restoreStatusRect(51, 90, 168, FRAME_HEIGHT);
      }
      if ((statusChanges & 1) != 0) {
        restoreStatusRect(142, 185, 168, FRAME_HEIGHT);
      }
      if ((statusChanges & 8) != 0) {
        restoreStatusRect(182, 221, 168, FRAME_HEIGHT);
      }
      if ((statusChanges & 16) != 0) {
        restoreStatusRect(238, 269, 168, FRAME_HEIGHT);
      }
      if ((statusChanges & 32) != 0) {
        restoreStatusRect(104, 142, 168, FRAME_HEIGHT);
      }
      if ((statusChanges & 64) != 0) {
        restoreStatusRect(274, 320, 168, FRAME_HEIGHT);
      }
`,
  'widget-specific-status-restore',
);
core = replaceExact(
  core,
  `    drawHudNumber(Math.max(0, ammo), 44);
`,
  `    if ((statusChanges & 2) != 0) {
      drawHudNumber(Math.max(0, ammo), 44);
    }
`,
  'widget-specific-ammo',
);
core = replaceExact(
  core,
  `    drawHudNumber(health, 90);
    drawHudNumber(armor, 221);
    blitUi(uiPercent, 90, 171);
    blitUi(uiPercent, 221, 171);
    // STFB0 is the player-color background behind Doomguy's animated face.
    blitUi(uiFaceNormal, 143, 169);
`,
  `    if ((statusChanges & 4) != 0) {
      drawHudNumber(health, 90);
      blitUi(uiPercent, 90, 171);
    }
    if ((statusChanges & 8) != 0) {
      drawHudNumber(armor, 221);
      blitUi(uiPercent, 221, 171);
    }
    // STFB0 is the player-color background behind Doomguy's animated face.
    if ((statusChanges & 1) != 0) blitUi(uiFaceNormal, 143, 169);
`,
  'widget-specific-health-armor-face-background',
);
core = replaceExact(
  core,
  `    blitUi(face, 148, 169);
    int presentationFlags = snapshotI32(snapshot, 144);
    for (int row = 0; row < 3; row++) {
      int key = (presentationFlags & (1 << (row + 3))) != 0
          ? row + 3
          : (presentationFlags & (1 << row)) != 0 ? row : -1;
      if (key >= 0) blitUi(uiKeys[key], 239, 171 + row * 10);
    }
    boolean deathmatch = (presentationFlags & (1 << 18)) != 0;
    if (deathmatch) {
      drawTallHudNumber(snapshotI32(snapshot, 148), 138, 171, 2);
    } else {
      blitUi(uiArmsBackground, 104, 168);
      for (int arm = 0; arm < 6; arm++) {
        boolean owned =
            (presentationFlags & (1 << (8 + arm + 1))) != 0;
        blitUi(owned ? uiYellowDigits[arm + 2] : uiGrayArmsDigits[arm],
            111 + (arm % 3) * 12, 172 + (arm / 3) * 10);
      }
    }
    boolean backpack = (presentationFlags & (1 << 17)) != 0;
    for (int ammoType = 0; ammoType < 4; ammoType++) {
      drawShortHudNumber(
          Math.max(0, snapshotI32(snapshot, 72 + ammoType * 4)),
          288, STATUS_AMMO_Y[ammoType], 3);
      drawShortHudNumber(
          STATUS_MAX_AMMO[ammoType] * (backpack ? 2 : 1),
          314, STATUS_AMMO_Y[ammoType], 3);
    }
`,
  `    if ((statusChanges & 1) != 0) blitUi(face, 148, 169);
    if ((statusChanges & 16) != 0) {
      int presentationFlags = snapshotI32(snapshot, 144);
      for (int row = 0; row < 3; row++) {
        int key = (presentationFlags & (1 << (row + 3))) != 0
            ? row + 3
            : (presentationFlags & (1 << row)) != 0 ? row : -1;
        if (key >= 0) blitUi(uiKeys[key], 239, 171 + row * 10);
      }
    }
    int presentationFlags = snapshotI32(snapshot, 144);
    if ((statusChanges & 32) != 0) {
      boolean deathmatch = (presentationFlags & (1 << 18)) != 0;
      if (deathmatch) {
        drawTallHudNumber(snapshotI32(snapshot, 148), 138, 171, 2);
      } else {
        blitUi(uiArmsBackground, 104, 168);
        for (int arm = 0; arm < 6; arm++) {
          boolean owned =
              (presentationFlags & (1 << (8 + arm + 1))) != 0;
          blitUi(owned ? uiYellowDigits[arm + 2] : uiGrayArmsDigits[arm],
              111 + (arm % 3) * 12, 172 + (arm / 3) * 10);
        }
      }
    }
    if ((statusChanges & 64) != 0) {
      boolean backpack = (presentationFlags & (1 << 17)) != 0;
      for (int ammoType = 0; ammoType < 4; ammoType++) {
        drawShortHudNumber(
            Math.max(0, snapshotI32(snapshot, 72 + ammoType * 4)),
            288, STATUS_AMMO_Y[ammoType], 3);
        drawShortHudNumber(
            STATUS_MAX_AMMO[ammoType] * (backpack ? 2 : 1),
            314, STATUS_AMMO_Y[ammoType], 3);
      }
    }
`,
  'widget-specific-face-and-keys',
);
if (core.includes('@JSExport') || core.includes('@JSByRef')) {
  throw new Error('compositor core still contains delegate exports');
}
fs.writeFileSync(
  path.join(outputRoot, 'FreeLiveCompositorCore.java'), core);
fs.copyFileSync(
  path.join(sourceRoot, 'FreeLiveCompositorModule.java'),
  path.join(outputRoot, 'FreeLiveCompositorModule.java'));
process.stdout.write(
  'PMLE_FREE_LIVE_COMPOSITOR_SOURCE|PASS' +
  `|input_bytes=${Buffer.byteLength(source)}` +
  `|input_sha256=${sha256(source)}` +
  `|core_bytes=${Buffer.byteLength(core)}` +
  `|core_sha256=${sha256(core)}\n`,
);
