package doomdb.mle.raster;

import org.teavm.jso.JSByRef;
import org.teavm.jso.JSExport;
import org.teavm.jso.typedarrays.Uint8Array;

/**
 * Small generated raster discriminator.
 *
 * Geometry is deliberately absent.  The retained module consumes resolved
 * wall spans captured from the real E1M1 route and samples the authentic
 * prelit atlas.  Keeping this method and module small tests whether generated
 * shape, rather than pixel work, prevented the integrated renderer from
 * entering the compiled MLE tier.
 */
public final class FreeRasterKernel {
  private static final int WIDTH = 320;
  private static final int HEIGHT = 200;
  private static final int PIXELS = WIDTH * HEIGHT;
  private static final int COMMAND_MAGIC = 0x31504352;
  private static final int COMMAND_VERSION = 1;
  private static final int COMMAND_BYTES = 20;
  private static final int COLUMN_HASH_SIZE = 1 << 20;

  private static byte[] atlas;
  private static byte[] commands;
  private static int[] frameOffsets;
  private static int[] frameCounts;
  private static byte[] backgroundFrame;
  private static byte[] frame;

  private FreeRasterKernel() {}

  @JSExport
  public static int allocateAtlas(int length) {
    if (length < 1 || length > 64_000_000) {
      throw new IllegalArgumentException("invalid raster atlas length");
    }
    atlas = new byte[length];
    return length;
  }

  @JSExport
  public static int loadAtlasChunk(int offset, Uint8Array chunk) {
    if (atlas == null || offset < 0 || offset + chunk.getLength() > atlas.length) {
      throw new IllegalArgumentException("atlas chunk outside allocation");
    }
    for (int index = 0; index < chunk.getLength(); index++) {
      atlas[offset + index] = (byte) chunk.get(index);
    }
    return offset + chunk.getLength();
  }

  @JSExport
  public static int allocateCommands(int length) {
    if (length < 20 || length > 32_000_000) {
      throw new IllegalArgumentException("invalid command pack length");
    }
    commands = new byte[length];
    return length;
  }

  @JSExport
  public static int loadCommandChunk(int offset, Uint8Array chunk) {
    if (commands == null || offset < 0
        || offset + chunk.getLength() > commands.length) {
      throw new IllegalArgumentException("command chunk outside allocation");
    }
    for (int index = 0; index < chunk.getLength(); index++) {
      commands[offset + index] = (byte) chunk.get(index);
    }
    return offset + chunk.getLength();
  }

  @JSExport
  public static int finalizeCommands() {
    if (u32(commands, 0) != COMMAND_MAGIC
        || u32(commands, 4) != COMMAND_VERSION
        || u32(commands, 12) != COMMAND_BYTES) {
      throw new IllegalStateException("resolved command pack header mismatch");
    }
    int count = u32(commands, 8);
    if (count < 1 || count > 5250) {
      throw new IllegalStateException("resolved command frame count mismatch");
    }
    frameOffsets = new int[count];
    frameCounts = new int[count];
    int at = 16;
    for (int index = 0; index < count; index++) {
      if (at + 4 > commands.length) {
        throw new IllegalStateException("truncated resolved command frame");
      }
      int commandCount = u32(commands, at);
      at += 4;
      if (commandCount < 0
          || commandCount > (commands.length - at) / COMMAND_BYTES) {
        throw new IllegalStateException("invalid resolved command count");
      }
      frameOffsets[index] = at;
      frameCounts[index] = commandCount;
      at += commandCount * COMMAND_BYTES;
    }
    if (at != commands.length) {
      throw new IllegalStateException("resolved command pack trailing bytes");
    }
    transposeReferencedColumns();
    backgroundFrame = new byte[PIXELS];
    frame = new byte[PIXELS];
    for (int x = 0; x < WIDTH; x++) {
      int output = x * HEIGHT;
      for (int y = 0; y < HEIGHT; y++) {
        backgroundFrame[output + y] = (byte) (y < HEIGHT / 2 ? 96 : 48);
      }
    }
    return count;
  }

  @JSExport
  public static int renderFrame(int index) {
    if (frameOffsets == null || atlas == null) {
      throw new IllegalStateException("raster kernel is not initialized");
    }
    index %= frameOffsets.length;
    if (index < 0) index += frameOffsets.length;

    System.arraycopy(backgroundFrame, 0, frame, 0, PIXELS);

    int at = frameOffsets[index];
    int end = at + frameCounts[index] * COMMAND_BYTES;
    while (at < end) {
      int output = u32(commands, at);
      int sourceBase = u32(commands, at + 4);
      int width = u16(commands, at + 8);
      int height = u16(commands, at + 10);
      int wallHeight = u16(commands, at + 12);
      int length = u16(commands, at + 14);
      int numerator = i32(commands, at + 16);
      boolean powerOfTwo = (height & (height - 1)) == 0;
      for (int pixel = 0; pixel < length; pixel++) {
        int sourceY = numerator / wallHeight;
        sourceY = powerOfTwo ? sourceY & (height - 1) : sourceY % height;
        if (sourceY < 0) sourceY += height;
        frame[output + pixel] = atlas[sourceBase + sourceY];
        numerator += 128;
      }
      at += COMMAND_BYTES;
    }
    return (frame[index % PIXELS] & 255)
        | ((frame[(index * 997) % PIXELS] & 255) << 8);
  }

