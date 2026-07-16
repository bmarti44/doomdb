import java.nio.ByteBuffer;
import java.nio.ByteOrder;

/**
 * First differential slice of the retained OJVM simulation.
 *
 * This class deliberately owns no JDBC objects.  A worker loads one player row
 * at startup, then crosses the Java boundary with validated packed commands and
 * receives packed deltas.  SQL remains the durability and differential oracle.
 */
public final class DoomResidentSimulationBench {
  private static final int COMMAND_MAGIC = 0x444d5343; // DMSC
  private static final int DELTA_MAGIC = 0x444d5344;   // DMSD
  private static final byte VERSION = 1;
  private static final int COMMAND_HEADER_BYTES = 8;
  private static final int COMMAND_BYTES = 16;
  private static final int DELTA_HEADER_BYTES = 8;
  private static final int DELTA_BYTES = 24;
  private static final double TURN_DEGREES = 5.625d;

  private static boolean loaded;
  private static String sessionToken;
  private static long currentTic;
  private static long lastCommandSeq;
  private static double playerX;
  private static double playerY;
  private static double playerZ;
  private static double playerAngle;
  private static String lastError = "";

  private DoomResidentSimulationBench() {}

  private static void require(boolean condition, String message) {
    if (!condition) throw new IllegalArgumentException(message);
  }

  private static void requireSession(String session) {
    require(loaded, "state is not loaded");
    require(session != null && session.equals(sessionToken), "worker session mismatch");
  }

  private static double advanceAngle(double angle, int turn) {
    angle += turn * TURN_DEGREES;
    if (angle >= 360.0d) angle -= 360.0d;
    else if (angle < 0.0d) angle += 360.0d;
    return angle;
  }

  private static String failure(Throwable error) {
    String message = error.getMessage();
    lastError = error.getClass().getName() + (message == null ? "" : ": " + message);
    return "ERR|" + lastError;
  }

  /** Catch-all worker load boundary. */
  public static String loadPlayer(String session, long tic, long commandSeq,
      double x, double y, double z, double angle) {
    try {
      require(session != null && session.matches("[0-9a-f]{32}"), "invalid session token");
      require(tic >= 0 && commandSeq >= 0, "negative frontier");
      require(Double.isFinite(x) && Double.isFinite(y) && Double.isFinite(z),
          "non-finite position");
      require(Double.isFinite(angle) && angle >= 0.0d && angle < 360.0d,
          "invalid angle");
      sessionToken = session;
      currentTic = tic;
      lastCommandSeq = commandSeq;
      playerX = x;
      playerY = y;
      playerZ = z;
      playerAngle = angle;
      loaded = true;
      lastError = "";
      return "OK";
    } catch (Throwable error) {
      loaded = false;
      sessionToken = null;
      return failure(error);
    }
  }

  /** Scalar differential-test boundary; production uses stepTurnBatch. */
  public static String stepTurn(String session, long commandSeq, int turn) {
    try {
      requireSession(session);
      require(commandSeq == lastCommandSeq + 1, "command sequence gap");
      require(turn >= -1 && turn <= 1, "turn outside domain");
      playerAngle = advanceAngle(playerAngle, turn);
      currentTic++;
      lastCommandSeq = commandSeq;
      lastError = "";
      return "OK|" + commandSeq + "|" + currentTic + "|" + Double.toString(playerAngle);
    } catch (Throwable error) {
      return failure(error);
    }
  }

  /**
   * Apply 1..4 validated turn commands atomically without JDBC or allocation per
   * command. Input is DMSC/v1 plus 16-byte records (seq:int64, turn:int8,
   * reserved:7). Output is DMSD/v1 plus 24-byte records
   * (seq:int64, tic:int64, angle:binary64).
   */
  public static byte[] stepTurnBatch(String session, byte[] packedCommands) {
    try {
      requireSession(session);
      require(packedCommands != null && packedCommands.length >= COMMAND_HEADER_BYTES,
          "missing command pack");
      ByteBuffer input = ByteBuffer.wrap(packedCommands).order(ByteOrder.BIG_ENDIAN);
      require(input.getInt() == COMMAND_MAGIC, "command magic");
      require(input.get() == VERSION, "command version");
      int count = input.get() & 255;
      require(count >= 1 && count <= 4, "batch size");
      require(input.getShort() == 0, "command flags");
      require(packedCommands.length == COMMAND_HEADER_BYTES + count * COMMAND_BYTES,
          "command pack length");

      long nextSeq = lastCommandSeq;
      long nextTic = currentTic;
      double nextAngle = playerAngle;
      long[] sequences = new long[count];
      double[] angles = new double[count];
      for (int index = 0; index < count; index++) {
        long sequence = input.getLong();
        int turn = input.get();
        require(sequence == nextSeq + 1, "command sequence gap");
        require(turn >= -1 && turn <= 1, "turn outside domain");
        for (int reserved = 0; reserved < 7; reserved++) {
          require(input.get() == 0, "command reserved bytes");
        }
        nextSeq = sequence;
        nextTic++;
        nextAngle = advanceAngle(nextAngle, turn);
        sequences[index] = sequence;
        angles[index] = nextAngle;
      }

      ByteBuffer output = ByteBuffer.allocate(DELTA_HEADER_BYTES + count * DELTA_BYTES)
          .order(ByteOrder.BIG_ENDIAN);
      output.putInt(DELTA_MAGIC).put(VERSION).put((byte) 0).put((byte) count).put((byte) 0);
      long tic = currentTic;
      for (int index = 0; index < count; index++) {
        output.putLong(sequences[index]).putLong(++tic).putDouble(angles[index]);
      }
      lastCommandSeq = nextSeq;
      currentTic = nextTic;
      playerAngle = nextAngle;
      lastError = "";
      return output.array();
    } catch (Throwable error) {
      failure(error);
      ByteBuffer output = ByteBuffer.allocate(DELTA_HEADER_BYTES)
          .order(ByteOrder.BIG_ENDIAN);
      output.putInt(DELTA_MAGIC).put(VERSION).put((byte) 1).put((byte) 0).put((byte) 0);
      return output.array();
    }
  }

  /** No-state-change compute benchmark for the primitive-array turn kernel. */
  public static String benchmarkTurn(String session, int iterations) {
    try {
      requireSession(session);
      require(iterations >= 1 && iterations <= 100_000_000, "benchmark iterations");
      double angle = playerAngle;
      long started = System.nanoTime();
      for (int index = 0; index < iterations; index++) {
        angle = advanceAngle(angle, (index & 1) == 0 ? 1 : -1);
      }
      long elapsed = System.nanoTime() - started;
      // Consume the result without mutating authoritative worker state.
      require(Double.isFinite(angle), "benchmark result");
      lastError = "";
      return "OK|" + iterations + "|" + elapsed + "|" +
          Double.toString((double) elapsed / iterations);
    } catch (Throwable error) {
      return failure(error);
    }
  }

  public static String state(String session) {
    try {
      requireSession(session);
      return "OK|" + lastCommandSeq + "|" + currentTic + "|" +
          Double.toString(playerX) + "|" + Double.toString(playerY) + "|" +
          Double.toString(playerZ) + "|" + Double.toString(playerAngle);
    } catch (Throwable error) {
      return failure(error);
    }
  }

  public static String lastError() {
    try {
      return lastError;
    } catch (Throwable error) {
      return error.getClass().getName();
    }
  }
}
