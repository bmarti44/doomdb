/* GPLv3-or-later: links with the pinned Mocha Doom engine. */
package doomdb.mle.engine;

import org.teavm.jso.JSExport;
import org.teavm.jso.typedarrays.Uint8Array;

/** TeaVM/ES-module boundary for the separately pinned compiled DVR codec. */
public final class DvrFrameCodecReachabilityProbe {
  private DvrFrameCodecReachabilityProbe() {}

  @JSExport
  public static String codecId() {
    return DvrFrameCodec.CODEC_ID;
  }

  @JSExport
  public static int codecVersion() {
    return DvrFrameCodec.CODEC_VERSION;
  }

  @JSExport
  public static Uint8Array compressFrame(Uint8Array frame) {
    byte[] input = fromTypedArray(frame);
    return toTypedArray(DvrFrameCodec.compress(input));
  }

  @JSExport
  public static Uint8Array decompressFrame(Uint8Array encoded) {
    byte[] input = fromTypedArray(encoded);
    return toTypedArray(DvrFrameCodec.decompress(input));
  }

  private static byte[] fromTypedArray(Uint8Array source) {
    if (source == null) throw new IllegalArgumentException("typed array is null");
    byte[] result = new byte[source.getLength()];
    for (int index = 0; index < result.length; index++) {
      result[index] = (byte) source.get(index);
    }
    return result;
  }

  private static Uint8Array toTypedArray(byte[] source) {
    Uint8Array result = Uint8Array.create(source.length);
    for (int index = 0; index < source.length; index++) {
      result.set(index, (short) (source[index] & 0xff));
    }
    return result;
  }

  public static void main(String[] args) {
    // Oracle MLE and the Node verifier drive the explicit exports.
  }
}
