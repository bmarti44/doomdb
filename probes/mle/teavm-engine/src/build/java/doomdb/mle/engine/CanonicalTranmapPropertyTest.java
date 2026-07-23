/* GPLv3-or-later: links with the pinned Mocha Doom engine. */
package doomdb.mle.engine;

import doom.DoomMain;
import java.lang.reflect.Field;
import java.nio.file.Files;
import java.nio.file.Paths;
import java.security.MessageDigest;
import java.util.Arrays;
import mochadoom.Engine;
import rr.RendererState;
import w.InputStreamSugar;

/** Proves the packed TRANMAP equals the unmodified renderer's JVM synthesis. */
public final class CanonicalTranmapPropertyTest {
  private static final int TRANMAP_BYTES = 256 * 256;

  private CanonicalTranmapPropertyTest() {}

  public static void main(String[] args) throws Exception {
    if (args.length != 2) {
      throw new IllegalArgumentException("usage: CanonicalTranmapPropertyTest IWAD PACK");
    }
    byte[] iwad = Files.readAllBytes(Paths.get(args[0]));
    byte[] pack = Files.readAllBytes(Paths.get(args[1]));
    byte[] expected = Arrays.copyOfRange(
        pack, pack.length - TRANMAP_BYTES, pack.length);
    InputStreamSugar.setInjectedResource(iwad);
    DoomMain<?, ?> engine = null;
    try {
      engine = Engine.createHeadless(
          "-iwad", "freedoom1.wad", "-nosound", "-nomusic", "-indexed",
          "-width", "320", "-height", "200");
      Field field = RendererState.class.getDeclaredField("main_tranmap");
      field.setAccessible(true);
      byte[] actual = (byte[]) field.get(engine.sceneRenderer);
      if (!Arrays.equals(expected, actual)) {
        int mismatch = 0;
        while (mismatch < expected.length && expected[mismatch] == actual[mismatch]) {
          mismatch++;
        }
        throw new AssertionError("canonical TRANMAP mismatch at " + mismatch);
      }
      System.out.println("PASS CANONICAL_TRANMAP_PROPERTY bytes=" + actual.length
          + " sha256=" + hex(MessageDigest.getInstance("SHA-256").digest(actual)));
    } finally {
      engine = null;
      Engine.releaseHeadless();
      InputStreamSugar.clearInjectedResource();
    }
  }

  private static String hex(byte[] bytes) {
    StringBuilder result = new StringBuilder(bytes.length * 2);
    for (byte value : bytes) result.append(String.format("%02x", value & 0xff));
    return result.toString();
  }
}
