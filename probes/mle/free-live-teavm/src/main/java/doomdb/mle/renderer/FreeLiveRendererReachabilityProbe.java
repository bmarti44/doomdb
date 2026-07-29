package doomdb.mle.renderer;

import org.teavm.jso.JSExport;
import org.teavm.jso.JSByRef;
import org.teavm.jso.typedarrays.Uint8Array;

/**
 * Generated-shape rank for the specialized Always Free live renderer.
 *
 * This intentionally contains only BSP/portal visibility.  It answers whether
 * the same primitive-array kernel that is compilation-inert as hand-written
 * JavaScript becomes compiler-visible when emitted by TeaVM.  It is not a
 * production renderer and cannot be promoted without the exact same texture,
 * sprite, HUD, and framebuffer work as the live module.
 */
public final class FreeLiveRendererReachabilityProbe {
  private static final int MAGIC = 0x31465244;
  private static final int WIDTH = 320;
  private static final int LIVE_RENDER_WIDTH = 160;
  private static final int VIEW_HEIGHT = 168;
  private static final int FRAME_HEIGHT = 200;
  private static final int PIXELS = WIDTH * FRAME_HEIGHT;
  private static final int CACHE_SIZE = 262144;
  private static final int COMMAND_BYTES = 24;
  private static final int RESOLVED_COMMAND_BYTES = 20;
  private static final int COMMAND_BUFFER_BYTES = 262144;
  private static final int NATIVE_TAPE_MAGIC = 0x31575244;
  private static byte[] pack;
  private static int poseOffset;
  private static int poseCount;
  private static int poseRecordBytes;
  private static int[] lineX1;
  private static int[] lineY1;
  private static int[] lineX2;
  private static int[] lineY2;
  private static char[] lineRightSector;
  private static char[] lineLeftSector;
  private static char[] lineRightUpper;
  private static char[] lineRightLower;
  private static char[] lineRightMiddle;
  private static char[] lineLeftUpper;
  private static char[] lineLeftLower;
  private static char[] lineLeftMiddle;
  private static char[] lineRightSide;
  private static char[] lineLeftSide;
  private static char[] lineTexture;
  private static short[] lineXOffset;
  private static short[] lineYOffset;
  private static short[] lineLeftXOffset;
  private static short[] lineLeftYOffset;
  private static short[] sectorFloor;
  private static short[] sectorCeiling;
  private static byte[] sectorLight;
  private static int sectorCount;
  private static char[] sectorFloorAsset;
  private static char[] sectorCeilingAsset;
  private static char[] runtimeWallToAsset;
  private static char[] runtimeFlatToAsset;
  private static char[] dynamicSideTop;
  private static char[] dynamicSideBottom;
  private static char[] dynamicSideMiddle;
  private static int sideCount;
  private static boolean liveDynamicsActive;
  private static char[] subsectorSector;
  private static byte[] colormaps;
  private static int[] textureBase;
  private static char[] textureWidth;
  private static char[] textureHeight;
  private static int wallTextureElements;
  private static byte[] encodedWallTextures;
  private static byte[] encodedFlatTextures;
  private static byte[] encodedSpriteTextures;
  private static byte[] encodedUiTextures;
  private static byte[] litTextures;
  private static byte[] litFlats;
  private static int flatTextureElements;
  private static int[] lightToBank;
  private static int lightBankCount;
  private static int spriteTextureElements;
  private static int[] spriteBase;
  private static char[] spriteWidth;
  private static char[] spriteHeight;
  private static short[] spriteLeft;
  private static short[] spriteTop;
  private static char[] spriteLookupAsset;
  private static byte[] spriteLookupFlip;
  private static int spritePrefixCount;
  private static int spriteFrameCount;
  private static char[] spriteTexels;
  private static int uiTextureElements;
  private static int[] uiBase;
  private static char[] uiWidth;
  private static char[] uiHeight;
  private static char[] uiDigits;
  private static char[] uiKeys;
  private static char[] uiFaceStraight;
  private static char[] uiFaceTurnLeft;
  private static char[] uiFaceTurnRight;
  private static char[] uiFaceOuch;
  private static char[] uiFaceEvil;
  private static char[] uiFaceKill;
  private static char[] uiMainMenuItems;
  private static char[] uiEpisodeMenuItems;
  private static char[] uiSkillMenuItems;
  private static char[] uiOptionMenuItems;
  private static char[] uiMenuSkulls;
  private static char[] uiFullScreens;
  private static char[] uiTexels;
  private static int[] uiAssetRunStart;
  private static int[] uiAssetRunEnd;
  private static int[] uiRunPixelStart;
  private static short[] uiRunX;
  private static short[] uiRunY;
  private static short[] uiRunLength;
  private static byte[] uiRunPixels;
  private static int uiStatusBar;
  private static int uiFaceNormal;
  private static int uiFaceDead;
  private static int uiFaceGod;
  private static int uiTitle;
  private static int uiPause;
  private static int uiMenuLogo;
  private static int uiNewGame;
  private static int uiEpisode;
  private static int uiSkill;
  private static int uiOptions;
  private static byte[] frame;
  private static byte[] statusBarBackground;
  private static boolean statusBarInitialized;
  private static byte[] backgroundColumn;
  private static short[] sinTable;
  private static short[] cosTable;
  private static int[] segX1;
  private static int[] segY1;
  private static int[] segX2;
  private static int[] segY2;
  private static char[] segLine;
  private static byte[] segDirection;
  private static int[] ssectorFirst;
  private static char[] ssectorCount;
  private static int[] nodeX;
  private static int[] nodeY;
  private static int[] nodeDx;
  private static int[] nodeDy;
  private static int[] nodeChild0;
  private static int[] nodeChild1;
  private static int[] bbox0Top;
  private static int[] bbox0Bottom;
  private static int[] bbox0Left;
  private static int[] bbox0Right;
  private static int[] bbox1Top;
  private static int[] bbox1Bottom;
  private static int[] bbox1Left;
  private static int[] bbox1Right;
  private static int[] clipTop;
  private static int[] clipBottom;
  private static double[] solidDepth;
  private static double[] wallDepth;
  private static int stagedMobjOffset;
  private static int stagedMobjCount;
  private static int[] stack;
  private static short[] stackCheck;
  private static byte[] commandBuffer;
  private static int commandLength;
  private static boolean captureCommands;
  private static int commandCaptureWidth = WIDTH;
  private static boolean captureResolvedCommands;
  private static boolean captureNativeTape;
  private static int nativeCommandCount;
  private static int nativeMissCount;
  private static int rasterPixelWrites;
  private static int activeWidth;
  private static int pixelScale;
  private static boolean coarseVerticalRaster;
  private static short[] planeTop;
  private static short[] planeBottom;
  private static int[] planeStamp;
  private static int[] planeMinX;
  private static int[] planeMaxX;
  private static int[] touchedPlanes;
  private static int touchedPlaneCount;
  private static int planeSerial;
  private static int[] spanStart;
  private static int[] nativeCacheKeyA;
  private static int[] nativeCacheKeyB;
  private static int[] nativeCacheKeyC;
  private static byte[] nativeCacheValid;
  private static int[] worldSpriteOrder;
  private static double[] worldSpriteDepth;

  private FreeLiveRendererReachabilityProbe() {}

  @JSExport
  public static int allocatePack(int length) {
    if (length < 496 || length > 1_000_000) {
      throw new IllegalArgumentException("invalid pack length");
    }
    pack = new byte[length];
    return length;
  }

  @JSExport
  public static int loadPackChunk(int offset, Uint8Array chunk) {
    if (pack == null || offset < 0 || offset + chunk.getLength() > pack.length) {
      throw new IllegalArgumentException("pack chunk outside allocation");
    }
    for (int index = 0; index < chunk.getLength(); index++) {
      pack[offset + index] = (byte) chunk.get(index);
    }
    return offset + chunk.getLength();
  }

  @JSExport
  public static int allocateWallTextures(int length) {
    if (length < 1 || length > 10_000_000) {
      throw new IllegalArgumentException("invalid wall texture length");
    }
    encodedWallTextures = new byte[length];
    return length;
  }

  @JSExport
  public static int loadWallTextureChunk(int offset, Uint8Array chunk) {
    if (encodedWallTextures == null || offset < 0
        || offset + chunk.getLength() > encodedWallTextures.length) {
      throw new IllegalArgumentException("wall texture chunk outside allocation");
    }
    for (int index = 0; index < chunk.getLength(); index++) {
      encodedWallTextures[offset + index] = (byte) chunk.get(index);
    }
    return offset + chunk.getLength();
  }

