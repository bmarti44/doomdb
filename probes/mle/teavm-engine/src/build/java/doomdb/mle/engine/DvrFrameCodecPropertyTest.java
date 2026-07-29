package doomdb.mle.engine;

import java.util.Arrays;
import java.util.Random;

/** Exhaustive-shape and mutation checks for the pinned DFR1 codec. */
public final class DvrFrameCodecPropertyTest {
  private DvrFrameCodecPropertyTest() {}

  public static void main(String[] args) {
    byte[][] frames = {
      new byte[DvrFrameCodec.FRAME_BYTES],
      alternating(),
      sequential(),
      random(0x44465231L),
      runBoundaries()
    };
    long checksum = 0;
    for (byte[] frame : frames) {
      byte[] first = DvrFrameCodec.compress(frame);
      byte[] second = DvrFrameCodec.compress(frame);
      require(Arrays.equals(first, second), "compression is not deterministic");
      require(Arrays.equals(frame, DvrFrameCodec.decompress(first)),
          "round trip mismatch");
      checksum = checksum * 0x100000001b3L + Arrays.hashCode(first);
      for (int index : new int[] {0, 3, 4, 8}) {
        byte[] changed = first.clone();
        changed[index] ^= 1;
        boolean rejected = false;
        try {
          DvrFrameCodec.decompress(changed);
        } catch (IllegalArgumentException expected) {
          rejected = true;
        }
        require(rejected, "mutated stream was accepted at " + index);
      }
      byte[] payloadMutation = first.clone();
      payloadMutation[payloadMutation.length - 1] ^= 1;
      try {
        require(!Arrays.equals(frame, DvrFrameCodec.decompress(payloadMutation)),
            "payload mutation preserved the canonical frame");
      } catch (IllegalArgumentException expected) {
        // A token-boundary mutation may also become structurally invalid.
      }
    }
    require(DvrFrameCodec.compress(new byte[DvrFrameCodec.FRAME_BYTES]).length
        < DvrFrameCodec.FRAME_BYTES / 50, "constant frame ratio regressed");
    System.out.println("PASS DFR1-CODEC-PROPERTY frames=" + frames.length
        + " checksum=" + Long.toUnsignedString(checksum));
  }

  private static byte[] alternating() {
    byte[] frame = new byte[DvrFrameCodec.FRAME_BYTES];
    for (int i = 0; i < frame.length; i++) frame[i] = (byte) (i & 1);
    return frame;
  }

  private static byte[] sequential() {
    byte[] frame = new byte[DvrFrameCodec.FRAME_BYTES];
    for (int i = 0; i < frame.length; i++) frame[i] = (byte) i;
    return frame;
  }

  private static byte[] random(long seed) {
    byte[] frame = new byte[DvrFrameCodec.FRAME_BYTES];
    new Random(seed).nextBytes(frame);
    return frame;
  }

  private static byte[] runBoundaries() {
    byte[] frame = new byte[DvrFrameCodec.FRAME_BYTES];
    int output = 0;
    for (int length : new int[] {1, 2, 3, 127, 128, 129, 130, 131}) {
      Arrays.fill(frame, output, output + length, (byte) length);
      output += length;
    }
    for (int i = output; i < frame.length; i++) frame[i] = (byte) i;
    return frame;
  }

  private static void require(boolean condition, String message) {
    if (!condition) throw new AssertionError(message);
  }
}
