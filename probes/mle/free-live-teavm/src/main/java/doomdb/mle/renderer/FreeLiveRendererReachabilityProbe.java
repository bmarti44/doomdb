package doomdb.mle.renderer;

import org.teavm.jso.JSExport;
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
  private static final int HEIGHT = 200;
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
  private static short[] sectorFloor;
  private static short[] sectorCeiling;
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
  private static int[] stack;
  private static short[] stackCheck;

  private FreeLiveRendererReachabilityProbe() {}

  @JSExport
  public static int allocatePack(int length) {
    if (length < 288 || length > 1_000_000) {
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
  public static int finalizePack() {
    if (u32(0) != MAGIC || u32(4) != 3 || u32(76) != pack.length) {
      throw new IllegalStateException("pack header mismatch");
    }
    int lineCount = u32(24);
    poseCount = u32(36);
    poseOffset = u32(64);
    poseRecordBytes = u32(176);
    int segCount = u32(180);
    int subsectorCount = u32(184);
    int nodeCount = u32(188);
    int sectorCount = u32(120);
    if (poseCount != 5250 || poseRecordBytes != 32 || nodeCount < 1) {
      throw new IllegalStateException("pack cardinality mismatch");
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
    sectorFloor = shorts(u32(124), sectorCount);
    sectorCeiling = shorts(u32(128), sectorCount);
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
    clipTop = new int[WIDTH];
    clipBottom = new int[WIDTH];
    stack = new int[nodeCount + subsectorCount + 8];
    stackCheck = new short[stack.length];
    return pack.length;
  }

  @JSExport
  public static int renderGeometry(int pose) {
    pose %= poseCount;
    int at = poseOffset + pose * poseRecordBytes;
    double playerX = i32(at) / 65536.0;
    double playerY = i32(at + 4) / 65536.0;
    int angle = (u32(at + 8) >>> 5) & 2047;
    double viewZ = i32(at + 12) / 65536.0;
    double directionX = cosTable[angle] / 32767.0;
    double directionY = sinTable[angle] / 32767.0;
    for (int x = 0; x < WIDTH; x++) {
      clipTop[x] = 0;
      clipBottom[x] = HEIGHT - 1;
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
        int middle = fromRight ? lineRightMiddle[line] : lineLeftMiddle[line];
        if (far != 0xffff && middle == 0xffff
            && sectorFloor[near] == sectorFloor[far]
            && sectorCeiling[near] == sectorCeiling[far]) continue;
        int upper = fromRight ? lineRightUpper[line] : lineLeftUpper[line];
        int lower = fromRight ? lineRightLower[line] : lineLeftLower[line];
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
            (int) Math.ceil(Math.min(WIDTH / 2.0 + as / ad * WIDTH / 2.0,
                WIDTH / 2.0 + bs / bd * WIDTH / 2.0) - .5));
        int finish = Math.min(WIDTH - 1,
            (int) Math.floor(Math.max(WIDTH / 2.0 + as / ad * WIDTH / 2.0,
                WIDTH / 2.0 + bs / bd * WIDTH / 2.0) - .5));
        if (start > finish) continue;
        int segmentX = segX2[seg] - segX1[seg];
        int segmentY = segY2[seg] - segY1[seg];
        double offsetX = segX1[seg] - playerX;
        double offsetY = segY1[seg] - playerY;
        double numerator = offsetX * segmentY - offsetY * segmentX;
        double base = directionX * segmentY - directionY * segmentX;
        double slope = -directionY * segmentY - directionX * segmentX;
        double denominator = base
            + slope * ((start * 2 + 1) / (double) WIDTH - 1);
        double denominatorStep = slope * 2 / WIDTH;
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
            clipTop[x] = 1;
            clipBottom[x] = 0;
          } else {
            int openingCeiling = Math.min(sectorCeiling[near], sectorCeiling[far]);
            int openingFloor = Math.max(sectorFloor[near], sectorFloor[far]);
            int openingTop = (int) Math.floor(
                HEIGHT / 2.0 - (openingCeiling - viewZ) * wallHeight / 128);
            int openingBottom = (int) Math.ceil(
                HEIGHT / 2.0 - (openingFloor - viewZ) * wallHeight / 128) - 1;
            clipTop[x] = Math.max(clipTop[x], openingTop);
            clipBottom[x] = Math.min(clipBottom[x], openingBottom);
            if (!clipOnly) checksum ^= (upper << 1) ^ (lower << 2);
          }
        }
      }
    }
    return checksum;
  }

  @JSExport
  public static int renderGeometryBatch(int start, int count) {
    int checksum = 0;
    for (int index = 0; index < count; index++) {
      checksum += renderGeometry(start + index);
    }
    return checksum;
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
        double screen = WIDTH / 2.0 + (-rx * dy + ry * dx) / depth * WIDTH / 2.0;
        minimumScreen = Math.min(minimumScreen, screen);
        maximumScreen = Math.max(maximumScreen, screen);
      }
    }
    if (maximumDepth <= .01) return false;
    if (minimumDepth <= .01) return true;
    int start = Math.max(0, (int) Math.floor(minimumScreen));
    int end = Math.min(WIDTH - 1, (int) Math.ceil(maximumScreen));
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
