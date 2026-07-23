package doomdb.mle.engine;

import data.Tables;
import java.nio.file.Files;
import java.nio.file.Paths;
import mochadoom.Engine;
import p.BoomLevelLoader;
import rr.vertex_t;
import w.InputStreamSugar;

/** Compares the MLE-only no-host-sqrt path with pinned JVM Math.sqrt. */
public final class DeterministicSqrtPropertyTest {
  private static final int[] BOUNDARIES = {
      Integer.MIN_VALUE, Integer.MIN_VALUE + 1, -0x40000000, -0x10001,
      -0x10000, -1, 0, 1, 0xffff, 0x10000, 0x10001, 0x40000000,
      Integer.MAX_VALUE - 1, Integer.MAX_VALUE
  };

  private static float originalDistance(int dx, int dy) {
    float fx = (float) dx / 65536, fy = (float) dy / 65536;
    return (float) Math.sqrt(fx * fx + fy * fy);
  }

  private static float originalTexel(int dx, int dy) {
    float fx = (float) dx / 65536, fy = (float) dy / 65536;
    return (int) (0.5f + (float) Math.sqrt(fx * fx + fy * fy));
  }

  private static int originalOffset(int dx, int dy) {
    float a = dx / (float) 65536, b = dy / (float) 65536;
    return (int) (Math.sqrt(a * a + b * b) * 65536);
  }

  private static int next(int value) {
    value ^= value << 13;value ^= value >>> 17;value ^= value << 5;return value;
  }

  private static void check(int dx, int dy) {
    float distance = BoomLevelLoader.GetDistance(dx, dy);
    float texel = BoomLevelLoader.GetTexelDistance(dx, dy);
    vertex_t a = new vertex_t(), b = new vertex_t();
    a.x = dx;a.y = dy;
    int offset = BoomLevelLoader.GetOffset(a, b);
    if (Float.floatToRawIntBits(distance) !=
          Float.floatToRawIntBits(originalDistance(dx, dy)) ||
        Float.floatToRawIntBits(texel) !=
          Float.floatToRawIntBits(originalTexel(dx, dy)) ||
        offset != originalOffset(dx, dy)) {
      throw new AssertionError("sqrt mismatch dx=" + dx + " dy=" + dy
          + " distance=" + distance + "/" + originalDistance(dx, dy)
          + " texel=" + texel + "/" + originalTexel(dx, dy)
          + " offset=" + offset + "/" + originalOffset(dx, dy));
    }
  }

  public static void main(String[] args) throws Exception {
    if (args.length != 2) {
      throw new IllegalArgumentException("usage: DeterministicSqrtPropertyTest IWAD PACK");
    }
    InputStreamSugar.setInjectedResource(Files.readAllBytes(Paths.get(args[0])));
    Tables.installCanonicalTablePack(Files.readAllBytes(Paths.get(args[1])));
    Engine.createHeadless("-iwad", "freedoom1.wad", "-nosound", "-nomusic",
        "-indexed", "-width", "320", "-height", "200");
    long checked = 0;
    for (int dx : BOUNDARIES) for (int dy : BOUNDARIES) {
      check(dx, dy);checked++;
    }
    int state = 0x6d2b79f5;
    for (int index = 0; index < 1_000_000; index++) {
      state = next(state);int dx = state;state = next(state);int dy = state;
      check(dx, dy);checked++;
    }
    System.out.println("PASS DETERMINISTIC_SQRT_PROPERTY checked=" + checked);
    Engine.releaseHeadless();InputStreamSugar.clearInjectedResource();
  }
}
