package doomdb.mle.raster;

import org.teavm.jso.JSByRef;
import org.teavm.jso.JSExport;
import org.teavm.jso.typedarrays.Uint8Array;

/**
 * Compact renderer for the authentic low-level commands emitted by Mocha.
 *
 * The diagnostic pack preserves invocation order and contains already-lit
 * texture columns/flats.  This kernel deliberately excludes geometry and game
 * simulation: the shipping authority resolves those, while this small
 * compiled shape performs only the final indexed-pixel raster work.
 */
public final class FullCommandRasterKernel {
  private static final int WIDTH = 320;
  private static final int VIEW_HEIGHT = 168;
  private static final int FRAME_HEIGHT = 200;
  private static final int FRAME_PIXELS = WIDTH * FRAME_HEIGHT;
  private static final int VIEW_PIXELS = WIDTH * VIEW_HEIGHT;
  private static final int PACK_MAGIC = 0x31504346; // FCP1
  private static final int PACK_VERSION = 3;
  private static final int ASSET_MAGIC = 0x31414346; // FCA1
  private static final int COMMAND_BYTES = 28;
  private static final int DIGEST_BYTES = 32;

  private static byte[] pack;
  private static int[] commandOffsets;
  private static int[] commandLengths;
  private static int[] commandStarts;
  private static int[] viewportDigestOffsets;
  private static int[] frameTics;
  private static int[] framePlayers;
  private static int[] assetOffsets;
  private static int[] assetLengths;
  private static byte[] commandKinds;
  private static int[] commandA;
  private static int[] commandB;
  private static int[] commandC;
  private static int[] commandD;
  private static int[] commandE;
  private static int[] commandF;
  private static int[] commandG;
  private static int[] commandH;
  private static byte[] frame;
  private static byte[] rowMajorViewport;

  private FullCommandRasterKernel() {}

  @JSExport
  public static int allocateFullCommandPack(int length) {
    if (length < 16 || length > 64_000_000) {
      throw new IllegalArgumentException("invalid full-command pack length");
    }
    pack = new byte[length];
    commandOffsets = null;
    return length;
  }

  @JSExport
  public static int loadFullCommandPackChunk(int offset, Uint8Array chunk) {
    if (pack == null || offset < 0 || offset + chunk.getLength() > pack.length) {
      throw new IllegalArgumentException("full-command chunk outside allocation");
    }
    for (int index = 0; index < chunk.getLength(); index++) {
      pack[offset + index] = (byte) chunk.get(index);
    }
    return offset + chunk.getLength();
  }

  @JSExport
  public static int finalizeFullCommandPack() {
    if (pack == null || u32(pack, 0) != PACK_MAGIC
        || u32(pack, 4) != PACK_VERSION) {
      throw new IllegalStateException("full-command pack header mismatch");
    }
    int frameCount = u32(pack, 8);
    int assetBytes = u32(pack, 12);
    if (frameCount < 1 || frameCount > 10_500
        || assetBytes < 12 || assetBytes >= pack.length) {
      throw new IllegalStateException("full-command pack dimensions invalid");
    }

    commandOffsets = new int[frameCount];
    commandLengths = new int[frameCount];
    commandStarts = new int[frameCount];
    viewportDigestOffsets = new int[frameCount];
    frameTics = new int[frameCount];
    framePlayers = new int[frameCount];
    int at = 16;
    int totalCommands = 0;
    for (int index = 0; index < frameCount; index++) {
      require(at, 16);
      int tic = u32(pack, at);
      int player = u32(pack, at + 4);
      int commandLength = u32(pack, at + 8);
      int frameLength = u32(pack, at + 12);
      at += 16;
      if (tic < 1 || player < 0 || player > 3
          || commandLength < COMMAND_BYTES
          || commandLength % COMMAND_BYTES != 0
          || frameLength != FRAME_PIXELS) {
        throw new IllegalStateException("full-command frame header invalid");
      }
      require(at, commandLength + DIGEST_BYTES * 2);
      frameTics[index] = tic;
      framePlayers[index] = player;
      commandOffsets[index] = at;
      commandLengths[index] = commandLength;
      commandStarts[index] = totalCommands;
      totalCommands += commandLength / COMMAND_BYTES;
      at += commandLength;
      at += DIGEST_BYTES; // canonical full-frame SHA-256
      viewportDigestOffsets[index] = at;
      at += DIGEST_BYTES;
    }

    if (at + assetBytes != pack.length || u32(pack, at) != ASSET_MAGIC) {
      throw new IllegalStateException("full-command asset pack boundary mismatch");
    }
    int assetCount = u32(pack, at + 4);
    int assetDataBytes = u32(pack, at + 8);
    if (assetCount < 1 || assetCount > 65_534
        || 12 + assetCount * 8 + assetDataBytes != assetBytes) {
      throw new IllegalStateException("full-command asset directory invalid");
    }
    assetOffsets = new int[assetCount];
    assetLengths = new int[assetCount];
    for (int index = 0; index < assetCount; index++) {
      int offset = u32(pack, at + 12 + index * 8);
      int length = u32(pack, at + 16 + index * 8);
      if (offset < 12 + assetCount * 8 || length < 1
          || offset + length > assetBytes) {
        throw new IllegalStateException("full-command asset entry invalid");
      }
      assetOffsets[index] = at + offset;
      assetLengths[index] = length;
    }
    commandKinds = new byte[totalCommands];
    commandA = new int[totalCommands];
    commandB = new int[totalCommands];
    commandC = new int[totalCommands];
    commandD = new int[totalCommands];
    commandE = new int[totalCommands];
    commandF = new int[totalCommands];
    commandG = new int[totalCommands];
    commandH = new int[totalCommands];
    int command = 0;
    for (int frameIndex = 0; frameIndex < frameCount; frameIndex++) {
      int commandAt = commandOffsets[frameIndex];
      int commandEnd = commandAt + commandLengths[frameIndex];
      while (commandAt < commandEnd) {
        resolveCommand(command++, commandAt);
        commandAt += COMMAND_BYTES;
      }
    }
    if (command != totalCommands) {
      throw new IllegalStateException("full-command resolution mismatch");
    }
    frame = new byte[FRAME_PIXELS];
    rowMajorViewport = new byte[VIEW_PIXELS];
    return frameCount;
  }

