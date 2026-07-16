import oracle.sql.NUMBER;

/** Exact-arithmetic feasibility probe for the retained simulation. */
public final class DoomOracleNumberParityBench {
  private static final NUMBER ZERO = NUMBER.zero();
  private static final NUMBER TWO = new NUMBER(2);
  private static final NUMBER FOUR = new NUMBER(4);
  private static final NUMBER EIGHT = new NUMBER(8);
  private static final NUMBER ONE_EIGHTY = new NUMBER(180);
  private static String lastError = "";

  private DoomOracleNumberParityBench() {}

  private static NUMBER radians(NUMBER angle) throws Exception {
    return angle.mul(NUMBER.pi()).div(ONE_EIGHTY);
  }

  public static NUMBER movementDeltaX(NUMBER angle, int forward, int strafe, int run) {
    try {
      NUMBER rad = radians(angle);
      NUMBER result = new NUMBER(forward).mul(rad.cos())
          .add(new NUMBER(strafe).mul(rad.sin()))
          .mul(EIGHT).mul(new NUMBER(run + 1));
      lastError = "";
      return result;
    } catch (Throwable error) {
      lastError = error.getClass().getName() + ":" + error.getMessage();
      return null;
    }
  }

  public static NUMBER movementDeltaY(NUMBER angle, int forward, int strafe, int run) {
    try {
      NUMBER rad = radians(angle);
      NUMBER result = new NUMBER(forward).mul(rad.sin())
          .sub(new NUMBER(strafe).mul(rad.cos()))
          .mul(EIGHT).mul(new NUMBER(run + 1));
      lastError = "";
      return result;
    } catch (Throwable error) {
      lastError = error.getClass().getName() + ":" + error.getMessage();
      return null;
    }
  }

  public static NUMBER quadraticEntry(NUMBER px, NUMBER py, NUMBER ex, NUMBER ey,
      NUMBER dx, NUMBER dy, NUMBER radius) {
    try {
      NUMBER rx = px.sub(ex), ry = py.sub(ey);
      NUMBER qa = dx.mul(dx).add(dy.mul(dy));
      NUMBER qb = TWO.mul(rx.mul(dx).add(ry.mul(dy)));
      NUMBER constant = rx.mul(rx).add(ry.mul(ry)).sub(radius.mul(radius));
      NUMBER discriminant = qb.mul(qb).sub(FOUR.mul(qa).mul(constant));
      NUMBER root = qb.negate().sub(discriminant.compareTo(ZERO) < 0 ? ZERO :
          discriminant.sqroot()).div(TWO.mul(qa));
      lastError = "";
      return root;
    } catch (Throwable error) {
      lastError = error.getClass().getName() + ":" + error.getMessage();
      return null;
    }
  }

  public static String benchmarkMovement(int iterations) {
    try {
      if (iterations < 1 || iterations > 1_000_000) throw new IllegalArgumentException("iterations");
      NUMBER[] angles = new NUMBER[64];
      for (int index = 0; index < angles.length; index++) {
        angles[index] = new NUMBER(index * 5.625d);
      }
      NUMBER result = ZERO;
      long started = System.nanoTime();
      for (int index = 0; index < iterations; index++) {
        result = movementDeltaX(angles[index & 63], 1, index & 1, index & 1);
        if (result == null) throw new IllegalStateException(lastError);
      }
      long elapsed = System.nanoTime() - started;
      lastError = "";
      return "OK|" + iterations + "|" + elapsed + "|" +
          Double.toString((double) elapsed / iterations) + "|" + result.stringValue();
    } catch (Throwable error) {
      lastError = error.getClass().getName() + ":" + error.getMessage();
      return "ERR|" + lastError;
    }
  }

  public static String benchmarkLookup(int iterations) {
    try {
      if (iterations < 1 || iterations > 10_000_000) throw new IllegalArgumentException("iterations");
      NUMBER[] deltaX = new NUMBER[64 * 18];
      int cursor = 0;
      for (int angle = 0; angle < 64; angle++) {
        NUMBER degrees = new NUMBER(angle * 5.625d);
        for (int forward = -1; forward <= 1; forward++) {
          for (int strafe = -1; strafe <= 1; strafe++) {
            for (int run = 0; run <= 1; run++) {
              deltaX[cursor++] = movementDeltaX(degrees, forward, strafe, run);
            }
          }
        }
      }
      NUMBER position = ZERO;
      long started = System.nanoTime();
      for (int index = 0; index < iterations; index++) {
        position = position.add(deltaX[index % deltaX.length]);
      }
      long elapsed = System.nanoTime() - started;
      lastError = "";
      return "OK|" + iterations + "|" + elapsed + "|" +
          Double.toString((double) elapsed / iterations) + "|" + position.stringValue();
    } catch (Throwable error) {
      lastError = error.getClass().getName() + ":" + error.getMessage();
      return "ERR|" + lastError;
    }
  }

  public static String benchmarkQuadratic(int iterations) {
    try {
      if (iterations < 1 || iterations > 100_000) throw new IllegalArgumentException("iterations");
      NUMBER result = ZERO;
      NUMBER px = new NUMBER(-416), py = new NUMBER(256), ex = new NUMBER(-400);
      NUMBER ey = new NUMBER(240), dx = new NUMBER(8), dy = new NUMBER(4);
      NUMBER radius = new NUMBER(16);
      long started = System.nanoTime();
      for (int index = 0; index < iterations; index++) {
        result = quadraticEntry(px, py, ex, ey, dx, dy, radius);
        if (result == null) throw new IllegalStateException(lastError);
      }
      long elapsed = System.nanoTime() - started;
      lastError = "";
      return "OK|" + iterations + "|" + elapsed + "|" +
          Double.toString((double) elapsed / iterations) + "|" + result.stringValue();
    } catch (Throwable error) {
      lastError = error.getClass().getName() + ":" + error.getMessage();
      return "ERR|" + lastError;
    }
  }

  public static String lastError() {
    try { return lastError; }
    catch (Throwable error) { return error.getClass().getName(); }
  }
}
