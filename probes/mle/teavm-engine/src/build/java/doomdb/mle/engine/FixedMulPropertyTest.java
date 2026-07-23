/* GPLv3-or-later: links with the pinned Mocha Doom engine. */
package doomdb.mle.engine;

import m.fixed_t;

/** Differential property test for the MLE-only int-limb FixedMul. */
public final class FixedMulPropertyTest {
  private static final int RANDOM_PAIRS = 1_000_000;
  private static final int[] BOUNDARIES = {
      Integer.MIN_VALUE, Integer.MIN_VALUE + 1,
      -0x40000001, -0x40000000, -0x10001, -0x10000, -0xffff,
      -0x8001, -0x8000, -2, -1, 0, 1, 2,
      0x7fff, 0x8000, 0xffff, 0x10000, 0x10001,
      0x3fffffff, 0x40000000, Integer.MAX_VALUE - 1, Integer.MAX_VALUE
  };

  private FixedMulPropertyTest() {}

  public static void main(String[] args) {
    fixed_t left = new fixed_t();
    fixed_t right = new fixed_t();
    fixed_t destination = new fixed_t();
    int checksum = 0x13579bdf;
    long checked = 0;
    for (int a : BOUNDARIES) {
      for (int b : BOUNDARIES) {
        verify(a, b, left, right, destination);
        checksum = mix(checksum, a, b, fixed_t.FixedMul(a, b));
        checked++;
      }
    }

    int state = 0x6d2b79f5;
    for (int i = 0; i < RANDOM_PAIRS; i++) {
      state = next(state);
      int a = state;
      state = next(state);
      int b = state;
      verify(a, b, left, right, destination);
      checksum = mix(checksum, a, b, fixed_t.FixedMul(a, b));
      checked++;
    }
    System.out.println("PASS FIXED_MUL_PROPERTY checked=" + checked
        + " checksum=" + checksum);
  }

  private static void verify(
      int a, int b, fixed_t left, fixed_t right, fixed_t destination) {
    int unsignedReference = (int) (((long) a * (long) b) >>> fixed_t.FRACBITS);
    int signedReference = (int) (((long) a * (long) b) >> fixed_t.FRACBITS);
    if (unsignedReference != signedReference) {
      throw new AssertionError("shift references diverged");
    }
    left.set(a);
    right.set(b);
    assertEqual("int/int", a, b, unsignedReference, fixed_t.FixedMul(a, b));
    assertEqual("fixed/fixed", a, b, unsignedReference, fixed_t.FixedMul(left, right));
    assertEqual("int/fixed", a, b, unsignedReference, fixed_t.FixedMul(a, right));
    assertEqual("FixedMulInt", a, b, signedReference, fixed_t.FixedMulInt(left, right));
    fixed_t.FixedMul(left, right, destination);
    assertEqual("destination", a, b, signedReference, destination.get());
    destination.set(a);
    destination.FixedMul(right);
    assertEqual("in-place", a, b, signedReference, destination.get());
  }

  private static void assertEqual(
      String operation, int a, int b, int expected, int actual) {
    if (expected != actual) {
      throw new AssertionError(operation + " a=" + a + " b=" + b
          + " expected=" + expected + " actual=" + actual);
    }
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
