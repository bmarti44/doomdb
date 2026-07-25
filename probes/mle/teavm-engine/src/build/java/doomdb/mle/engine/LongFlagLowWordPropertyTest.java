package doomdb.mle.engine;

/** Proves low-word flag tests preserve Java long semantics for low masks. */
public final class LongFlagLowWordPropertyTest {
  private static final int[] MASKS = {
      0x1, 0x2, 0x4, 0x8, 0x10, 0x20, 0x40, 0x80,
      0x100, 0x200, 0x400, 0x800, 0x1000, 0x2000, 0x4000, 0x8000,
      0x10000, 0x20000, 0x40000, 0x80000, 0x100000, 0x200000,
      0x400000, 0x800000, 0x1000000, 0x2000000, 0xc000000
  };
  private static final long[] BOUNDARIES = {
      Long.MIN_VALUE, Long.MIN_VALUE + 1, -1L, 0L, 1L,
      0x7fffffffL, 0x80000000L, 0xffffffffL,
      1L << 32, 1L << 38, (1L << 38) | 0x01000000L, Long.MAX_VALUE
  };

  private LongFlagLowWordPropertyTest() {}

  private static void check(long flags) {
    int low = (int) flags;
    for (int mask : MASKS) {
      boolean expected = (flags & (long) mask) != 0;
      boolean actual = (low & mask) != 0;
      if (actual != expected) {
        throw new AssertionError(
            "low-word mismatch flags=" + flags + " mask=" + mask);
      }
    }
  }

  public static void main(String[] args) {
    long checksum = 0x13579bdf2468ace0L;
    for (long value : BOUNDARIES) {
      check(value);
      checksum = checksum * 33 + value;
    }
    long state = 0x6a09e667f3bcc909L;
    for (int i = 0; i < 1_000_000; i++) {
      state ^= state << 13;
      state ^= state >>> 7;
      state ^= state << 17;
      check(state);
      checksum = checksum * 33 + state;
    }
    System.out.println(
        "PASS LONG_FLAG_LOW_WORD_PROPERTY samples=1000012 checksum=" + checksum);
  }
}