  @JSExport
  public static int finalizePack() {
    if (u32(0) != MAGIC || u32(4) != 7 || u32(76) != pack.length) {
      throw new IllegalStateException("pack header mismatch");
    }
    int lineCount = u32(24);
    poseCount = u32(36);
    poseOffset = u32(64);
    poseRecordBytes = u32(176);
    int segCount = u32(180);
    int subsectorCount = u32(184);
    int nodeCount = u32(188);
    sectorCount = u32(120);
    int textureCount = u32(80);
    wallTextureElements = u32(84);
    int flatTextureCount = u32(288);
    flatTextureElements = u32(292);
    int spriteTextureCount = u32(300);
    spriteTextureElements = u32(304);
    spritePrefixCount = u32(336);
    spriteFrameCount = u32(340);
    int uiTextureCount = u32(344);
    uiTextureElements = u32(348);
    if (poseCount != 5250 || poseRecordBytes != 32 || nodeCount < 1) {
      throw new IllegalStateException("pack cardinality mismatch");
    }
    if (flatTextureCount < 1 || flatTextureElements != flatTextureCount * 4096) {
      throw new IllegalStateException("flat cardinality mismatch");
    }
    if (spriteTextureCount < 1 || spriteTextureElements < 1
        || spritePrefixCount < 100 || spriteFrameCount != 29
        || uiTextureCount < 1 || uiTextureElements < 1) {
      throw new IllegalStateException("presentation asset cardinality mismatch");
    }
    lineX1 = ints(u32(40), lineCount);
    lineY1 = ints(u32(44), lineCount);
    lineX2 = ints(u32(48), lineCount);
    lineY2 = ints(u32(52), lineCount);
    sinTable = shorts(u32(68), 2048);
    cosTable = shorts(u32(72), 2048);
    lineRightSector = chars(u32(112), lineCount);
    lineLeftSector = chars(u32(116), lineCount);
    lineRightUpper = chars(u32(140), lineCount);
    lineRightLower = chars(u32(144), lineCount);
    lineRightMiddle = chars(u32(148), lineCount);
    lineLeftUpper = chars(u32(152), lineCount);
    lineLeftLower = chars(u32(156), lineCount);
    lineLeftMiddle = chars(u32(160), lineCount);
    lineTexture = chars(u32(100), lineCount);
    lineXOffset = shorts(u32(104), lineCount);
    lineYOffset = shorts(u32(108), lineCount);
    lineLeftXOffset = shorts(u32(164), lineCount);
    lineLeftYOffset = shorts(u32(168), lineCount);
    sectorFloor = shorts(u32(124), sectorCount);
    sectorCeiling = shorts(u32(128), sectorCount);
    sectorLight = bytes(u32(132), sectorCount);
    sectorFloorAsset = chars(u32(280), sectorCount);
    sectorCeilingAsset = chars(u32(284), sectorCount);
    subsectorSector = chars(u32(296), subsectorCount);
    colormaps = bytes(u32(136), 8192);
    textureBase = ints(u32(88), textureCount);
    textureWidth = chars(u32(92), textureCount);
    textureHeight = chars(u32(96), textureCount);
    segX1 = ints(u32(192), segCount);
    segY1 = ints(u32(196), segCount);
    segX2 = ints(u32(200), segCount);
    segY2 = ints(u32(204), segCount);
    segLine = chars(u32(208), segCount);
    segDirection = bytes(u32(212), segCount);
    ssectorFirst = ints(u32(216), subsectorCount);
    ssectorCount = chars(u32(220), subsectorCount);
    nodeX = ints(u32(224), nodeCount);
    nodeY = ints(u32(228), nodeCount);
    nodeDx = ints(u32(232), nodeCount);
    nodeDy = ints(u32(236), nodeCount);
    nodeChild0 = ints(u32(240), nodeCount);
    nodeChild1 = ints(u32(244), nodeCount);
    bbox0Top = ints(u32(248), nodeCount);
    bbox0Bottom = ints(u32(252), nodeCount);
    bbox0Left = ints(u32(256), nodeCount);
    bbox0Right = ints(u32(260), nodeCount);
    bbox1Top = ints(u32(264), nodeCount);
    bbox1Bottom = ints(u32(268), nodeCount);
    bbox1Left = ints(u32(272), nodeCount);
    bbox1Right = ints(u32(276), nodeCount);
    spriteBase = ints(u32(308), spriteTextureCount);
    spriteWidth = chars(u32(312), spriteTextureCount);
    spriteHeight = chars(u32(316), spriteTextureCount);
    spriteLeft = shorts(u32(320), spriteTextureCount);
    spriteTop = shorts(u32(324), spriteTextureCount);
    int spriteLookupCount =
        spritePrefixCount * spriteFrameCount * 9;
    spriteLookupAsset = chars(u32(328), spriteLookupCount);
    spriteLookupFlip = bytes(u32(332), spriteLookupCount);
    uiBase = ints(u32(352), uiTextureCount);
    uiWidth = chars(u32(356), uiTextureCount);
    uiHeight = chars(u32(360), uiTextureCount);
    uiStatusBar = u32(364);
    uiFaceNormal = u32(368);
    uiFaceDead = u32(372);
    uiFaceGod = u32(376);
    uiTitle = u32(380);
    uiPause = u32(384);
    uiMenuLogo = u32(388);
    uiNewGame = u32(392);
    uiEpisode = u32(396);
    uiSkill = u32(400);
    uiDigits = chars(u32(404), 10);
    uiKeys = chars(u32(408), 6);
    uiFaceStraight = chars(u32(412), 15);
    uiFaceTurnLeft = chars(u32(416), 5);
    uiFaceTurnRight = chars(u32(420), 5);
    uiFaceOuch = chars(u32(424), 5);
    uiFaceEvil = chars(u32(428), 5);
    uiFaceKill = chars(u32(432), 5);
    uiMainMenuItems = chars(u32(436), 6);
    uiEpisodeMenuItems = chars(u32(440), 4);
    uiSkillMenuItems = chars(u32(444), 5);
    uiOptionMenuItems = chars(u32(448), 6);
    uiMenuSkulls = chars(u32(452), 2);
    uiFullScreens = chars(u32(456), 10);
    uiOptions = u32(460);
    runtimeWallToAsset = chars(u32(464), u32(468));
    runtimeFlatToAsset = chars(u32(472), u32(476));
    lineRightSide = chars(u32(480), lineCount);
    lineLeftSide = chars(u32(484), lineCount);
    sideCount = u32(488);
    if (u32(492) != 208 || sideCount < 1
        || runtimeWallToAsset.length < 1
        || runtimeFlatToAsset.length < 1) {
      throw new IllegalStateException("DVL2 mapping cardinality mismatch");
    }
    dynamicSideTop = new char[sideCount];
    dynamicSideBottom = new char[sideCount];
    dynamicSideMiddle = new char[sideCount];
    clipTop = new int[WIDTH];
    clipBottom = new int[WIDTH];
    solidDepth = new double[WIDTH];
    wallDepth = new double[LIVE_RENDER_WIDTH * VIEW_HEIGHT];
    stack = new int[nodeCount + subsectorCount + 8];
    stackCheck = new short[stack.length];
    frame = new byte[PIXELS];
    backgroundColumn = new byte[VIEW_HEIGHT];
    for (int y = 0; y < VIEW_HEIGHT; y++) {
      backgroundColumn[y] = (byte) (y < VIEW_HEIGHT / 2 ? 96 : 48);
    }
    commandBuffer = new byte[COMMAND_BUFFER_BYTES];
    nativeCacheKeyA = new int[CACHE_SIZE];
    nativeCacheKeyB = new int[CACHE_SIZE];
    nativeCacheKeyC = new int[CACHE_SIZE];
    nativeCacheValid = new byte[CACHE_SIZE];
    int planeCount = sectorCount * 2;
    planeTop = new short[planeCount * LIVE_RENDER_WIDTH];
    planeBottom = new short[planeCount * LIVE_RENDER_WIDTH];
    planeStamp = new int[planeCount];
    planeMinX = new int[planeCount];
    planeMaxX = new int[planeCount];
    touchedPlanes = new int[planeCount];
    spanStart = new int[VIEW_HEIGHT];
    worldSpriteOrder = new int[1024];
    worldSpriteDepth = new double[1024];
    return pack.length;
  }

  @JSExport
  public static int finalizeWallTextures() {
    if (encodedWallTextures == null
        || encodedWallTextures.length != wallTextureElements * 2) {
      throw new IllegalStateException("wall texture length mismatch");
    }
    lightToBank = new int[32];
    for (int index = 0; index < lightToBank.length; index++) {
      lightToBank[index] = -1;
    }
    lightBankCount = 0;
    for (byte value : sectorLight) {
      int light = value & 255;
      int map = Math.max(0, Math.min(31, (255 - light) / 8));
      if (lightToBank[map] < 0) lightToBank[map] = lightBankCount++;
    }
    litTextures = new byte[wallTextureElements * lightBankCount];
    for (int map = 0; map < 32; map++) {
      int bank = lightToBank[map];
      if (bank < 0) continue;
      int target = bank * wallTextureElements;
      for (int texel = 0; texel < wallTextureElements; texel++) {
        int encoded = ((encodedWallTextures[texel * 2] & 255) << 8)
            | (encodedWallTextures[texel * 2 + 1] & 255);
        int sample = encoded == 0 ? 0 : encoded - 1;
        litTextures[target + texel] = colormaps[map * 256 + sample];
      }
    }
    int length = encodedWallTextures.length;
    encodedWallTextures = null;
    return length;
  }

  @JSExport
  public static int allocateFlatTextures(int length) {
    if (flatTextureElements < 1 || length != flatTextureElements * 2) {
      throw new IllegalArgumentException("invalid flat texture length");
    }
    encodedFlatTextures = new byte[length];
    return length;
  }

  @JSExport
  public static int loadFlatTextureChunk(int offset, Uint8Array chunk) {
    if (encodedFlatTextures == null || offset < 0
        || offset + chunk.getLength() > encodedFlatTextures.length) {
      throw new IllegalArgumentException("flat texture chunk outside allocation");
    }
    for (int index = 0; index < chunk.getLength(); index++) {
      encodedFlatTextures[offset + index] = (byte) chunk.get(index);
    }
    return offset + chunk.getLength();
  }

  @JSExport
  public static int finalizeFlatTextures() {
    if (encodedFlatTextures == null
        || encodedFlatTextures.length != flatTextureElements * 2
        || lightToBank == null) {
      throw new IllegalStateException("flat texture length mismatch");
    }
    litFlats = new byte[flatTextureElements * lightBankCount];
    for (int map = 0; map < 32; map++) {
      int bank = lightToBank[map];
      if (bank < 0) continue;
      int target = bank * flatTextureElements;
      for (int texel = 0; texel < flatTextureElements; texel++) {
        int encoded = ((encodedFlatTextures[texel * 2] & 255) << 8)
            | (encodedFlatTextures[texel * 2 + 1] & 255);
        int sample = encoded == 0 ? 0 : encoded - 1;
        litFlats[target + texel] = colormaps[map * 256 + sample];
      }
    }
    int length = encodedFlatTextures.length;
    encodedFlatTextures = null;
    return length;
  }

  @JSExport
  public static int allocateSpriteTextures(int length) {
    if (spriteTextureElements < 1 || length != spriteTextureElements * 2) {
      throw new IllegalArgumentException("invalid sprite texture length");
    }
    encodedSpriteTextures = new byte[length];
    return length;
  }

  @JSExport
  public static int loadSpriteTextureChunk(int offset, Uint8Array chunk) {
    if (encodedSpriteTextures == null || offset < 0
        || offset + chunk.getLength() > encodedSpriteTextures.length) {
      throw new IllegalArgumentException("sprite texture chunk outside allocation");
    }
    for (int index = 0; index < chunk.getLength(); index++) {
      encodedSpriteTextures[offset + index] = (byte) chunk.get(index);
    }
    return offset + chunk.getLength();
  }

  @JSExport
  public static int finalizeSpriteTextures() {
    if (encodedSpriteTextures == null
        || encodedSpriteTextures.length != spriteTextureElements * 2) {
      throw new IllegalStateException("sprite texture length mismatch");
    }
    spriteTexels = decodeTransparentTexels(
        encodedSpriteTextures, spriteTextureElements);
    int length = encodedSpriteTextures.length;
    encodedSpriteTextures = null;
    return length;
  }

  @JSExport
  public static int allocateUiTextures(int length) {
    if (uiTextureElements < 1 || length != uiTextureElements * 2) {
      throw new IllegalArgumentException("invalid UI texture length");
    }
    encodedUiTextures = new byte[length];
    return length;
  }

  @JSExport
  public static int loadUiTextureChunk(int offset, Uint8Array chunk) {
    if (encodedUiTextures == null || offset < 0
        || offset + chunk.getLength() > encodedUiTextures.length) {
      throw new IllegalArgumentException("UI texture chunk outside allocation");
    }
    for (int index = 0; index < chunk.getLength(); index++) {
      encodedUiTextures[offset + index] = (byte) chunk.get(index);
    }
    return offset + chunk.getLength();
  }