  @JSExport
  public static int renderFullCommandFrame(int frameIndex) {
    if (commandOffsets == null || frame == null) {
      throw new IllegalStateException("full-command raster is not initialized");
    }
    frameIndex = normalizedFrame(frameIndex);
    int command = commandStarts[frameIndex];
    int end = command + commandLengths[frameIndex] / COMMAND_BYTES;
    while (command < end) {
      int kind = commandKinds[command] & 255;
      if (kind == 6) {
        drawSpan(command);
      } else if (kind == 4) {
        throw new IllegalStateException(
            "fuzz command requires the separately gated fuzz path");
      } else if (kind <= 5) {
        drawColumn(command);
      } else {
        throw new IllegalStateException("unknown full-command raster kind");
      }
      command++;
    }
    return (frame[frameIndex % FRAME_PIXELS] & 255)
        | ((frame[(frameIndex * 997) % FRAME_PIXELS] & 255) << 8);
  }

  @JSExport
  public static int renderFullCommandBatch(int start, int count) {
    if (count < 1 || commandOffsets == null || count > commandOffsets.length) {
      throw new IllegalArgumentException("invalid full-command batch length");
    }
    int checksum = 0;
    for (int index = 0; index < count; index++) {
      checksum += renderFullCommandFrame(start + index);
    }
    return checksum;
  }

  @JSExport
  public static int fullCommandFrameCount() {
    return commandOffsets == null ? 0 : commandOffsets.length;
  }

  @JSExport
  public static int fullCommandCount(int frameIndex) {
    frameIndex = normalizedFrame(frameIndex);
    return commandLengths[frameIndex] / COMMAND_BYTES;
  }

  @JSExport
  public static int fullCommandFrameTic(int frameIndex) {
    return frameTics[normalizedFrame(frameIndex)];
  }

  @JSExport
  public static int fullCommandFramePlayer(int frameIndex) {
    return framePlayers[normalizedFrame(frameIndex)];
  }

  @JSExport
  public static int prepareFullCommandViewport() {
    if (frame == null) {
      throw new IllegalStateException("full-command framebuffer unavailable");
    }
    int output = 0;
    for (int y = 0; y < VIEW_HEIGHT; y++) {
      for (int x = 0; x < WIDTH; x++) {
        rowMajorViewport[output++] = frame[x * FRAME_HEIGHT + y];
      }
    }
    return output;
  }

  @JSExport
  @JSByRef
  public static byte[] fullCommandViewportChunk(int offset, int length) {
    if (rowMajorViewport == null || offset < 0 || length < 0 || length > 32767
        || offset + length > rowMajorViewport.length) {
      throw new IllegalArgumentException("viewport chunk outside framebuffer");
    }
    byte[] chunk = new byte[length];
    System.arraycopy(rowMajorViewport, offset, chunk, 0, length);
    return chunk;
  }

  @JSExport
  @JSByRef
  public static byte[] fullCommandViewportDigest(int frameIndex) {
    frameIndex = normalizedFrame(frameIndex);
    byte[] digest = new byte[DIGEST_BYTES];
    System.arraycopy(pack, viewportDigestOffsets[frameIndex],
        digest, 0, DIGEST_BYTES);
    return digest;
  }

