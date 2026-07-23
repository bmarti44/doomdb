/* GPLv3-or-later: links with the pinned Mocha Doom engine. */
package doomdb.mle.engine;

import data.Tables;
import java.nio.ByteBuffer;
import java.nio.ByteOrder;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.Paths;
import java.security.MessageDigest;

/** Emits canonical Oracle-JVM tables and the IWAD-derived TRANMAP for MLE. */
public final class CanonicalTablePackGenerator {
  private static final byte[] MAGIC = {'D', 'M', 'L', 'U', 'T', '0', '0', '2'};
  private static final int VERSION = 2;
  private static final int ENDIAN_MARKER = 0x01020304;
  private static final int HEADER_BYTES = 44;
  private static final int TRANMAP_BYTES = 256 * 256;

  private CanonicalTablePackGenerator() {}

  public static void main(String[] args) throws Exception {
    if (args.length != 2) {
      throw new IllegalArgumentException(
          "usage: CanonicalTablePackGenerator IWAD OUTPUT");
    }

    Tables.InitTables();
    byte[] tranmap = buildTranmap(readLump(Paths.get(args[0]), "PLAYPAL"));
    int payloadBytes = Math.addExact(Math.multiplyExact(
        Tables.finetangent.length
            + Tables.finesine.length
            + Tables.finecosine.length
            + Tables.tantoangle.length,
        Integer.BYTES), tranmap.length);
    ByteBuffer pack = ByteBuffer.allocate(HEADER_BYTES + payloadBytes)
        .order(ByteOrder.BIG_ENDIAN);
    pack.put(MAGIC);
    pack.putInt(VERSION);
    pack.putInt(ENDIAN_MARKER);
    pack.putInt(HEADER_BYTES);
    pack.putInt(pack.capacity());
    pack.putInt(Tables.finetangent.length);
    pack.putInt(Tables.finesine.length);
    pack.putInt(Tables.finecosine.length);
    pack.putInt(Tables.tantoangle.length);
    pack.putInt(tranmap.length);
    put(pack, Tables.finetangent);
    put(pack, Tables.finesine);
    put(pack, Tables.finecosine);
    put(pack, Tables.tantoangle);
    pack.put(tranmap);
    if (pack.hasRemaining()) {
      throw new IllegalStateException("canonical table pack length mismatch");
    }

    Path output = Paths.get(args[1]).toAbsolutePath();
    Files.createDirectories(output.getParent());
    byte[] bytes = pack.array();
    Files.write(output, bytes);
    System.out.println("CANONICAL_TABLE_PACK bytes=" + bytes.length
        + " sha256=" + hex(MessageDigest.getInstance("SHA-256").digest(bytes)));
  }

  private static void put(ByteBuffer output, int[] values) {
    for (int value : values) output.putInt(value);
  }

  private static byte[] readLump(Path wadPath, String wanted) throws Exception {
    byte[] wad = Files.readAllBytes(wadPath);
    ByteBuffer input = ByteBuffer.wrap(wad).order(ByteOrder.LITTLE_ENDIAN);
    if (input.get() != 'I' || input.get() != 'W' || input.get() != 'A'
        || input.get() != 'D') {
      throw new IllegalArgumentException("canonical IWAD header");
    }
    int count = input.getInt();
    int directory = input.getInt();
    if (count < 1 || directory < 12 || directory > wad.length - count * 16) {
      throw new IllegalArgumentException("canonical IWAD directory");
    }
    for (int index = 0; index < count; index++) {
      int entry = directory + index * 16;
      int offset = input.getInt(entry);
      int length = input.getInt(entry + 4);
      StringBuilder name = new StringBuilder(8);
      for (int cursor = 0; cursor < 8; cursor++) {
        int value = wad[entry + 8 + cursor] & 0xff;
        if (value == 0) break;
        name.append((char) value);
      }
      if (wanted.equals(name.toString())) {
        if (length < 768 || offset < 0 || offset > wad.length - length) {
          throw new IllegalArgumentException("canonical PLAYPAL lump");
        }
        byte[] lump = new byte[length];
        System.arraycopy(wad, offset, lump, 0, length);
        return lump;
      }
    }
    throw new IllegalArgumentException("canonical PLAYPAL missing");
  }

  /** Exact copy of RendererState.R_InitTranMap's JVM float selection rules. */
  private static byte[] buildTranmap(byte[] playpal) {
    int[] base = new int[3 * 256];
    for (int color = 0; color < 256; color++) {
      base[3 * color] = playpal[3 * color] & 0xff;
      base[3 * color + 1] = playpal[3 * color + 1] & 0xff;
      base[3 * color + 2] = playpal[3 * color + 2] & 0xff;
    }
    byte[] result = new byte[TRANMAP_BYTES];
    for (int a = 0; a < 256; a++) {
      for (int b = a; b < 256; b++) {
        int red = (base[3 * a] + base[3 * b]) / 2;
        int green = (base[3 * a + 1] + base[3 * b + 1]) / 2;
        int blue = (base[3 * a + 2] + base[3 * b + 2]) / 2;
        float minimum = Float.POSITIVE_INFINITY;
        int minimumIndex = 0;
        for (int candidate = 0; candidate < 256; candidate++) {
          int dr = red - base[3 * candidate];
          int dg = green - base[3 * candidate + 1];
          int db = blue - base[3 * candidate + 2];
          float distance = (float) Math.sqrt(dr * dr + dg * dg + db * db);
          if (distance < minimum) {
            minimum = distance;
            minimumIndex = candidate;
          }
        }
        result[(a << 8) | b] = (byte) minimumIndex;
        result[(b << 8) | a] = (byte) minimumIndex;
      }
    }
    return result;
  }

  private static String hex(byte[] bytes) {
    StringBuilder result = new StringBuilder(bytes.length * 2);
    for (byte value : bytes) {
      result.append(String.format("%02x", value & 0xff));
    }
    return result.toString();
  }
}
