package doomdb.mle.wasm2js;

import org.teavm.interop.Export;

/** Minimal i32/i64 shape used to distinguish pipeline support from Doom reachability. */
public final class Wasm2JsToolchainSmoke {
  private Wasm2JsToolchainSmoke() {}

  @Export(name = "smoke_mix")
  public static int mix(int left, int right) {
    return Integer.rotateLeft(left * 31 + right, 7) ^ 0x5a17c9e3;
  }

  @Export(name = "smoke_i64_low")
  public static int i64Low(int left, int right) {
    long product = (long) left * (long) right;
    return (int) (product ^ (product >>> 32));
  }

  public static void main(String[] args) {
    // Driven through low-level exports.
  }
}