  @JSExport
  public static int renderBatch(int start, int count) {
    if (count < 1 || count > 5250) {
      throw new IllegalArgumentException("invalid raster batch length");
    }
    int checksum = 0;
    for (int index = 0; index < count; index++) {
      checksum += renderFrame(start + index);
    }
    return checksum;
  }

  @JSExport
  public static int commandCount(int index) {
    if (frameCounts == null) {
      throw new IllegalStateException("raster kernel is not initialized");
    }
    return frameCounts[index % frameCounts.length];
  }

  @JSExport
  @JSByRef
  public static byte[] frameChunk(int offset, int length) {
    if (frame == null || offset < 0 || length < 0 || length > 32767
        || offset + length > frame.length) {
      throw new IllegalArgumentException("frame chunk outside framebuffer");
    }
    byte[] chunk = new byte[length];
    System.arraycopy(frame, offset, chunk, 0, length);
    return chunk;
  }

  @JSExport
  public static int fullPackAllocate(int length) {
    return FullCommandRasterKernel.allocateFullCommandPack(length);
  }

  @JSExport
  public static int fullPackLoad(int offset, Uint8Array chunk) {
    return FullCommandRasterKernel.loadFullCommandPackChunk(offset, chunk);
  }

  @JSExport
  public static int fullPackFinalize() {
    return FullCommandRasterKernel.finalizeFullCommandPack();
  }

  @JSExport
  public static int fullFrameRender(int index) {
    return FullCommandRasterKernel.renderFullCommandFrame(index);
  }

  @JSExport
  public static int fullFrameBatch(int start, int count) {
    return FullCommandRasterKernel.renderFullCommandBatch(start, count);
  }

  @JSExport
  public static int fullFrameCount() {
    return FullCommandRasterKernel.fullCommandFrameCount();
  }

  @JSExport
  public static int fullFramePrepareViewport() {
    return FullCommandRasterKernel.prepareFullCommandViewport();
  }

  @JSExport
  public static int fullFramePrepare() {
    return FullCommandRasterKernel.prepareFullCommandFrame();
  }

  @JSExport
  @JSByRef
  public static byte[] fullFrameViewportChunk(int offset, int length) {
    return FullCommandRasterKernel.fullCommandViewportChunk(offset, length);
  }

  @JSExport
  @JSByRef
  public static byte[] fullFrameViewportDigest(int index) {
    return FullCommandRasterKernel.fullCommandViewportDigest(index);
  }

  @JSExport
  @JSByRef
  public static byte[] fullFrameChunk(int offset, int length) {
    return FullCommandRasterKernel.fullCommandFrameChunk(offset, length);
  }

  @JSExport
  @JSByRef
  public static byte[] fullFrameDigest(int index) {
    return FullCommandRasterKernel.fullCommandFrameDigest(index);
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

  /**
   * The installed atlas is row-major because that is Mocha's canonical
   * texture representation.  Doom draws walls vertically, so the live raster
   * pays a stride and multiply for every pixel in that layout.  Resolve every
   * referenced lit texture column once during retained-context initialization
   * and rewrite command bases to a compact column-major atlas.  A production
   * asset pack can be emitted directly in this shape; doing it here keeps the
   * discriminator byte-comparable with the existing reference pack.
   */
  private static void transposeReferencedColumns() {
    int[] keyBase = new int[COLUMN_HASH_SIZE];
    int[] keyShape = new int[COLUMN_HASH_SIZE];
    int[] value = new int[COLUMN_HASH_SIZE];
    byte[] occupied = new byte[COLUMN_HASH_SIZE];
    byte[] columnAtlas = new byte[atlas.length];
    int next = 0;
    int mask = COLUMN_HASH_SIZE - 1;

    for (int frameIndex = 0; frameIndex < frameOffsets.length; frameIndex++) {
      int at = frameOffsets[frameIndex];
      int end = at + frameCounts[frameIndex] * COMMAND_BYTES;
      while (at < end) {
        int sourceBase = u32(commands, at + 4);
        int width = u16(commands, at + 8);
        int height = u16(commands, at + 10);
        int shape = (width << 16) | height;
        int slot = (sourceBase * 0x9e3779b9 ^ shape * 0x85ebca6b) & mask;
        while (occupied[slot] != 0
            && (keyBase[slot] != sourceBase || keyShape[slot] != shape)) {
          slot = (slot + 1) & mask;
        }
        int columnBase;
        if (occupied[slot] == 0) {
          if (height < 1 || next + height > columnAtlas.length) {
            throw new IllegalStateException("column-major atlas overflow");
          }
          occupied[slot] = 1;
          keyBase[slot] = sourceBase;
          keyShape[slot] = shape;
          columnBase = next;
          value[slot] = columnBase;
          for (int y = 0; y < height; y++) {
            columnAtlas[next++] = atlas[sourceBase + y * width];
          }
        } else {
          columnBase = value[slot];
        }
        putI32(commands, at + 4, columnBase);
        at += COMMAND_BYTES;
      }
    }
    atlas = columnAtlas;
  }

  private static void putI32(byte[] target, int offset, int value) {
    target[offset] = (byte) value;
    target[offset + 1] = (byte) (value >>> 8);
    target[offset + 2] = (byte) (value >>> 16);
    target[offset + 3] = (byte) (value >>> 24);
  }

  public static void main(String[] args) {
    FullCommandRasterKernel.keepReachable();
  }
}