  private static void drawColumn(int command) {
    int x = commandA[command];
    int yl = commandB[command];
    int yh = commandC[command];
    int fracStep = commandD[command];
    int frac = commandE[command];
    int textureHeight = commandF[command];
    int sourceOffset = commandG[command];
    int source = commandH[command];
    int output = x * FRAME_HEIGHT + yl;
    int count = yh - yl + 1;
    int heightMask = textureHeight - 1;
    if ((textureHeight & heightMask) != 0) {
      int wrap = textureHeight << 16;
      if (wrap <= 0) {
        throw new IllegalStateException("invalid non-power-of-two texture");
      }
      if (frac < 0) {
        while ((frac += wrap) < 0) {
          // Match the source renderer's fixed-point normalization exactly.
        }
      } else {
        while (frac >= wrap) frac -= wrap;
      }
      while (count-- > 0) {
        int sample = frac >> 16;
        frame[output++] = pack[source + sample];
        frac += fracStep;
        if (frac >= wrap) frac -= wrap;
      }
    } else {
      while (count-- > 0) {
        int sample = sourceOffset + ((frac >> 16) & heightMask);
        frame[output++] = pack[source + sample];
        frac += fracStep;
      }
    }
  }

  private static void drawSpan(int command) {
    int x1 = commandA[command];
    int x2 = commandB[command];
    int y = commandC[command];
    int xfrac = commandD[command];
    int yfrac = commandE[command];
    int xstep = commandF[command];
    int ystep = commandG[command];
    int source = commandH[command];
    int output = x1 * FRAME_HEIGHT + y;
    for (int x = x1; x <= x2; x++) {
      int spot = ((yfrac >> 10) & 4032) + ((xfrac >> 16) & 63);
      frame[output] = pack[source + spot];
      output += FRAME_HEIGHT;
      xfrac += xstep;
      yfrac += ystep;
    }
  }

  private static void resolveCommand(int command, int at) {
    int kind = pack[at] & 255;
    commandKinds[command] = (byte) kind;
    if (kind == 6) {
      int x1 = u16(pack, at + 2);
      int x2 = u16(pack, at + 4);
      int y = u16(pack, at + 6);
      int asset = u16(pack, at + 24);
      if (x1 > x2 || x2 >= WIDTH || y >= VIEW_HEIGHT
          || asset >= assetOffsets.length || assetLengths[asset] < 4096) {
        throw new IllegalStateException("full-command span outside bounds");
      }
      commandA[command] = x1;
      commandB[command] = x2;
      commandC[command] = y;
      commandD[command] = i32(pack, at + 8);
      commandE[command] = i32(pack, at + 12);
      commandF[command] = i32(pack, at + 16);
      commandG[command] = i32(pack, at + 20);
      commandH[command] = assetOffsets[asset];
      return;
    }
    if (kind == 4) return;
    if (kind > 5) {
      throw new IllegalStateException("unknown full-command raster kind");
    }
    int x = u16(pack, at + 2);
    int yl = u16(pack, at + 4);
    int yh = u16(pack, at + 6);
    int fracStep = i32(pack, at + 8);
    int asset = u16(pack, at + 26);
    if (x >= WIDTH || yl > yh || yh >= VIEW_HEIGHT
        || asset >= assetOffsets.length) {
      throw new IllegalStateException("full-command column outside bounds");
    }
    commandA[command] = x;
    commandB[command] = yl;
    commandC[command] = yh;
    commandD[command] = fracStep;
    commandE[command] = i32(pack, at + 12)
        + (yl - u16(pack, at + 24)) * fracStep;
    commandF[command] = i32(pack, at + 16);
    commandG[command] = i32(pack, at + 20);
    commandH[command] = assetOffsets[asset];
  }

  private static int normalizedFrame(int frameIndex) {
    if (commandOffsets == null || commandOffsets.length == 0) {
      throw new IllegalStateException("full-command frames unavailable");
    }
    frameIndex %= commandOffsets.length;
    if (frameIndex < 0) frameIndex += commandOffsets.length;
    return frameIndex;
  }

  private static void require(int offset, int length) {
    if (offset < 0 || length < 0 || offset + length > pack.length) {
      throw new IllegalStateException("truncated full-command pack");
    }
  }

  private static int u16(byte[] source, int offset) {
    return (source[offset] & 255) | ((source[offset + 1] & 255) << 8);
  }

  private static int u32(byte[] source, int offset) {
    return (source[offset] & 255) | ((source[offset + 1] & 255) << 8)
        | ((source[offset + 2] & 255) << 16) | (source[offset + 3] << 24);
  }

  private static int i32(byte[] source, int offset) {
    return u32(source, offset);
  }

  static void keepReachable() {
    // TeaVM discovers the public JS exports through this reachable class.
  }
}