  @JSExport
  public static int finalizeUiTextures() {
    if (encodedUiTextures == null
        || encodedUiTextures.length != uiTextureElements * 2) {
      throw new IllegalStateException("UI texture length mismatch");
    }
    uiTexels = decodeTransparentTexels(encodedUiTextures, uiTextureElements);
    buildUiRuns();
    int statusWidth = uiWidth[uiStatusBar];
    int statusHeight = uiHeight[uiStatusBar];
    statusBarBackground = new byte[WIDTH * (FRAME_HEIGHT - VIEW_HEIGHT)];
    int statusBase = uiBase[uiStatusBar];
    for (int y = 0; y < statusHeight; y++) {
      for (int x = 0; x < statusWidth; x++) {
        int encoded = uiTexels[statusBase + y * statusWidth + x];
        if (encoded != 0) {
          statusBarBackground[
              x * (FRAME_HEIGHT - VIEW_HEIGHT) + y] =
              (byte) (encoded - 1);
        }
      }
    }
    int length = encodedUiTextures.length;
    encodedUiTextures = null;
    return length;
  }

  /**
   * Convert row-major transparent UI patches into opaque vertical runs once.
   * The framebuffer is column-major, so every unclipped run becomes one
   * native array copy instead of interpreted per-pixel transparency checks.
   */
  private static void buildUiRuns() {
    int runCount = 0;
    int pixelCount = 0;
    for (int asset = 0; asset < uiBase.length; asset++) {
      int width = uiWidth[asset];
      int height = uiHeight[asset];
      int base = uiBase[asset];
      for (int x = 0; x < width; x++) {
        int y = 0;
        while (y < height) {
          while (y < height && uiTexels[base + y * width + x] == 0) y++;
          if (y >= height) break;
          runCount++;
          while (y < height && uiTexels[base + y * width + x] != 0) {
            pixelCount++;
            y++;
          }
        }
      }
    }
    uiAssetRunStart = new int[uiBase.length];
    uiAssetRunEnd = new int[uiBase.length];
    uiRunPixelStart = new int[runCount];
    uiRunX = new short[runCount];
    uiRunY = new short[runCount];
    uiRunLength = new short[runCount];
    uiRunPixels = new byte[pixelCount];
    int run = 0;
    int pixel = 0;
    for (int asset = 0; asset < uiBase.length; asset++) {
      uiAssetRunStart[asset] = run;
      int width = uiWidth[asset];
      int height = uiHeight[asset];
      int base = uiBase[asset];
      for (int x = 0; x < width; x++) {
        int y = 0;
        while (y < height) {
          while (y < height && uiTexels[base + y * width + x] == 0) y++;
          if (y >= height) break;
          int first = y;
          uiRunPixelStart[run] = pixel;
          uiRunX[run] = (short) x;
          uiRunY[run] = (short) y;
          while (y < height) {
            int encoded = uiTexels[base + y * width + x];
            if (encoded == 0) break;
            uiRunPixels[pixel++] = (byte) (encoded - 1);
            y++;
          }
          uiRunLength[run] = (short) (y - first);
          run++;
        }
      }
      uiAssetRunEnd[asset] = run;
    }
    if (run != runCount || pixel != pixelCount) {
      throw new IllegalStateException("UI run cardinality mismatch");
    }
    byte[] verified = new byte[uiTextureElements];
    for (int asset = 0; asset < uiBase.length; asset++) {
      int width = uiWidth[asset];
      int base = uiBase[asset];
      for (int index = uiAssetRunStart[asset];
           index < uiAssetRunEnd[asset]; index++) {
        int x = uiRunX[index];
        int y = uiRunY[index];
        int source = uiRunPixelStart[index];
        int length = uiRunLength[index];
        for (int at = 0; at < length; at++) {
          verified[base + (y + at) * width + x] =
              uiRunPixels[source + at];
        }
      }
    }
    for (int index = 0; index < uiTextureElements; index++) {
      int encoded = uiTexels[index];
      int expected = encoded == 0 ? 0 : encoded - 1;
      if ((verified[index] & 255) != expected) {
        throw new IllegalStateException("UI run mismatch at " + index);
      }
    }
  }

  private static char[] decodeTransparentTexels(
      byte[] encoded, int elementCount) {
    char[] decoded = new char[elementCount];
    for (int texel = 0; texel < elementCount; texel++) {
      decoded[texel] = (char) (((encoded[texel * 2] & 255) << 8)
          | (encoded[texel * 2 + 1] & 255));
    }
    return decoded;
  }

  @JSExport
  public static int renderGeometry(int pose) {
    return render(pose, false, false, true);
  }

  @JSExport
  public static int renderFrame(int pose) {
    if (litTextures == null || litFlats == null) {
      throw new IllegalStateException("renderer textures are not finalized");
    }
    return render(pose, true, true, true);
  }

