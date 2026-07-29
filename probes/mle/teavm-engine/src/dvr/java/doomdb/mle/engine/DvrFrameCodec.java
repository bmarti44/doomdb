/* GPLv3-or-later: links with the pinned Mocha Doom engine. */
package doomdb.mle.engine;

import java.util.Arrays;

/** Deterministic frame-local byte RLE for exact indexed DVR frames. */
public final class DvrFrameCodec {
  public static final String CODEC_ID = "DOOM_DFR1_RLE";
  public static final int CODEC_VERSION = 1;
  public static final int FRAME_BYTES = 320 * 200;
  public static final int HEADER_BYTES = 12;
  private static final int MAX_LITERAL = 128;
  private static final int MAX_REPEAT = 130;

  private DvrFrameCodec() {}

  public static byte[] compress(byte[] frame) {
    if (frame == null || frame.length != FRAME_BYTES) {
      throw new IllegalArgumentException("DFR1 requires a 64000-byte frame");
    }
    byte[] encoded = new byte[
        HEADER_BYTES + frame.length + (frame.length + MAX_LITERAL - 1) / MAX_LITERAL];
    encoded[0] = 'D';
    encoded[1] = 'F';
    encoded[2] = 'R';
    encoded[3] = '1';
    putU32(encoded, 4, frame.length);
    int input = 0;
    int output = HEADER_BYTES;
    while (input < frame.length) {
      int repeated = repeatLength(frame, input);
      if (repeated >= 3) {
        encoded[output++] = (byte) (0x80 | (repeated - 3));
        encoded[output++] = frame[input];
        input += repeated;
        continue;
      }
      int literalStart = input;
      input += repeated;
      while (input < frame.length && input - literalStart < MAX_LITERAL) {
        repeated = repeatLength(frame, input);
        if (repeated >= 3) break;
        if (input - literalStart + repeated > MAX_LITERAL) break;
        input += repeated;
      }
      int literalLength = input - literalStart;
      encoded[output++] = (byte) (literalLength - 1);
      System.arraycopy(frame, literalStart, encoded, output, literalLength);
      output += literalLength;
    }
    putU32(encoded, 8, output - HEADER_BYTES);
    return Arrays.copyOf(encoded, output);
  }

  public static byte[] decompress(byte[] encoded) {
    if (encoded == null || encoded.length < HEADER_BYTES
        || encoded[0] != 'D' || encoded[1] != 'F'
        || encoded[2] != 'R' || encoded[3] != '1') {
      throw new IllegalArgumentException("DFR1 header is invalid");
    }
    int frameLength = getU32(encoded, 4);
    int payloadLength = getU32(encoded, 8);
    if (frameLength != FRAME_BYTES
        || payloadLength != encoded.length - HEADER_BYTES) {
      throw new IllegalArgumentException("DFR1 lengths are invalid");
    }
    byte[] frame = new byte[frameLength];
    int input = HEADER_BYTES;
    int output = 0;
    while (input < encoded.length) {
      int token = encoded[input++] & 0xff;
      if ((token & 0x80) != 0) {
        int length = (token & 0x7f) + 3;
        if (input >= encoded.length || length > frame.length - output) {
          throw new IllegalArgumentException("DFR1 repeated run is truncated");
        }
        byte value = encoded[input++];
        Arrays.fill(frame, output, output + length, value);
        output += length;
      } else {
        int length = token + 1;
        if (length > encoded.length - input || length > frame.length - output) {
          throw new IllegalArgumentException("DFR1 literal is truncated");
        }
        System.arraycopy(encoded, input, frame, output, length);
        input += length;
        output += length;
      }
    }
    if (output != frame.length) {
      throw new IllegalArgumentException("DFR1 output length is invalid");
    }
    // Canonical tokenization is part of the codec identity.
    if (!Arrays.equals(encoded, compress(frame))) {
      throw new IllegalArgumentException("DFR1 stream is non-canonical");
    }
    return frame;
  }

  private static int repeatLength(byte[] frame, int offset) {
    int length = 1;
    while (length < MAX_REPEAT && offset + length < frame.length
        && frame[offset + length] == frame[offset]) {
      length++;
    }
    return length;
  }

  private static void putU32(byte[] target, int offset, int value) {
    target[offset] = (byte) value;
    target[offset + 1] = (byte) (value >>> 8);
    target[offset + 2] = (byte) (value >>> 16);
    target[offset + 3] = (byte) (value >>> 24);
  }

  private static int getU32(byte[] source, int offset) {
    return (source[offset] & 0xff)
        | (source[offset + 1] & 0xff) << 8
        | (source[offset + 2] & 0xff) << 16
        | (source[offset + 3] & 0xff) << 24;
  }
}
