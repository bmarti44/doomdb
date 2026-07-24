/* GPLv3-or-later: links with the pinned Mocha Doom engine. */
package doomdb.mle.engine;

import m.fixed_t;

/** Boundary and randomized differential for the MLE-only FixedDiv intrinsic. */
public final class FixedDivPropertyTest {
  private static final int RANDOM_PAIRS = 2_000_000;
  private static final int[] BOUNDARIES = {
      Integer.MIN_VALUE, Integer.MIN_VALUE + 1,
      -0x40000001, -0x40000000, -0x10001, -0x10000, -0xffff,
      -0x8001, -0x8000, -0x4001, -0x4000, -2, -1, 0, 1, 2,
      0x3fff, 0x4000, 0x7fff, 0x8000, 0xffff, 0x10000, 0x10001,
      0x3fffffff, 0x40000000, Integer.MAX_VALUE - 1, Integer.MAX_VALUE
  };

  private FixedDivPropertyTest() {}

  public static void main(String[] args) {
    int checksum = 0x2468ace1;
    long checked = 0;
    for (int a : BOUNDARIES) {
      for (int b : BOUNDARIES) {
        checksum = verifyAndMix(checksum, a, b);
        checked++;
      }
    }

    // Exhaust every small divisor at the saturation boundary and immediately
    // on both sides. This is the branch where Math.abs(MIN_VALUE), sign, and
    // quotient truncation mistakes tend to hide.
    for (int b = -65536; b <= 65536; b++) {
      long magnitude = Math.abs((long) b) << 14;
      for (int delta = -3; delta <= 3; delta++) {
        long positive = magnitude + delta;
        long negative = -magnitude + delta;
        if (positive >= Integer.MIN_VALUE && positive <= Integer.MAX_VALUE) {
          checksum = verifyAndMix(checksum, (int) positive, b);
          checked++;
        }
        if (negative >= Integer.MIN_VALUE && negative <= Integer.MAX_VALUE) {
          checksum = verifyAndMix(checksum, (int) negative, b);
          checked++;
        }
      }
    }

    int state = 0x51ed270b;
    for (int i = 0; i < RANDOM_PAIRS; i++) {
      state = next(state);
      int a = state;
      state = next(state);
      int b = state;
      checksum = verifyAndMix(checksum, a, b);
      checked++;
    }
    System.out.println("PASS FIXED_DIV_PROPERTY checked=" + checked
        + " checksum=" + checksum);
  }

  private static int verifyAndMix(int checksum, int a, int b) {
    if (a == Integer.MIN_VALUE && b == 0) {
      try {
        fixed_t.FixedDiv(a, b);
        throw new AssertionError("FixedDiv MIN_VALUE/0 did not throw");
      } catch (ArithmeticException expected) {
        return mix(checksum, a, b, 0x4d494e30);
      }
    }
    int expected = reference(a, b);
    int actual = fixed_t.FixedDiv(a, b);
    if (expected != actual) {
      throw new AssertionError("FixedDiv a=" + a + " b=" + b
          + " expected=" + expected + " actual=" + actual);
    }
    return mix(checksum, a, b, actual);
  }

  private static int reference(int a, int b) {
    if ((Math.abs(a) >> 14) >= Math.abs(b)) {
      return (a ^ b) < 0 ? Integer.MIN_VALUE : Integer.MAX_VALUE;
    }
    return (int) (((long) a << fixed_t.FRACBITS) / (long) b);
  }

  private static int next(int value) {
    value ^= value << 13;
    value ^= value >>> 17;
    value ^= value << 5;
    return value;
  }

  private static int mix(int checksum, int a, int b, int result) {
    checksum = checksum * 16777619 ^ a;
    checksum = checksum * 16777619 ^ b;
    return checksum * 16777619 ^ result;
  }
}
