import oracle.sql.NUMBER;

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
  private static final int MOVEMENT_DELTA_BYTES = 96;
  private static final double TURN_DEGREES = 5.625d;

  private static boolean loaded;
  private static String sessionToken;
  private static long currentTic;
  private static long lastCommandSeq;
  private static double playerX;
  private static double playerY;
  private static double playerZ;
  private static double playerAngle;
  private static NUMBER exactPlayerX;
  private static NUMBER exactPlayerY;
  private static NUMBER exactPlayerZ;
  private static String lineage;
  private static long workerGeneration;
  private static boolean pending;
  private static String pendingRequest;
  private static long pendingTic;
  private static long pendingCommandSeq;
  private static double pendingX;
  private static double pendingY;
  private static double pendingZ;
  private static double pendingAngle;
  private static NUMBER pendingExactX;
  private static NUMBER pendingExactY;
  private static NUMBER pendingExactZ;
  private static final long[] scratchSequence = new long[4];
  private static final double[] scratchAngle = new double[4];
  private static final byte[] deltaBuffer = new byte[DELTA_HEADER_BYTES + 4 * DELTA_BYTES];
  private static final byte[] movementDeltaBuffer =
      new byte[DELTA_HEADER_BYTES + 4 * MOVEMENT_DELTA_BYTES];
  private static String lastError = "";

  private DoomResidentSimulationBench() {}

  private static void require(boolean condition, String message) {
    if (!condition) throw new IllegalArgumentException(message);
  }

  private static void requireFence(String session, String expectedLineage, long generation) {
    require(loaded, "state is not loaded");
    require(session != null && session.equals(sessionToken), "worker session mismatch");
    require(expectedLineage != null && expectedLineage.equals(lineage), "worker lineage mismatch");
    require(generation == workerGeneration, "worker generation mismatch");
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
  public static String loadPlayer(String session, String loadedLineage, long generation,
      long tic, long commandSeq,
      double x, double y, double z, double angle) {
    try {
      require(session != null && session.matches("[0-9a-f]{32}"), "invalid session token");
      require(loadedLineage != null && loadedLineage.matches("[0-9a-f]{64}"),
          "invalid lineage");
      require(generation > 0, "invalid worker generation");
      require(tic >= 0 && commandSeq >= 0, "negative frontier");
      require(Double.isFinite(x) && Double.isFinite(y) && Double.isFinite(z),
          "non-finite position");
      require(Double.isFinite(angle) && angle >= 0.0d && angle < 360.0d,
          "invalid angle");
      sessionToken = session;
      lineage = loadedLineage;
      workerGeneration = generation;
      currentTic = tic;
      lastCommandSeq = commandSeq;
      playerX = x;
      playerY = y;
      playerZ = z;
      playerAngle = angle;
      exactPlayerX = new NUMBER(x); exactPlayerY = new NUMBER(y); exactPlayerZ = new NUMBER(z);
      pending = false;
      pendingRequest = null;
      loaded = true;
      lastError = "";
      return "OK";
    } catch (Throwable error) {
      loaded = false;
      sessionToken = null;
      lineage = null;
      pending = false;
      pendingRequest = null;
      return failure(error);
    }
  }

  public static String loadExactPlayer(String session, String loadedLineage, long generation,
      long tic, long commandSeq, NUMBER x, NUMBER y, NUMBER z, double angle) {
    try {
      require(x != null && y != null && z != null, "missing exact position");
      String result = loadPlayer(session, loadedLineage, generation, tic, commandSeq,
          x.doubleValue(), y.doubleValue(), z.doubleValue(), angle);
      require("OK".equals(result), result);
      exactPlayerX = x; exactPlayerY = y; exactPlayerZ = z;
      return "OK";
    } catch (Throwable error) {
      loaded = false; pending = false; return failure(error);
    }
  }

  /** Scalar differential-test boundary; production uses stepTurnBatch. */
  public static String stepTurn(String session, String expectedLineage, long generation,
      long commandSeq, int turn) {
    try {
      requireFence(session, expectedLineage, generation);
      require(!pending, "prepared batch is awaiting resolution");
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
  private static int readInt(byte[] bytes, int offset) {
    return ((bytes[offset] & 255) << 24) | ((bytes[offset + 1] & 255) << 16) |
        ((bytes[offset + 2] & 255) << 8) | (bytes[offset + 3] & 255);
  }

  private static long readLong(byte[] bytes, int offset) {
    return ((long) readInt(bytes, offset) << 32) | (readInt(bytes, offset + 4) & 0xffffffffL);
  }

  private static void putInt(byte[] bytes, int offset, int value) {
    bytes[offset] = (byte) (value >>> 24); bytes[offset + 1] = (byte) (value >>> 16);
    bytes[offset + 2] = (byte) (value >>> 8); bytes[offset + 3] = (byte) value;
  }

  private static void putLong(byte[] bytes, int offset, long value) {
    putInt(bytes, offset, (int) (value >>> 32)); putInt(bytes, offset + 4, (int) value);
  }

  private static void writeDeltaHeader(int status, int count) {
    for (int index = 0; index < deltaBuffer.length; index++) deltaBuffer[index] = 0;
    putInt(deltaBuffer, 0, DELTA_MAGIC);
    deltaBuffer[4] = VERSION; deltaBuffer[5] = (byte) status;
    deltaBuffer[6] = (byte) count;
  }

  private static void writeMovementHeader(int status, int count) {
    for (int index = 0; index < movementDeltaBuffer.length; index++) movementDeltaBuffer[index] = 0;
    putInt(movementDeltaBuffer, 0, DELTA_MAGIC);
    movementDeltaBuffer[4] = 2; movementDeltaBuffer[5] = (byte) status;
    movementDeltaBuffer[6] = (byte) count;
  }

  private static void putNumber(byte[] output, int offset, NUMBER value) {
    byte[] bytes = value.toBytes();
    require(bytes.length >= 1 && bytes.length <= 22, "NUMBER byte length");
    output[offset] = (byte) bytes.length;
    System.arraycopy(bytes, 0, output, offset + 1, bytes.length);
  }

  public static byte[] prepareTurnBatch(String session, String expectedLineage,
      long generation, String request, byte[] packedCommands) {
    try {
      requireFence(session, expectedLineage, generation);
      require(!pending, "prepared batch is awaiting resolution");
      require(request != null && request.matches("[0-9a-f]{32}"), "invalid request id");
      require(packedCommands != null && packedCommands.length >= COMMAND_HEADER_BYTES,
          "missing command pack");
      require(readInt(packedCommands, 0) == COMMAND_MAGIC, "command magic");
      require(packedCommands[4] == VERSION, "command version");
      int count = packedCommands[5] & 255;
      require(count >= 1 && count <= 4, "batch size");
      require(packedCommands[6] == 0 && packedCommands[7] == 0, "command flags");
      require(packedCommands.length == COMMAND_HEADER_BYTES + count * COMMAND_BYTES,
          "command pack length");

      long nextSeq = lastCommandSeq;
      long nextTic = currentTic;
      double nextAngle = playerAngle;
      for (int index = 0; index < count; index++) {
        int offset = COMMAND_HEADER_BYTES + index * COMMAND_BYTES;
        long sequence = readLong(packedCommands, offset);
        int turn = packedCommands[offset + 8];
        require(sequence == nextSeq + 1, "command sequence gap");
        require(turn >= -1 && turn <= 1, "turn outside domain");
        for (int reserved = 0; reserved < 7; reserved++) {
          require(packedCommands[offset + 9 + reserved] == 0, "command reserved bytes");
        }
        nextSeq = sequence;
        nextTic++;
        nextAngle = advanceAngle(nextAngle, turn);
        scratchSequence[index] = sequence;
        scratchAngle[index] = nextAngle;
      }

      writeDeltaHeader(0, count);
      long tic = currentTic;
      for (int index = 0; index < count; index++) {
        int offset = DELTA_HEADER_BYTES + index * DELTA_BYTES;
        putLong(deltaBuffer, offset, scratchSequence[index]);
        putLong(deltaBuffer, offset + 8, ++tic);
        putLong(deltaBuffer, offset + 16, Double.doubleToRawLongBits(scratchAngle[index]));
      }
      pendingCommandSeq = nextSeq;
      pendingTic = nextTic;
      pendingX = playerX; pendingY = playerY; pendingZ = playerZ;
      pendingAngle = nextAngle;
      pendingRequest = request;
      pending = true;
      lastError = "";
      return deltaBuffer;
    } catch (Throwable error) {
      failure(error);
      writeDeltaHeader(1, 0);
      return deltaBuffer;
    }
  }

  public static String accept(String session, String expectedLineage, long generation,
      String request) {
    try {
      requireFence(session, expectedLineage, generation);
      require(pending, "no prepared batch");
      require(request != null && request.equals(pendingRequest), "prepared request mismatch");
      lastCommandSeq = pendingCommandSeq; currentTic = pendingTic;
      playerX = pendingX; playerY = pendingY; playerZ = pendingZ; playerAngle = pendingAngle;
      exactPlayerX = pendingExactX; exactPlayerY = pendingExactY; exactPlayerZ = pendingExactZ;
      pending = false; pendingRequest = null; lastError = "";
      return "OK";
    } catch (Throwable error) {
      return failure(error);
    }
  }

  /** Version-2 transactional batch: turn plus exact retained player movement. */
  public static byte[] prepareMovementBatch(String session, String expectedLineage,
      long generation, String request, byte[] packedCommands) {
    try {
      requireFence(session, expectedLineage, generation);
      require(!pending, "prepared batch is awaiting resolution");
      require(request != null && request.matches("[0-9a-f]{32}"), "invalid request id");
      require(packedCommands != null && packedCommands.length >= COMMAND_HEADER_BYTES,
          "missing command pack");
      require(readInt(packedCommands, 0) == COMMAND_MAGIC && packedCommands[4] == 2,
          "movement command header");
      int count = packedCommands[5] & 255;
      require(count >= 1 && count <= 4 && packedCommands[6] == 0 && packedCommands[7] == 0,
          "movement batch header");
      require(packedCommands.length == COMMAND_HEADER_BYTES + count * COMMAND_BYTES,
          "movement command length");

      long nextSeq = lastCommandSeq, nextTic = currentTic;
      double nextAngle = playerAngle;
      NUMBER nextX = exactPlayerX, nextY = exactPlayerY, nextZ = exactPlayerZ;
      writeMovementHeader(0, count);
      for (int index = 0; index < count; index++) {
        int inputOffset = COMMAND_HEADER_BYTES + index * COMMAND_BYTES;
        long sequence = readLong(packedCommands, inputOffset);
        int turn = packedCommands[inputOffset + 8];
        int forward = packedCommands[inputOffset + 9];
        int strafe = packedCommands[inputOffset + 10];
        int run = packedCommands[inputOffset + 11];
        require(sequence == nextSeq + 1, "command sequence gap");
        require(turn >= -1 && turn <= 1 && forward >= -1 && forward <= 1 &&
            strafe >= -1 && strafe <= 1 && run >= 0 && run <= 1, "movement command domain");
        for (int reserved = 12; reserved < 16; reserved++) {
          require(packedCommands[inputOffset + reserved] == 0, "movement reserved bytes");
        }
        nextAngle = advanceAngle(nextAngle, turn);
        int angleIndex = ((int) Math.round(nextAngle / TURN_DEGREES)) & 63;
        String movement = DoomPlayerMovementBench.move(nextX, nextY, nextZ, angleIndex,
            forward, strafe, run);
        require(movement.indexOf("\"error\"") < 0, DoomPlayerMovementBench.lastError());
        nextX = DoomPlayerMovementBench.resultX;
        nextY = DoomPlayerMovementBench.resultY;
        nextZ = DoomPlayerMovementBench.resultZ;
        nextSeq = sequence; nextTic++;
        int outputOffset = DELTA_HEADER_BYTES + index * MOVEMENT_DELTA_BYTES;
        putLong(movementDeltaBuffer, outputOffset, sequence);
        putLong(movementDeltaBuffer, outputOffset + 8, nextTic);
        putLong(movementDeltaBuffer, outputOffset + 16,
            Double.doubleToRawLongBits(nextAngle));
        putNumber(movementDeltaBuffer, outputOffset + 24, nextX);
        putNumber(movementDeltaBuffer, outputOffset + 47, nextY);
        putNumber(movementDeltaBuffer, outputOffset + 70, nextZ);
      }
      pendingCommandSeq = nextSeq; pendingTic = nextTic; pendingAngle = nextAngle;
      pendingExactX = nextX; pendingExactY = nextY; pendingExactZ = nextZ;
      pendingX = nextX.doubleValue(); pendingY = nextY.doubleValue(); pendingZ = nextZ.doubleValue();
      pendingRequest = request; pending = true; lastError = "";
      return movementDeltaBuffer;
    } catch (Throwable error) {
      failure(error); writeMovementHeader(1, 0); return movementDeltaBuffer;
    }
  }

  public static String discard(String session, String expectedLineage, long generation,
      String request) {
    try {
      requireFence(session, expectedLineage, generation);
      require(pending, "no prepared batch");
      require(request != null && request.equals(pendingRequest), "prepared request mismatch");
      pending = false; pendingRequest = null; lastError = "";
      return "OK";
    } catch (Throwable error) {
      return failure(error);
    }
  }

  /** No-state-change compute benchmark for the primitive-array turn kernel. */
  public static String benchmarkTurn(String session, String expectedLineage, long generation,
      int iterations) {
    try {
      requireFence(session, expectedLineage, generation);
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

  public static String state(String session, String expectedLineage, long generation) {
    try {
      requireFence(session, expectedLineage, generation);
      return "OK|" + lastCommandSeq + "|" + currentTic + "|" +
          Double.toString(playerX) + "|" + Double.toString(playerY) + "|" +
          Double.toString(playerZ) + "|" + Double.toString(playerAngle);
    } catch (Throwable error) {
      return failure(error);
    }
  }

  public static String pendingState(String session, String expectedLineage, long generation,
      String request) {
    try {
      requireFence(session, expectedLineage, generation);
      require(pending, "no prepared batch");
      require(request != null && request.equals(pendingRequest), "prepared request mismatch");
      return "OK|" + pendingCommandSeq + "|" + pendingTic + "|" +
          Double.toString(pendingX) + "|" + Double.toString(pendingY) + "|" +
          Double.toString(pendingZ) + "|" + Double.toString(pendingAngle);
    } catch (Throwable error) {
      return failure(error);
    }
  }

  public static String exactState(String session, String expectedLineage, long generation) {
    try {
      requireFence(session, expectedLineage, generation);
      return "OK|" + lastCommandSeq + "|" + currentTic + "|" + exactPlayerX.stringValue() +
          "|" + exactPlayerY.stringValue() + "|" + exactPlayerZ.stringValue() + "|" +
          Double.toString(playerAngle);
    } catch (Throwable error) { return failure(error); }
  }

  public static String lastError() {
    try {
      return lastError;
    } catch (Throwable error) {
      return error.getClass().getName();
    }
  }
}