  /**
   * Authentic Doom projection and assets with a 160x84 world raster doubled
   * into the 320x168 view. Weapon sprites and the 320x32 status bar remain at
   * their native output resolution.
   */
  @JSExport
  public static int renderFrameCoarseVertical(int pose) {
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

  /** Diagnostic stage split: authentic wall columns without plane spans. */
  @JSExport
  public static int renderWallsOnly(int pose) {
    if (litTextures == null) {
      throw new IllegalStateException("renderer textures are not finalized");
    }
    return render(pose, true, false, true);
  }

  /** Diagnostic stage split: authentic floor/ceiling spans without BSP walls. */
  @JSExport
  public static int renderPlanesOnly(int pose) {
    if (litFlats == null) {
      throw new IllegalStateException("renderer flats are not finalized");
    }
    return render(pose, true, true, false);
  }

  /**
   * Render from the compact live-authority player snapshot rather than the
   * prerecorded diagnostic pose bank.  The first 32 bytes deliberately share
   * the accepted pose-record layout:
   *
   * <pre>
   * x, y, angle&gt;&gt;16, viewz, health, armor, readyweapon, ammo[0]
   * </pre>
   *
   * The remaining fields already cross the authority/renderer boundary even
   * though the wall-only prototype does not consume them yet.  Keeping the
   * complete record prevents a second boundary-format change when weapon and
   * HUD composition land.
   */
  @JSExport
  public static int renderPlayerSnapshot(Uint8Array snapshot) {
    if (litTextures == null || litFlats == null) {
      throw new IllegalStateException("renderer textures are not finalized");
    }
    if (snapshot == null || snapshot.getLength() != 32) {
      throw new IllegalArgumentException("player snapshot must be 32 bytes");
    }
    return renderView(
        snapshotI32(snapshot, 0),
        snapshotI32(snapshot, 4),
        snapshotI32(snapshot, 8),
        snapshotI32(snapshot, 12),
        0,
        true,
        true,
        true);
  }

  /**
   * Render a complete live 320x200 frame from the bounded DVL2 authority
   * snapshot. Walls, floors, ceilings, world sprites, weapon psprites and the
   * status bar are all authored here in MLE; the browser receives only the
   * resulting indexed pixels.
   */
  @JSExport
  public static int renderWorldSnapshot(Uint8Array snapshot) {
    loadWorldDynamics(snapshot);
    int checksum = renderLoadedWorldGeometry(snapshot);
    drawWorldSprites(snapshot, stagedMobjOffset, stagedMobjCount);
    drawPlayerSprites(snapshot);
    drawStatusBar(snapshot);
    checksum ^= (frame[snapshotI32(snapshot, 8) % PIXELS] & 255)
        | ((frame[(snapshotI32(snapshot, 8) * 997) % PIXELS] & 255) << 8);
    return checksum;
  }

  /**
   * Import dynamic sectors/sides and draw walls plus visplanes. The retained
   * frame is the input to the following sprite, weapon, and HUD stage calls.
   */
  @JSExport
  public static int renderWorldGeometryStage(Uint8Array snapshot) {
    loadWorldDynamics(snapshot);
    return renderLoadedWorldGeometry(snapshot);
  }

  /** Import only the per-frame sector and sidedef state. */
  @JSExport
  public static int loadWorldDynamicsStage(Uint8Array snapshot) {
    loadWorldDynamics(snapshot);
    return stagedMobjOffset ^ stagedMobjCount;
  }

  /** Draw geometry after {@link #loadWorldDynamicsStage(Uint8Array)}. */
  @JSExport
  public static int renderLoadedWorldGeometryStage(Uint8Array snapshot) {
    validateWorldSnapshot(snapshot);
    return renderLoadedWorldGeometry(snapshot);
  }

  /** Compose world mobjs onto the retained geometry frame. */
  @JSExport
  public static int renderWorldSpritesStage(Uint8Array snapshot) {
    validateWorldSnapshot(snapshot);
    drawWorldSprites(snapshot, stagedMobjOffset, stagedMobjCount);
    return frame[0] & 255;
  }

  /** Compose the active weapon and muzzle-flash psprites. */
  @JSExport
  public static int renderWeaponStage(Uint8Array snapshot) {
    validateWorldSnapshot(snapshot);
    drawPlayerSprites(snapshot);
    return frame[VIEW_HEIGHT - 1] & 255;
  }

  /**
   * Compose the currently supported Doom status-bar subset. The ARMS ownership
   * grid, ammo maxima, percent patches, and multiplayer frag widgets remain
   * fidelity work.
   */
  @JSExport
  public static int renderStatusStage(Uint8Array snapshot) {
    validateWorldSnapshot(snapshot);
    drawStatusBar(snapshot);
    return frame[PIXELS - 1] & 255;
  }

  private static void validateWorldSnapshot(Uint8Array snapshot) {
    if (litTextures == null || litFlats == null
        || spriteTexels == null || uiTexels == null) {
      throw new IllegalStateException("complete renderer assets are not finalized");
    }
    if (snapshot == null || snapshot.getLength() < 208
        || snapshotI32(snapshot, 0) != 0x324c5644
        || snapshotI32(snapshot, 4) != 2) {
      throw new IllegalArgumentException("invalid DVL2 world snapshot");
    }
    int sectors = snapshotI32(snapshot, 16);
    int mobjs = snapshotI32(snapshot, 20);
    int sectorOffset = snapshotI32(snapshot, 24);
    int mobjOffset = snapshotI32(snapshot, 28);
    int length = snapshotI32(snapshot, 32);
    int sides = snapshotI32(snapshot, 192);
    int sideOffset = snapshotI32(snapshot, 196);
    if (sectors != sectorCount || sectorOffset != 208
        || sides != sideCount || snapshotI32(snapshot, 200) != 8
        || snapshotI32(snapshot, 204) != sectorOffset
        || sideOffset != sectorOffset + sectors * 16
        || mobjOffset != sideOffset + sides * 8
        || mobjs < 0 || mobjs > worldSpriteOrder.length
        || length != mobjOffset + mobjs * 32
        || length != snapshot.getLength()) {
      throw new IllegalArgumentException("DVL2 world snapshot layout mismatch");
    }
    stagedMobjOffset = mobjOffset;
    stagedMobjCount = mobjs;
  }

  private static void loadWorldDynamics(Uint8Array snapshot) {
    validateWorldSnapshot(snapshot);
    int sectors = snapshotI32(snapshot, 16);
    int sectorOffset = snapshotI32(snapshot, 24);
    int sides = snapshotI32(snapshot, 192);
    int sideOffset = snapshotI32(snapshot, 196);
    for (int sector = 0; sector < sectors; sector++) {
      int at = sectorOffset + sector * 16;
      sectorFloor[sector] = (short) (snapshotI32(snapshot, at) >> 16);
      sectorCeiling[sector] =
          (short) (snapshotI32(snapshot, at + 4) >> 16);
      sectorLight[sector] = (byte) snapshotI16(snapshot, at + 8);
      sectorFloorAsset[sector] = translatedFlat(
          snapshotU16(snapshot, at + 10), sectorFloorAsset[sector]);
      sectorCeilingAsset[sector] = translatedFlat(
          snapshotU16(snapshot, at + 12), sectorCeilingAsset[sector]);
    }
    for (int side = 0; side < sides; side++) {
      int at = sideOffset + side * 8;
      dynamicSideTop[side] = translatedWall(snapshotU16(snapshot, at));
      dynamicSideBottom[side] =
          translatedWall(snapshotU16(snapshot, at + 2));
      dynamicSideMiddle[side] =
          translatedWall(snapshotU16(snapshot, at + 4));
    }
  }

  private static int renderLoadedWorldGeometry(Uint8Array snapshot) {
    int checksum;
    liveDynamicsActive = true;
    try {
      checksum = renderView(
          snapshotI32(snapshot, 36),
          snapshotI32(snapshot, 40),
          snapshotI32(snapshot, 48),
          snapshotI32(snapshot, 52),
          snapshotI32(snapshot, 8),
          true,
          true,
          true);
    } finally {
      liveDynamicsActive = false;
    }
    return checksum;
  }

  @JSExport
  public static int renderTitleFrame() {
    if (uiTexels == null) {
      throw new IllegalStateException("UI textures are not finalized");
    }
    clearFrame();
    blitUi(uiTitle, 0, 0);
    return frameChecksum();
  }

  /**
   * Compatibility entry point for the first selected item on a menu page.
   */
  @JSExport
  public static int renderMenuFrame(int page) {
    return renderMenuSelectionFrame(page, 0, 0);
  }

  /**
   * Database-authored Doom menu. Page 0 is the main menu, 1 is episode
   * selection, 2 is skill selection and 3 is options. Selection and skull
   * animation are presentation inputs; the final pixels are still produced
   * entirely by this MLE renderer.
   */
  @JSExport
  public static int renderMenuSelectionFrame(
      int page, int selection, int tic) {
    renderTitleFrame();
    char[] items;
    int header;
    int y;
    if (page == 1) {
      header = uiEpisode;
      items = uiEpisodeMenuItems;
      y = 72;
    } else if (page == 2) {
      header = uiSkill;
      items = uiSkillMenuItems;
      y = 68;
    } else if (page == 3) {
      header = uiOptions;
      items = uiOptionMenuItems;
      y = 56;
    } else {
      // TITLEPIC already carries Freedoom's full logo. M_DOOM is retained in
      // the pack for in-game overlays, but drawing both duplicates the logo.
      header = -1;
      items = uiMainMenuItems;
      y = 64;
    }
    if (header >= 0) {
      blitUi(header, (WIDTH - uiWidth[header]) / 2, 28);
    }
    selection = Math.max(0, Math.min(items.length - 1, selection));
    int lineHeight = 16;
    int minimumX = WIDTH;
    for (int item : items) {
      minimumX = Math.min(minimumX, (WIDTH - uiWidth[item]) / 2);
    }
    for (int index = 0; index < items.length; index++) {
      int item = items[index];
      blitUi(item, (WIDTH - uiWidth[item]) / 2, y + index * lineHeight);
    }
    int skull = uiMenuSkulls[(tic / 8) & 1];
    blitUi(skull, minimumX - uiWidth[skull] - 5,
        y + selection * lineHeight - 3);
    return frameChecksum();
  }

  /**
   * Render full-screen loading/help/intermission/finale art by stable screen
   * id: title, credit, help1, help2, intermission, victory, end, finale-left,
   * finale-right and boss backdrop.
   */
  @JSExport
  public static int renderScreenFrame(int screen) {
    if (uiTexels == null) {
      throw new IllegalStateException("UI textures are not finalized");
    }
    screen = Math.max(0, Math.min(uiFullScreens.length - 1, screen));
    clearFrame();
    blitUi(uiFullScreens[screen], 0, 0);
    return frameChecksum();
  }

  private static void clearFrame() {
    for (int index = 0; index < frame.length; index++) frame[index] = 0;
  }

  private static int frameChecksum() {
    int checksum = 1;
    for (int index = 0; index < frame.length; index += 257) {
      checksum = checksum * 31 + (frame[index] & 255);
    }
    return checksum;
  }

  /** Geometry-only counterpart used to measure the live snapshot boundary. */
  @JSExport
  public static int renderPlayerSnapshotGeometry(Uint8Array snapshot) {
    if (snapshot == null || snapshot.getLength() != 32) {
      throw new IllegalArgumentException("player snapshot must be 32 bytes");
    }
    return renderView(
        snapshotI32(snapshot, 0),
        snapshotI32(snapshot, 4),
        snapshotI32(snapshot, 8),
        snapshotI32(snapshot, 12),
        0,
        false,
        false,
        true);
  }

  @JSExport
  public static int renderCommands(int pose) {
    commandLength = 0;
    commandCaptureWidth = WIDTH;
    captureCommands = true;
    try {
      render(pose, false, false, true);
    } finally {
      captureCommands = false;
      commandCaptureWidth = WIDTH;
    }
    return commandLength / COMMAND_BYTES;
  }

  /** 160-column command tape for a horizontally doubled live framebuffer. */
  @JSExport
  public static int renderCommandsHalfWidth(int pose) {
    commandLength = 0;
    commandCaptureWidth = LIVE_RENDER_WIDTH;
    captureCommands = true;
    try {
      render(pose, false, false, true);
    } finally {
      captureCommands = false;
      commandCaptureWidth = WIDTH;
    }
    return commandLength / COMMAND_BYTES;
  }

  @JSExport
  public static int renderResolvedCommands(int pose) {
    if (litTextures == null) {
      throw new IllegalStateException("wall textures are not finalized");
    }
    commandLength = 0;
    captureResolvedCommands = true;
    try {
      render(pose, false, false, true);
    } finally {
      captureResolvedCommands = false;
    }
    return commandLength / RESOLVED_COMMAND_BYTES;
  }

  @JSExport
  public static int renderNativeTape(int pose) {
    commandLength = 16;
    nativeCommandCount = 0;
    nativeMissCount = 0;
    captureNativeTape = true;
    try {
      render(pose, false, false, true);
    } finally {
      captureNativeTape = false;
    }
    putI32(0, NATIVE_TAPE_MAGIC);
    putI32(4, nativeCommandCount);
    putI32(8, nativeMissCount);
    putI32(12, commandLength);
    return commandLength;
  }

  private static int render(
      int pose, boolean raster, boolean planes, boolean walls) {
    pose %= poseCount;
    int at = poseOffset + pose * poseRecordBytes;
    return renderView(
        i32(at), i32(at + 4), i32(at + 8), i32(at + 12), pose,
        raster, planes, walls);
  }

  private static int renderView(
      int playerXFixed, int playerYFixed, int angleHigh,
      int viewZFixed, int sample, boolean raster, boolean planes,
      boolean walls) {
    double playerX = playerXFixed / 65536.0;
    double playerY = playerYFixed / 65536.0;
    int angle = (angleHigh >>> 5) & 2047;
    double viewZ = viewZFixed / 65536.0;
    double directionX = cosTable[angle] / 32767.0;
    double directionY = sinTable[angle] / 32767.0;
    rasterPixelWrites = 0;
    activeWidth = raster
        ? LIVE_RENDER_WIDTH
        : (captureCommands ? commandCaptureWidth : WIDTH);
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
    for (int x = 0; x < activeWidth; x++) {
      clipTop[x] = 0;
      clipBottom[x] = VIEW_HEIGHT - 1;
      solidDepth[x] = Double.POSITIVE_INFINITY;
    }
    if (raster) {
      for (int index = 0; index < wallDepth.length; index++) {
        wallDepth[index] = Double.POSITIVE_INFINITY;
      }
    }
    int stackSize = 1;
    stack[0] = nodeX.length - 1;
    stackCheck[0] = -1;
    int checksum = 0;
    while (stackSize > 0) {
      int item = stack[--stackSize];
      int pending = stackCheck[stackSize];
      if (pending >= 0
          && !bboxVisible(pending, playerX, playerY, directionX, directionY)) {
        continue;
      }
      if (item >= 0) {
        int side = ((playerX - nodeX[item]) * nodeDy[item]
            - (playerY - nodeY[item]) * nodeDx[item]) >= 0 ? 0 : 1;
        stack[stackSize] = side == 0 ? nodeChild1[item] : nodeChild0[item];
        stackCheck[stackSize++] = (short) (item * 2 + (side ^ 1));
        stack[stackSize] = side == 0 ? nodeChild0[item] : nodeChild1[item];
        stackCheck[stackSize++] = -1;
        continue;
      }
      int subsector = item & 0x7fffffff;
      int first = ssectorFirst[subsector];
      int end = first + ssectorCount[subsector];
      for (int seg = first; seg < end; seg++) {
        int line = segLine[seg];
        boolean fromRight = segDirection[seg] == 0;
        boolean playerRight = ((playerX - lineX1[line])
            * (lineY2[line] - lineY1[line])
            - (playerY - lineY1[line]) * (lineX2[line] - lineX1[line])) >= 0;
        if (playerRight != fromRight) continue;
        int near = fromRight ? lineRightSector[line] : lineLeftSector[line];
        int far = fromRight ? lineLeftSector[line] : lineRightSector[line];
        int rightSide = lineRightSide[line];
        int leftSide = lineLeftSide[line];
        int side = fromRight ? rightSide : leftSide;
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
        boolean clipOnly = far != 0xffff
            && !(sectorCeiling[far] < sectorCeiling[near] && upper != 0xffff)
            && !(sectorFloor[far] > sectorFloor[near] && lower != 0xffff);

        double ax = segX1[seg] - playerX;
        double ay = segY1[seg] - playerY;
        double bx = segX2[seg] - playerX;
        double by = segY2[seg] - playerY;
        double ad = ax * directionX + ay * directionY;
        double bd = bx * directionX + by * directionY;
        double as = -ax * directionY + ay * directionX;
        double bs = -bx * directionY + by * directionX;
        if (ad <= .01 && bd <= .01) continue;
        if (ad <= .01) {
          double fraction = (.01 - ad) / (bd - ad);
          as += (bs - as) * fraction;
          ad = .01;
        } else if (bd <= .01) {
          double fraction = (.01 - bd) / (ad - bd);
          bs += (as - bs) * fraction;
          bd = .01;
        }
        int start = Math.max(0,
            (int) Math.ceil(Math.min(
                activeWidth / 2.0 + as / ad * activeWidth / 2.0,
                activeWidth / 2.0 + bs / bd * activeWidth / 2.0) - .5));
        int finish = Math.min(activeWidth - 1,
            (int) Math.floor(Math.max(
                activeWidth / 2.0 + as / ad * activeWidth / 2.0,
                activeWidth / 2.0 + bs / bd * activeWidth / 2.0) - .5));
        if (start > finish) continue;
        int segmentX = segX2[seg] - segX1[seg];
        int segmentY = segY2[seg] - segY1[seg];
        double offsetX = segX1[seg] - playerX;
        double offsetY = segY1[seg] - playerY;
        double numerator = offsetX * segmentY - offsetY * segmentX;
        double base = directionX * segmentY - directionY * segmentX;
        double slope = -directionY * segmentY - directionX * segmentX;
        double denominator = base
            + slope * ((start * 2 + 1) / (double) activeWidth - 1);
        double denominatorStep = slope * 2 / activeWidth;
        for (int x = start; x <= finish; x++) {
          double current = denominator;
          denominator += denominatorStep;
          if (clipTop[x] > clipBottom[x] || Math.abs(current) < .000001) {
            continue;
          }
          int wallHeight = (int) Math.floor(20480 * current / numerator);
          if (wallHeight < 1) continue;
          if (wallHeight > 65535) wallHeight = 65535;
          checksum += wallHeight + line;
          if (far == 0xffff) {
            solidDepth[x] = Math.min(solidDepth[x], numerator / current);
            int texture = middle;
            if (texture == 0xffff) texture = lineTexture[line];
            int nearTop = (int) Math.floor(
                VIEW_HEIGHT / 2.0
                  - (sectorCeiling[near] - viewZ) * wallHeight / 128);
            int nearBottom = (int) Math.ceil(
                VIEW_HEIGHT / 2.0
                  - (sectorFloor[near] - viewZ) * wallHeight / 128) - 1;
            if (recordVisplanes) {
              recordPlaneRange(
                  near, true, x, clipTop[x],
                  Math.min(clipBottom[x], nearTop - 1));
              recordPlaneRange(
                  near, false, x,
                  Math.max(clipTop[x], nearBottom + 1), clipBottom[x]);
            }
            if (raster || captureCommands || captureResolvedCommands
                || captureNativeTape) {
              int textureX = textureX(
                  x, line, fromRight, numerator / current,
                  playerX, playerY, directionX, directionY);
              drawWallSegment(
                  x, texture, textureX, wallHeight, nearTop, nearBottom,
                  clipTop[x], clipBottom[x], lightMap(near),
                  fromRight ? lineYOffset[line] : lineLeftYOffset[line],
                  numerator / current);
            }
            clipTop[x] = 1;
            clipBottom[x] = 0;
          } else {
            int openingCeiling = Math.min(sectorCeiling[near], sectorCeiling[far]);
            int openingFloor = Math.max(sectorFloor[near], sectorFloor[far]);
            int openingTop = (int) Math.floor(
                VIEW_HEIGHT / 2.0
                    - (openingCeiling - viewZ) * wallHeight / 128);
            int openingBottom = (int) Math.ceil(
                VIEW_HEIGHT / 2.0
                    - (openingFloor - viewZ) * wallHeight / 128) - 1;
            int nearTop = (int) Math.floor(
                VIEW_HEIGHT / 2.0
                    - (sectorCeiling[near] - viewZ) * wallHeight / 128);
            int nearBottom = (int) Math.ceil(
                VIEW_HEIGHT / 2.0
                    - (sectorFloor[near] - viewZ) * wallHeight / 128) - 1;
            if (recordVisplanes) {
              recordPlaneRange(
                  near, true, x, clipTop[x],
                  Math.min(clipBottom[x], nearTop - 1));
              recordPlaneRange(
                  near, false, x,
                  Math.max(clipTop[x], nearBottom + 1), clipBottom[x]);
            }
            if ((raster || captureCommands || captureResolvedCommands
                || captureNativeTape) && !clipOnly) {
              boolean drawUpper = sectorCeiling[far] < sectorCeiling[near]
                  && upper != 0xffff && nearTop <= clipBottom[x]
                  && openingTop - 1 >= clipTop[x];
              boolean drawLower = sectorFloor[far] > sectorFloor[near]
                  && lower != 0xffff && openingBottom + 1 <= clipBottom[x]
                  && nearBottom >= clipTop[x];
              if (drawUpper || drawLower) {
                int textureX = textureX(
                    x, line, fromRight, numerator / current,
                    playerX, playerY, directionX, directionY);
                int lightMap = lightMap(near);
                int yOffset = fromRight
                    ? lineYOffset[line] : lineLeftYOffset[line];
                if (drawUpper) {
                  drawWallSegment(
                      x, upper, textureX, wallHeight, nearTop, openingTop - 1,
                      clipTop[x], clipBottom[x], lightMap, yOffset,
                      numerator / current);
                }
                if (drawLower) {
                  drawWallSegment(
                      x, lower, textureX, wallHeight, openingBottom + 1,
                      nearBottom, clipTop[x], clipBottom[x], lightMap, yOffset,
                      numerator / current);
                }
              }
            }
            clipTop[x] = Math.max(clipTop[x], openingTop);
            clipBottom[x] = Math.min(clipBottom[x], openingBottom);
            if (!clipOnly) checksum ^= (upper << 1) ^ (lower << 2);
          }
        }
      }
    }
    if (recordVisplanes) {
      drawRecordedPlanes(
          playerX, playerY, viewZ, directionX, directionY);
    }
    if (raster) {
      checksum ^= (frame[sample % PIXELS] & 255)
          | ((frame[(sample * 997) % PIXELS] & 255) << 8);
    }
    return checksum;
  }

  private static int snapshotI32(Uint8Array snapshot, int offset) {
    return (snapshot.get(offset) & 255)
        | ((snapshot.get(offset + 1) & 255) << 8)
        | ((snapshot.get(offset + 2) & 255) << 16)
        | ((snapshot.get(offset + 3) & 255) << 24);
  }

  private static int snapshotI16(Uint8Array snapshot, int offset) {
    int value = (snapshot.get(offset) & 255)
        | ((snapshot.get(offset + 1) & 255) << 8);
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

  private static int spriteLookup(int sprite, int frame, int rotation) {
    frame &= 0x7fff;
    if (sprite < 0 || sprite >= spritePrefixCount
        || frame < 0 || frame >= spriteFrameCount) {
      return -1;
    }
    int lookup = (sprite * spriteFrameCount + frame) * 9 + rotation;
    int asset = spriteLookupAsset[lookup];
    if (asset == 0xffff && rotation != 0) {
      lookup -= rotation;
      asset = spriteLookupAsset[lookup];
    }
    return asset == 0xffff ? -1 : lookup;
  }

  private static void drawWorldSprites(
      Uint8Array snapshot, int mobjOffset, int mobjCount) {
    double playerX = snapshotI32(snapshot, 36) / 65536.0;
    double playerY = snapshotI32(snapshot, 40) / 65536.0;
    int viewAngle = (snapshotI32(snapshot, 48) >>> 5) & 2047;
    double directionX = cosTable[viewAngle] / 32767.0;
    double directionY = sinTable[viewAngle] / 32767.0;
    int visible = 0;
    for (int mobj = 0; mobj < mobjCount; mobj++) {
      int at = mobjOffset + mobj * 32;
      double dx = snapshotI32(snapshot, at) / 65536.0 - playerX;
      double dy = snapshotI32(snapshot, at + 4) / 65536.0 - playerY;
      double depth = dx * directionX + dy * directionY;
      double lateral = -dx * directionY + dy * directionX;
      if (depth <= 1.0 || Math.abs(lateral) > depth * 1.5) continue;
      int sprite = snapshotI16(snapshot, at + 16);
      int spriteFrame = snapshotI16(snapshot, at + 18);
      if (spriteLookup(sprite, spriteFrame, 0) < 0
          && spriteLookup(sprite, spriteFrame, 1) < 0) {
        continue;
      }
      int insert = visible;
      while (insert > 0 && worldSpriteDepth[insert - 1] < depth) {
        worldSpriteDepth[insert] = worldSpriteDepth[insert - 1];
        worldSpriteOrder[insert] = worldSpriteOrder[insert - 1];
        insert--;
      }
      worldSpriteDepth[insert] = depth;
      worldSpriteOrder[insert] = mobj;
      visible++;
    }
    for (int index = 0; index < visible; index++) {
      drawWorldSprite(
          snapshot, mobjOffset + worldSpriteOrder[index] * 32,
          playerX, playerY, directionX, directionY,
          worldSpriteDepth[index]);
    }
  }

  private static void drawWorldSprite(
      Uint8Array snapshot, int at,
      double playerX, double playerY,
      double directionX, double directionY, double depth) {
    double mobjX = snapshotI32(snapshot, at) / 65536.0;
    double mobjY = snapshotI32(snapshot, at + 4) / 65536.0;
    double mobjZ = snapshotI32(snapshot, at + 8) / 65536.0;
    int mobjAngle = snapshotI32(snapshot, at + 12) & 0xffff;
    int sprite = snapshotI16(snapshot, at + 16);
    int spriteFrame = snapshotI16(snapshot, at + 18);
    int viewerOctant = 0;
    double viewerX = playerX - mobjX;
    double viewerY = playerY - mobjY;
    double bestDot = -Double.MAX_VALUE;
    for (int octant = 0; octant < 8; octant++) {
      int angle = octant * 256;
      double dot = viewerX * cosTable[angle]
          + viewerY * sinTable[angle];
      if (dot > bestDot) {
        bestDot = dot;
        viewerOctant = octant;
      }
    }
    int viewerAngle = viewerOctant * 8192;
    int rotation =
        (((viewerAngle - mobjAngle + 36864) & 0xffff) >>> 13) + 1;
    int lookup = spriteLookup(sprite, spriteFrame, rotation);
    if (lookup < 0) return;
    int asset = spriteLookupAsset[lookup];
    boolean flip = spriteLookupFlip[lookup] != 0;
    int width = spriteWidth[asset];
    int height = spriteHeight[asset];
    double lateral = -(mobjX - playerX) * directionY
        + (mobjY - playerY) * directionX;
    double scale = (LIVE_RENDER_WIDTH / 2.0) / depth;
    double center = LIVE_RENDER_WIDTH / 2.0
        + lateral * (LIVE_RENDER_WIDTH / 2.0) / depth;
    int left = (int) Math.floor(center - spriteLeft[asset] * scale);
    int right = (int) Math.ceil(
        center + (width - spriteLeft[asset]) * scale) - 1;
    double viewZ = snapshotI32(snapshot, 52) / 65536.0;
    int top = (int) Math.floor(
        VIEW_HEIGHT / 2.0
            - (mobjZ + spriteTop[asset] - viewZ) * scale);
    int bottom = (int) Math.ceil(
        VIEW_HEIGHT / 2.0
            - (mobjZ + spriteTop[asset] - height - viewZ) * scale) - 1;
    int screenWidth = right - left + 1;
    int screenHeight = bottom - top + 1;
    if (screenWidth < 1 || screenHeight < 1) return;
    int sector = snapshotI16(snapshot, at + 30);
    int map = (spriteFrame & 0x8000) != 0 || sector < 0
        || sector >= sectorCount ? 0 : lightMap(sector);
    int sourceBase = spriteBase[asset];
    for (int x = Math.max(0, left);
         x <= Math.min(LIVE_RENDER_WIDTH - 1, right); x++) {
      if (depth >= solidDepth[x]) continue;
      int sourceX = (x - left) * width / screenWidth;
      if (flip) sourceX = width - sourceX - 1;
      int outputX = x * 2;
      for (int y = Math.max(0, top);
           y <= Math.min(VIEW_HEIGHT - 1, bottom); y++) {
        if (depth >= wallDepth[x * VIEW_HEIGHT + y]) continue;
        int sourceY = (y - top) * height / screenHeight;
        int encoded = spriteTexels[
            sourceBase + sourceY * width + sourceX];
        if (encoded == 0) continue;
        byte pixel = colormaps[map * 256 + encoded - 1];
        frame[outputX * FRAME_HEIGHT + y] = pixel;
        frame[(outputX + 1) * FRAME_HEIGHT + y] = pixel;
      }
    }
  }

  private static void drawPlayerSprites(Uint8Array snapshot) {
    for (int psprite = 0; psprite < 2; psprite++) {
      int at = 88 + psprite * 20;
      int sprite = snapshotI32(snapshot, at + 12);
      int spriteFrame = snapshotI32(snapshot, at + 16);
      int lookup = spriteLookup(sprite, spriteFrame, 0);
      if (lookup < 0) continue;
      int asset = spriteLookupAsset[lookup];
      int width = spriteWidth[asset];
      int height = spriteHeight[asset];
      int sx = snapshotI32(snapshot, at + 4) >> 16;
      int sy = snapshotI32(snapshot, at + 8) >> 16;
      // Doom's WEAPONTOP is 32. A newly spawned weapon begins at
      // WEAPONBOTTOM (128-ish) and rises into place; anchoring against the
      // tic-1 value made the ready weapon float 84 pixels too high.
      int left = (WIDTH - width) / 2 + sx;
      int top = VIEW_HEIGHT - height + sy - 32;
      blitSprite(asset, left, top, 0);
    }
  }

  private static void drawStatusBar(Uint8Array snapshot) {
    if (!statusBarInitialized) {
      for (int x = 0; x < WIDTH; x++) {
        System.arraycopy(
            statusBarBackground, x * (FRAME_HEIGHT - VIEW_HEIGHT),
            frame, x * FRAME_HEIGHT + VIEW_HEIGHT,
            FRAME_HEIGHT - VIEW_HEIGHT);
      }
      statusBarInitialized = true;
    } else {
      // The world raster never writes the bottom 32 rows.  Preserve the
      // invariant status-bar background and restore only rectangles whose
      // widgets can change, rather than issuing 320 tiny array copies.
      restoreStatusRect(4, 44, 168, FRAME_HEIGHT);
      restoreStatusRect(51, 90, 168, FRAME_HEIGHT);
      restoreStatusRect(142, 185, 168, FRAME_HEIGHT);
      restoreStatusRect(182, 221, 168, FRAME_HEIGHT);
      restoreStatusRect(238, 269, 168, FRAME_HEIGHT);
    }
    int ammo = snapshotI32(snapshot, 72);
    int weapon = snapshotI32(snapshot, 64);
    if (weapon == 2 || weapon == 8) ammo = snapshotI32(snapshot, 76);
    else if (weapon == 4) ammo = snapshotI32(snapshot, 80);
    else if (weapon == 5 || weapon == 6) ammo = snapshotI32(snapshot, 84);
    drawHudNumber(Math.max(0, ammo), 44);
    int health = Math.max(0, snapshotI32(snapshot, 56));
    int armor = Math.max(0, snapshotI32(snapshot, 60));
    drawHudNumber(health, 90);
    drawHudNumber(armor, 221);
    // STFB0 is the player-color background behind Doomguy's animated face.
    blitUi(uiFaceNormal, 143, 169);
    int pain = Math.max(0, Math.min(4, (100 - health) * 5 / 101));
    int damage = snapshotI32(snapshot, 128);
    int bonus = snapshotI32(snapshot, 132);
    int cheats = snapshotI32(snapshot, 168);
    int refire = snapshotI32(snapshot, 180);
    int tic = snapshotI32(snapshot, 8);
    int face;
    if (health <= 0) {
      face = uiFaceDead;
    } else if ((cheats & 1) != 0) {
      face = uiFaceGod;
    } else if (damage > 20) {
      face = uiFaceOuch[pain];
    } else if (damage > 0) {
      face = (tic & 8) == 0
          ? uiFaceTurnLeft[pain] : uiFaceTurnRight[pain];
    } else if (bonus > 0) {
      face = uiFaceEvil[pain];
    } else if (refire > 2) {
      face = uiFaceKill[pain];
    } else {
      face = uiFaceStraight[pain * 3 + (tic / 17) % 3];
    }
    blitUi(face, 148, 169);
    int cards = snapshotI32(snapshot, 144);
    for (int key = 0; key < 6; key++) {
      if ((cards & (1 << key)) != 0) {
        blitUi(uiKeys[key], 239 + (key % 3) * 10, 171);
      }
    }
  }

  private static void restoreStatusRect(
      int left, int right, int top, int bottom) {
    int clippedLeft = Math.max(0, left);
    int clippedRight = Math.min(WIDTH, right);
    int clippedTop = Math.max(VIEW_HEIGHT, top);
    int clippedBottom = Math.min(FRAME_HEIGHT, bottom);
    int height = clippedBottom - clippedTop;
    if (height <= 0) return;
    for (int x = clippedLeft; x < clippedRight; x++) {
      System.arraycopy(
          statusBarBackground,
          x * (FRAME_HEIGHT - VIEW_HEIGHT) + clippedTop - VIEW_HEIGHT,
          frame, x * FRAME_HEIGHT + clippedTop, height);
    }
  }

  private static void drawHudNumber(int value, int rightEdge) {
    value = Math.min(999, value);
    int hundreds = value / 100;
    int tens = (value / 10) % 10;
    if (hundreds > 0) blitUi(uiDigits[hundreds], rightEdge - 39, 171);
    if (hundreds > 0 || tens > 0) {
      blitUi(uiDigits[tens], rightEdge - 26, 171);
    }
    blitUi(uiDigits[value % 10], rightEdge - 13, 171);
  }

  private static void blitSprite(
      int asset, int left, int top, int map) {
    int width = spriteWidth[asset];
    int height = spriteHeight[asset];
    int base = spriteBase[asset];
    for (int y = 0; y < height; y++) {
      int screenY = top + y;
      if (screenY < 0 || screenY >= VIEW_HEIGHT) continue;
      for (int x = 0; x < width; x++) {
        int screenX = left + x;
        if (screenX < 0 || screenX >= WIDTH) continue;
        int encoded = spriteTexels[base + y * width + x];
        if (encoded != 0) {
          frame[screenX * FRAME_HEIGHT + screenY] =
              colormaps[map * 256 + encoded - 1];
        }
      }
    }
  }

  private static void blitUi(int asset, int left, int top) {
    for (int run = uiAssetRunStart[asset];
         run < uiAssetRunEnd[asset]; run++) {
      int screenX = left + uiRunX[run];
      int screenY = top + uiRunY[run];
      int source = uiRunPixelStart[run];
      int length = uiRunLength[run];
      if (screenX < 0 || screenX >= WIDTH
          || screenY >= FRAME_HEIGHT || screenY + length <= 0) continue;
      if (screenY < 0) {
        source -= screenY;
        length += screenY;
        screenY = 0;
      }
      if (screenY + length > FRAME_HEIGHT) {
        length = FRAME_HEIGHT - screenY;
      }
      if (length > 0) {
        System.arraycopy(
            uiRunPixels, source,
            frame, screenX * FRAME_HEIGHT + screenY, length);
      }
    }
  }

  private static int pointSector(double playerX, double playerY) {
    int child = nodeX.length - 1;
    while (child >= 0) {
      int side = ((playerX - nodeX[child]) * nodeDy[child]
          - (playerY - nodeY[child]) * nodeDx[child]) >= 0 ? 0 : 1;
      child = side == 0 ? nodeChild0[child] : nodeChild1[child];
    }
    int subsector = child & 0x7fffffff;
    if (subsector < 0 || subsector >= subsectorSector.length) {
      throw new IllegalStateException("player subsector outside map");
    }
    return subsectorSector[subsector];
  }

  private static void startPlaneFrame() {
    planeSerial++;
    if (planeSerial == 0) {
      for (int index = 0; index < planeStamp.length; index++) {
        planeStamp[index] = 0;
      }
      planeSerial = 1;
    }
    touchedPlaneCount = 0;
  }

  private static void recordPlaneRange(
      int sector, boolean ceiling, int x, int top, int bottom) {
    top = Math.max(0, top);
    bottom = Math.min(VIEW_HEIGHT - 1, bottom);
    if (top > bottom || x < 0 || x >= activeWidth) return;
    int plane = sector * 2 + (ceiling ? 0 : 1);
    if (planeStamp[plane] != planeSerial) {
      planeStamp[plane] = planeSerial;
      touchedPlanes[touchedPlaneCount++] = plane;
      planeMinX[plane] = x;
      planeMaxX[plane] = x;
      int base = plane * LIVE_RENDER_WIDTH;
      for (int column = 0; column < activeWidth; column++) {
        planeTop[base + column] = VIEW_HEIGHT;
        planeBottom[base + column] = -1;
      }
    } else {
      planeMinX[plane] = Math.min(planeMinX[plane], x);
      planeMaxX[plane] = Math.max(planeMaxX[plane], x);
    }
    int at = plane * LIVE_RENDER_WIDTH + x;
    planeTop[at] = (short) Math.min(planeTop[at], top);
    planeBottom[at] = (short) Math.max(planeBottom[at], bottom);
  }

  private static void drawRecordedPlanes(
      double playerX, double playerY, double viewZ,
      double directionX, double directionY) {
    for (int touched = 0; touched < touchedPlaneCount; touched++) {
      int plane = touchedPlanes[touched];
      int base = plane * LIVE_RENDER_WIDTH;
      int minimum = planeMinX[plane];
      int maximum = planeMaxX[plane];
      int previousTop = VIEW_HEIGHT;
      int previousBottom = -1;
      for (int x = minimum; x <= maximum + 1; x++) {
        int top = x <= maximum ? planeTop[base + x] : VIEW_HEIGHT;
        int bottom = x <= maximum ? planeBottom[base + x] : -1;
        while (previousTop < top && previousTop <= previousBottom) {
          drawPlaneSpan(
              plane, previousTop, spanStart[previousTop], x - 1,
              playerX, playerY, viewZ, directionX, directionY);
          previousTop++;
        }
        while (previousBottom > bottom && previousBottom >= previousTop) {
          drawPlaneSpan(
              plane, previousBottom, spanStart[previousBottom], x - 1,
              playerX, playerY, viewZ, directionX, directionY);
          previousBottom--;
        }
        while (top < previousTop && top <= bottom) {
          spanStart[top++] = x;
        }
        while (bottom > previousBottom && bottom >= top) {
          spanStart[bottom--] = x;
        }
        previousTop = x <= maximum ? planeTop[base + x] : VIEW_HEIGHT;
        previousBottom = x <= maximum ? planeBottom[base + x] : -1;
      }
    }
  }

  private static void drawPlaneSpan(
      int plane, int y, int x1, int x2,
      double playerX, double playerY, double viewZ,
      double directionX, double directionY) {
    if (x1 > x2 || y == VIEW_HEIGHT / 2
        || (coarseVerticalRaster && (y & 1) != 0)) return;
    int sector = plane / 2;
    boolean ceiling = (plane & 1) == 0;
    int asset = ceiling ? sectorCeilingAsset[sector] : sectorFloorAsset[sector];
    if (ceiling && asset == 0xffff) {
      byte pixel = backgroundColumn[y];
      int output = x1 * pixelScale * FRAME_HEIGHT + y;
      for (int x = x1; x <= x2; x++) {
        frame[output] = pixel;
        frame[output + FRAME_HEIGHT] = pixel;
        if (coarseVerticalRaster && y + 1 < VIEW_HEIGHT) {
          frame[output + 1] = pixel;
          frame[output + FRAME_HEIGHT + 1] = pixel;
        }
        output += pixelScale * FRAME_HEIGHT;
      }
      rasterPixelWrites += (x2 - x1 + 1) * pixelScale;
      return;
    }
    double planeHeight = ceiling
        ? sectorCeiling[sector] - viewZ : viewZ - sectorFloor[sector];
    double distance = planeHeight * (activeWidth / 2.0)
        / Math.abs(y + .5 - VIEW_HEIGHT / 2.0);
    double cameraX = (x1 * 2 + 1) / (double) activeWidth - 1.0;
    double rayX = directionX - directionY * cameraX;
    double rayY = directionY + directionX * cameraX;
    int worldX = (int) Math.floor(
        (playerX + rayX * distance) * 65536.0);
    int worldY = (int) Math.floor(
        (playerY + rayY * distance) * 65536.0);
    int stepX = (int) Math.floor(
        (-directionY / (activeWidth / 2.0) * distance) * 65536.0);
    int stepY = (int) Math.floor(
        (directionX / (activeWidth / 2.0) * distance) * 65536.0);
    int bank = lightToBank[lightMap(sector)] * flatTextureElements;
    int assetBase = bank + asset * 4096;
    int output = x1 * pixelScale * FRAME_HEIGHT + y;
    for (int x = x1; x <= x2; x++) {
      int source = ((worldY >> 10) & 4032) + ((worldX >> 16) & 63);
      byte pixel = litFlats[assetBase + source];
      frame[output] = pixel;
      frame[output + FRAME_HEIGHT] = pixel;
      if (coarseVerticalRaster && y + 1 < VIEW_HEIGHT) {
        frame[output + 1] = pixel;
        frame[output + FRAME_HEIGHT + 1] = pixel;
      }
      output += pixelScale * FRAME_HEIGHT;
      worldX += stepX;
      worldY += stepY;
    }
    rasterPixelWrites += (x2 - x1 + 1) * pixelScale;
  }

  /**
   * Doom's plane mapping is affine across a screen row. Compute the expensive
   * perspective division and fixed-point increments once per row, not once
   * per pixel. This is the same span shape used by the original renderer and
   * avoids 64,000 interpreted Math.floor/multiply sequences.
   */
  private static void drawPlaneBackground(
      int sector, double playerX, double playerY, double viewZ,
      double directionX, double directionY) {
    int lightBank = lightToBank[lightMap(sector)] * flatTextureElements;
    int floorBase = lightBank + sectorFloorAsset[sector] * 4096;
    int ceilingAsset = sectorCeilingAsset[sector];
    int ceilingBase = ceilingAsset == 0xffff
        ? -1 : lightBank + ceilingAsset * 4096;
    for (int y = 0; y < VIEW_HEIGHT;
        y += coarseVerticalRaster ? 2 : 1) {
      if (y == VIEW_HEIGHT / 2) {
        for (int x = 0; x < activeWidth; x++) {
          int output = x * pixelScale * FRAME_HEIGHT + y;
          frame[output] = backgroundColumn[y];
          frame[output + FRAME_HEIGHT] = backgroundColumn[y];
          if (coarseVerticalRaster && y + 1 < VIEW_HEIGHT) {
            frame[output + 1] = backgroundColumn[y];
            frame[output + FRAME_HEIGHT + 1] = backgroundColumn[y];
          }
        }
        continue;
      }
      boolean ceiling = y < VIEW_HEIGHT / 2;
      if (ceiling && ceilingBase < 0) {
        for (int x = 0; x < activeWidth; x++) {
          int output = x * pixelScale * FRAME_HEIGHT + y;
          frame[output] = backgroundColumn[y];
          frame[output + FRAME_HEIGHT] = backgroundColumn[y];
          if (coarseVerticalRaster && y + 1 < VIEW_HEIGHT) {
            frame[output + 1] = backgroundColumn[y];
            frame[output + FRAME_HEIGHT + 1] = backgroundColumn[y];
          }
        }
        continue;
      }
      double plane = ceiling
          ? sectorCeiling[sector] - viewZ : viewZ - sectorFloor[sector];
      double distance = plane * (activeWidth / 2.0)
          / Math.abs(y + .5 - VIEW_HEIGHT / 2.0);
      double firstCamera = .5 / (activeWidth / 2.0) - 1.0;
      double rayX = directionX - directionY * firstCamera;
      double rayY = directionY + directionX * firstCamera;
      int worldX = (int) Math.floor(
          (playerX + rayX * distance) * 65536.0);
      int worldY = (int) Math.floor(
          (playerY + rayY * distance) * 65536.0);
      int stepX = (int) Math.floor(
          (-directionY / (activeWidth / 2.0) * distance) * 65536.0);
      int stepY = (int) Math.floor(
          (directionX / (activeWidth / 2.0) * distance) * 65536.0);
      int assetBase = ceiling ? ceilingBase : floorBase;
      int output = y;
      for (int x = 0; x < activeWidth; x++) {
        int source = ((worldY >> 10) & 4032)
            + ((worldX >> 16) & 63);
        byte pixel = litFlats[assetBase + source];
        frame[output] = pixel;
        frame[output + FRAME_HEIGHT] = pixel;
        if (coarseVerticalRaster && y + 1 < VIEW_HEIGHT) {
          frame[output + 1] = pixel;
          frame[output + FRAME_HEIGHT + 1] = pixel;
        }
        output += pixelScale * FRAME_HEIGHT;
        worldX += stepX;
        worldY += stepY;
      }
    }
    rasterPixelWrites += WIDTH * VIEW_HEIGHT;
  }

  @JSExport
  public static int renderGeometryBatch(int start, int count) {
    int checksum = 0;
    for (int index = 0; index < count; index++) {
      checksum += renderGeometry(start + index);
    }
    return checksum;
  }

  @JSExport
  public static int renderFrameBatch(int start, int count) {
    int checksum = 0;
    for (int index = 0; index < count; index++) {
      checksum += renderFrame(start + index);
    }
    return checksum;
  }

  @JSExport
  @JSByRef
  public static byte[] frameByRef() {
    return frame;
  }

  @JSExport
  @JSByRef
  public static byte[] frameChunk(int offset, int length) {
    if (offset < 0 || length < 0 || offset + length > frame.length) {
      throw new IllegalArgumentException("frame chunk outside framebuffer");
    }
    byte[] chunk = new byte[length];
    System.arraycopy(frame, offset, chunk, 0, length);
    return chunk;
  }

  @JSExport
  @JSByRef
  public static byte[] commandBufferByRef() {
    return commandBuffer;
  }

  @JSExport
  @JSByRef
  public static byte[] nativeTapeChunk(int offset, int length) {
    if (offset < 0 || length < 0 || length > 32767
        || offset + length > commandLength) {
      throw new IllegalArgumentException("native tape chunk outside tape");
    }
    byte[] chunk = new byte[length];
    System.arraycopy(commandBuffer, offset, chunk, 0, length);
    return chunk;
  }

  @JSExport
  @JSByRef
  public static byte[] resolvedCommandChunk(int offset, int length) {
    if (offset < 0 || length < 0 || length > 32767
        || offset + length > commandLength) {
      throw new IllegalArgumentException("resolved command chunk outside tape");
    }
    byte[] chunk = new byte[length];
    System.arraycopy(commandBuffer, offset, chunk, 0, length);
    return chunk;
  }

  @JSExport
  public static int litTextureLength() {
    if (litTextures == null) {
      throw new IllegalStateException("wall textures are not finalized");
    }
    return litTextures.length;
  }

  @JSExport
  @JSByRef
  public static byte[] litTextureChunk(int offset, int length) {
    if (litTextures == null || offset < 0 || length < 0 || length > 32767
        || offset + length > litTextures.length) {
      throw new IllegalArgumentException("lit texture chunk outside atlas");
    }
    byte[] chunk = new byte[length];
    System.arraycopy(litTextures, offset, chunk, 0, length);
    return chunk;
  }

  @JSExport
  public static int nativeTapeRecordChunkLength(int offset, int maximumLength) {
    if (offset < 16 || offset >= commandLength
        || maximumLength < 208 || maximumLength > 32767) {
      throw new IllegalArgumentException("invalid native tape record chunk");
    }
    int at = offset;
    while (at < commandLength) {
      int payload = commandBuffer[at + 7] == 0
          ? 0 : commandBuffer[at + 6] & 255;
      int recordLength = 8 + payload;
      if (at + recordLength - offset > maximumLength) break;
      at += recordLength;
    }
    if (at == offset) {
      throw new IllegalStateException("native tape record exceeds chunk");
    }
    return at - offset;
  }

  @JSExport
  public static int nativeTapeCommandCount() {
    return nativeCommandCount;
  }

  @JSExport
  public static int nativeTapeMissCount() {
    return nativeMissCount;
  }

  @JSExport
  public static int resetNativeCache() {
    for (int index = 0; index < nativeCacheValid.length; index++) {
      nativeCacheValid[index] = 0;
    }
    nativeCommandCount = 0;
    nativeMissCount = 0;
    return nativeCacheValid.length;
  }

  @JSExport
  public static int rasterPixelWrites() {
    return rasterPixelWrites;
  }

  private static int lightMap(int sector) {
    return Math.max(0, Math.min(31, (255 - (sectorLight[sector] & 255)) / 8));
  }

  private static int textureX(
      int screenX, int line, boolean fromRight, double distance,
      double playerX, double playerY, double directionX, double directionY) {
    double cameraX = (screenX * 2 + 1) / (double) activeWidth - 1;
    double rayX = directionX - directionY * cameraX;
    double rayY = directionY + directionX * cameraX;
    int segmentX = lineX2[line] - lineX1[line];
    int segmentY = lineY2[line] - lineY1[line];
    double hitX = playerX + rayX * distance;
    double hitY = playerY + rayY * distance;
    double along = Math.abs(segmentX) >= Math.abs(segmentY)
        ? Math.abs(hitX - lineX1[line]) : Math.abs(hitY - lineY1[line]);
    return (int) Math.floor(along)
        + (fromRight ? lineXOffset[line] : lineLeftXOffset[line]);
  }

  private static void drawWallSegment(
      int screenX, int texture, int textureX, int wallHeight,
      int projectedTop, int projectedBottom, int clipTopValue,
      int clipBottomValue, int lightMap, int verticalOffset, double depth) {
    if (texture == 0xffff || projectedTop > clipBottomValue
        || projectedBottom < clipTopValue || projectedTop > projectedBottom) {
      return;
    }
    int drawTop = Math.max(0, Math.max(clipTopValue, projectedTop));
    int drawBottom = Math.min(
        VIEW_HEIGHT - 1, Math.min(clipBottomValue, projectedBottom));
    if (drawTop > drawBottom) return;
    if (captureCommands) {
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
        screenX, texture, textureX, wallHeight, projectedTop,
        drawTop, drawBottom, lightMap, verticalOffset);
    if (activeWidth == LIVE_RENDER_WIDTH) {
      int base = screenX * VIEW_HEIGHT;
      for (int y = drawTop; y <= drawBottom; y++) {
        wallDepth[base + y] = Math.min(wallDepth[base + y], depth);
      }
    }
  }

  private static void appendCommand(
      int screenX, int texture, int textureX, int wallHeight,
      int projectedTop, int drawTop, int drawBottom,
      int lightMap, int verticalOffset) {
    if (commandLength + COMMAND_BYTES > commandBuffer.length) {
      throw new IllegalStateException("wall command buffer overflow");
    }
    int at = commandLength;
    putU16(at, screenX);
    putU16(at + 2, texture);
    putI32(at + 4, textureX);
    putU16(at + 8, wallHeight);
    commandBuffer[at + 10] = (byte) lightMap;
    commandBuffer[at + 11] = 0;
    putI32(at + 12, projectedTop);
    putU16(at + 16, drawTop);
    putU16(at + 18, drawBottom);
    putI32(at + 20, verticalOffset);
    commandLength += COMMAND_BYTES;
  }

  private static void appendResolvedCommand(
      int screenX, int texture, int textureX, int wallHeight,
      int projectedTop, int drawTop, int drawBottom,
      int lightMap, int verticalOffset) {
    if (commandLength + RESOLVED_COMMAND_BYTES > commandBuffer.length) {
      throw new IllegalStateException("resolved wall command buffer overflow");
    }
    int width = textureWidth[texture];
    int height = textureHeight[texture];
    textureX %= width;
    if (textureX < 0) textureX += width;
    int normalizedOffset = verticalOffset % height;
    if (normalizedOffset < 0) normalizedOffset += height;
    int at = commandLength;
    putI32(at, screenX * FRAME_HEIGHT + drawTop);
    putI32(at + 4,
        lightToBank[lightMap] * wallTextureElements
            + textureBase[texture] + textureX);
    putU16(at + 8, width);
    putU16(at + 10, height);
    putU16(at + 12, wallHeight);
    putU16(at + 14, drawBottom - drawTop + 1);
    putI32(at + 16,
        normalizedOffset * wallHeight + (drawTop - projectedTop) * 128);
    commandLength += RESOLVED_COMMAND_BYTES;
  }

  private static void putU16(int offset, int value) {
    commandBuffer[offset] = (byte) value;
    commandBuffer[offset + 1] = (byte) (value >>> 8);
  }

  private static void putI32(int offset, int value) {
    commandBuffer[offset] = (byte) value;
    commandBuffer[offset + 1] = (byte) (value >>> 8);
    commandBuffer[offset + 2] = (byte) (value >>> 16);
    commandBuffer[offset + 3] = (byte) (value >>> 24);
  }

  private static void appendNativeTape(
      int screenX, int texture, int textureX, int wallHeight,
      int projectedTop, int drawTop, int drawBottom,
      int lightMap, int verticalOffset) {
    int width = textureWidth[texture];
    int height = textureHeight[texture];
    textureX %= width;
    if (textureX < 0) textureX += width;
    int normalizedOffset = verticalOffset % height;
    if (normalizedOffset < 0) normalizedOffset += height;
    int keyA = texture | (textureX << 16);
    int keyB = (Math.min(65535, wallHeight) & 0xffff)
        | (lightMap << 16) | (normalizedOffset << 21);
    int keyC = (projectedTop & 0xffff) | (drawTop << 16) | (drawBottom << 24);
    int hash = keyA ^ keyB * 40503 ^ keyC * 7919;
    hash ^= hash >>> 13;
    hash *= -1640531527;
    hash ^= hash >>> 16;
    int slot = hash & (CACHE_SIZE - 1);
    boolean miss = nativeCacheValid[slot] == 0
        || nativeCacheKeyA[slot] != keyA
        || nativeCacheKeyB[slot] != keyB
        || nativeCacheKeyC[slot] != keyC;
    int length = drawBottom - drawTop + 1;
    int required = 8 + (miss ? length : 0);
    if (commandLength + required > commandBuffer.length) {
      throw new IllegalStateException("native wall tape overflow");
    }
    putI32BigEndian(commandLength, slot);
    putU16BigEndian(commandLength + 4, screenX * FRAME_HEIGHT + drawTop);
    commandBuffer[commandLength + 6] = (byte) length;
    commandBuffer[commandLength + 7] = (byte) (miss ? 1 : 0);
    commandLength += 8;
    nativeCommandCount++;
    if (!miss) return;
    int textureNumerator = normalizedOffset * wallHeight
        + (drawTop - projectedTop) * 128;
    int base = textureBase[texture];
    int bank = lightToBank[lightMap] * wallTextureElements;
    boolean powerOfTwoHeight = (height & (height - 1)) == 0;
    for (int output = 0; output < length; output++) {
      int sourceY = textureNumerator / wallHeight;
      sourceY = powerOfTwoHeight ? sourceY & (height - 1) : sourceY % height;
      commandBuffer[commandLength + output] =
          litTextures[bank + base + sourceY * width + textureX];
      textureNumerator += 128;
    }
    commandLength += length;
    nativeCacheKeyA[slot] = keyA;
    nativeCacheKeyB[slot] = keyB;
    nativeCacheKeyC[slot] = keyC;
    nativeCacheValid[slot] = 1;
    nativeMissCount++;
  }

  private static void putU16BigEndian(int offset, int value) {
    commandBuffer[offset] = (byte) (value >>> 8);
    commandBuffer[offset + 1] = (byte) value;
  }

  private static void putI32BigEndian(int offset, int value) {
    commandBuffer[offset] = (byte) (value >>> 24);
    commandBuffer[offset + 1] = (byte) (value >>> 16);
    commandBuffer[offset + 2] = (byte) (value >>> 8);
    commandBuffer[offset + 3] = (byte) value;
  }

  private static void drawWallPixels(
      int screenX, int texture, int textureX, int wallHeight,
      int projectedTop, int drawTop, int drawBottom,
      int lightMap, int verticalOffset) {
    int width = textureWidth[texture];
    int height = textureHeight[texture];
    textureX %= width;
    if (textureX < 0) textureX += width;
    int normalizedOffset = verticalOffset % height;
    if (normalizedOffset < 0) normalizedOffset += height;
    int length = drawBottom - drawTop + 1;
    int fractionStep = 8388608 / wallHeight; // 128 texels in 16.16.
    int fraction = (normalizedOffset << 16)
        + (drawTop - projectedTop) * fractionStep;
    int base = textureBase[texture];
    int bank = lightToBank[lightMap] * wallTextureElements;
    int outputAt = screenX * pixelScale * FRAME_HEIGHT + drawTop;
    rasterPixelWrites += length * pixelScale;
    boolean powerOfTwoHeight = (height & (height - 1)) == 0;
    int verticalStep = coarseVerticalRaster ? 2 : 1;
    for (int output = 0; output < length; output += verticalStep) {
      int sourceY = fraction >> 16;
      sourceY = powerOfTwoHeight
          ? sourceY & (height - 1)
          : positiveModulo(sourceY, height);
      byte pixel = litTextures[bank + base + sourceY * width + textureX];
      frame[outputAt + output] = pixel;
      frame[outputAt + FRAME_HEIGHT + output] = pixel;
      if (coarseVerticalRaster && output + 1 < length) {
        frame[outputAt + output + 1] = pixel;
        frame[outputAt + FRAME_HEIGHT + output + 1] = pixel;
      }
      fraction += fractionStep * verticalStep;
    }
  }

  private static int positiveModulo(int value, int modulus) {
    int result = value % modulus;
    return result < 0 ? result + modulus : result;
  }

  private static boolean bboxVisible(
      int check, double px, double py, double dx, double dy) {
    int node = check >> 1;
    int side = check & 1;
    int top = side == 0 ? bbox0Top[node] : bbox1Top[node];
    int bottom = side == 0 ? bbox0Bottom[node] : bbox1Bottom[node];
    int left = side == 0 ? bbox0Left[node] : bbox1Left[node];
    int right = side == 0 ? bbox0Right[node] : bbox1Right[node];
    if (px >= left && px <= right && py >= bottom && py <= top) return true;
    double minimumDepth = Double.MAX_VALUE;
    double maximumDepth = -Double.MAX_VALUE;
    double minimumScreen = Double.MAX_VALUE;
    double maximumScreen = -Double.MAX_VALUE;
    for (int corner = 0; corner < 4; corner++) {
      double x = (corner & 1) == 0 ? left : right;
      double y = (corner & 2) == 0 ? bottom : top;
      double rx = x - px;
      double ry = y - py;
      double depth = rx * dx + ry * dy;
      minimumDepth = Math.min(minimumDepth, depth);
      maximumDepth = Math.max(maximumDepth, depth);
      if (depth > .01) {
        double screen = activeWidth / 2.0
            + (-rx * dy + ry * dx) / depth * activeWidth / 2.0;
        minimumScreen = Math.min(minimumScreen, screen);
        maximumScreen = Math.max(maximumScreen, screen);
      }
    }
    if (maximumDepth <= .01) return false;
    if (minimumDepth <= .01) return true;
    int start = Math.max(0, (int) Math.floor(minimumScreen));
    int end = Math.min(activeWidth - 1, (int) Math.ceil(maximumScreen));
    for (int x = start; x <= end; x++) {
      if (clipTop[x] <= clipBottom[x]) return true;
    }
    return false;
  }

  private static int u32(int offset) {
    return (pack[offset] & 255) | ((pack[offset + 1] & 255) << 8)
        | ((pack[offset + 2] & 255) << 16) | (pack[offset + 3] << 24);
  }

  private static int i32(int offset) {
    return u32(offset);
  }

  private static int u16(int offset) {
    return (pack[offset] & 255) | ((pack[offset + 1] & 255) << 8);
  }

  private static int[] ints(int offset, int count) {
    int[] values = new int[count];
    for (int index = 0; index < count; index++) values[index] = i32(offset + index * 4);
    return values;
  }

  private static short[] shorts(int offset, int count) {
    short[] values = new short[count];
    for (int index = 0; index < count; index++) values[index] = (short) u16(offset + index * 2);
    return values;
  }

  private static char[] chars(int offset, int count) {
    char[] values = new char[count];
    for (int index = 0; index < count; index++) values[index] = (char) u16(offset + index * 2);
    return values;
  }

  private static byte[] bytes(int offset, int count) {
    byte[] values = new byte[count];
    System.arraycopy(pack, offset, values, 0, count);
    return values;
  }

  public static void main(String[] args) {}
}
