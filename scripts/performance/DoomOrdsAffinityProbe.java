/** Disposable ORDS/OJVM database-session affinity probe. */
public final class DoomOrdsAffinityProbe {
  private static long counter;

  private DoomOrdsAffinityProbe() {}

  public static synchronized String next() {
    try {
      return Long.toString(++counter);
    } catch (Throwable failure) {
      // Never let an exception escape an OJVM entry point and poison the
      // proxied database session while the ORDS request survives.
      return "ERROR:" + failure.getClass().getName();
    }
  }
}
