import java.sql.Clob;

/** Retained audible-wake phase for REJECT-hidden sleeping actors. */
public final class DoomActorWakeBench {
  private static boolean loaded, pending;
  private static String session, lineage, pendingRequest, lastError = "";
  private static long generation;
  private static int count;
  private static int[] id, health, seen, cooldown, awake, stateTics, sector;
  private static int[] stateIndex, target, seeStateIndex, seeStateTics;
  private static int[] nextSeen, nextCooldown, nextAwake, nextStateIndex, nextStateTics, nextTarget;
  private static int[] dirtyIndex, wakeIndex;
  private static final byte[] delta = new byte[12 + 255 * 32 + 255 * 12];

  private DoomActorWakeBench() {}
  private static void require(boolean value, String message) {
    if (!value) throw new IllegalStateException(message);
  }
  private static final class Parser {
    final String text; int offset;
    Parser(String text) { this.text = text; }
    void whitespace() { while (offset < text.length() && text.charAt(offset) <= ' ') offset++; }
    void expect(char value) { whitespace(); require(offset < text.length() &&
        text.charAt(offset++) == value, "wake JSON syntax"); }
    boolean take(char value) { whitespace(); if (offset < text.length() &&
        text.charAt(offset) == value) { offset++; return true; } return false; }
    int integer(boolean nullable) {
      whitespace();
      if (nullable && text.startsWith("null", offset)) { offset += 4; return -1; }
      int sign = 1, value = 0;
      if (offset < text.length() && text.charAt(offset) == '-') { sign = -1; offset++; }
      int start = offset;
      while (offset < text.length() && Character.isDigit(text.charAt(offset)))
        value = value * 10 + text.charAt(offset++) - '0';
      require(offset > start, "wake JSON integer"); return sign * value;
    }
  }
  private static void putInt(byte[] bytes, int offset, int value) {
    bytes[offset] = (byte) (value >>> 24); bytes[offset + 1] = (byte) (value >>> 16);
    bytes[offset + 2] = (byte) (value >>> 8); bytes[offset + 3] = (byte) value;
  }
  private static void putShort(byte[] bytes, int offset, int value) {
    bytes[offset] = (byte) (value >>> 8); bytes[offset + 1] = (byte) value;
  }
  private static String fail(Throwable error) {
    lastError = error.getClass().getName() + ":" + error.getMessage();
    return "ERR|" + lastError;
  }

  public static String load(String loadedSession, String loadedLineage, long loadedGeneration,
      Clob snapshot) {
    try {
      require(!pending, "pending wake load");
      require(loadedSession != null && loadedSession.matches("[0-9a-f]{32}"), "session");
      require(loadedLineage != null && loadedLineage.matches("[0-9a-f]{64}"), "lineage");
      require(loadedGeneration > 0 && snapshot != null && snapshot.length() <= 1048576, "load");
      String json = snapshot.getSubString(1, (int) snapshot.length());
      Parser parser = new Parser(json); parser.expect('['); int rows = 0;
      if (!parser.take(']')) {
        do {
          parser.expect('[');
          for (int field = 0; field < 11; field++) {
            parser.integer(field == 2 || field == 8); if (field < 10) parser.expect(',');
          }
          parser.expect(']'); rows++;
        } while (parser.take(',')); parser.expect(']');
      }
      require(rows <= 255, "wake actor count");
      int[][] values = new int[11][rows];
      parser = new Parser(json); parser.expect('['); int row = 0;
      if (!parser.take(']')) {
        do {
          parser.expect('[');
          for (int field = 0; field < 11; field++) {
            values[field][row] = parser.integer(field == 2 || field == 8);
            if (field < 10) parser.expect(',');
          }
          parser.expect(']');
          require(values[0][row] >= 0 && (row == 0 || values[0][row] > values[0][row - 1]),
              "wake actor order");
          require(values[1][row] > 0 && (values[2][row] == -1 || values[2][row] >= 0) &&
              values[3][row] >= 0 && (values[4][row] == 0 || values[4][row] == 1) &&
              values[5][row] >= -1 && values[6][row] >= 0 && values[7][row] >= 0 &&
              values[8][row] >= -1 && values[9][row] >= 0 && values[10][row] >= -1,
              "wake actor value");
          row++;
        } while (parser.take(',')); parser.expect(']');
      }
      require(row == rows && parser.offset == json.length(), "wake snapshot trailing bytes");
      id = values[0]; health = values[1]; seen = values[2]; cooldown = values[3];
      awake = values[4]; stateTics = values[5]; sector = values[6]; stateIndex = values[7];
      target = values[8]; seeStateIndex = values[9]; seeStateTics = values[10];
      nextSeen = new int[rows]; nextCooldown = new int[rows]; nextAwake = new int[rows];
      nextStateIndex = new int[rows]; nextStateTics = new int[rows]; nextTarget = new int[rows];
      dirtyIndex = new int[rows]; wakeIndex = new int[rows];
      session = loadedSession; lineage = loadedLineage; generation = loadedGeneration;
      count = rows; loaded = true; pending = false; pendingRequest = null; lastError = "";
      return "OK|" + count;
    } catch (Throwable error) { return fail(error); }
  }

  private static void fence(String expectedSession, String expectedLineage, long expectedGeneration) {
    require(loaded, "wake actors not loaded");
    require(session.equals(expectedSession) && lineage.equals(expectedLineage) &&
        generation == expectedGeneration, "wake actor fence");
  }

  public static byte[] prepare(String expectedSession, String expectedLineage,
      long expectedGeneration, String request, double playerX, double playerY,
      int playerMadeSound, int playerTarget, int firstEventOrdinal) {
    try {
      fence(expectedSession, expectedLineage, expectedGeneration);
      require(!pending && request != null && request.matches("[0-9a-f]{32}"), "wake request");
      require(Double.isFinite(playerX) && Double.isFinite(playerY) &&
          (playerMadeSound == 0 || playerMadeSound == 1) && playerTarget >= -1 &&
          firstEventOrdinal >= 0, "wake input");
      int playerSector = DoomSimCatalogBench.locateSector(playerX, playerY);
      require(playerSector >= 0, "wake player sector");
      int dirty = 0, wakes = 0;
      for (int index = 0; index < count; index++) {
        int rejected = DoomSimCatalogBench.rejected(sector[index], playerSector);
        int reaches = DoomSimCatalogBench.soundReach(playerSector, sector[index]);
        require(health[index] > 0 && awake[index] == 0 &&
            (seen[index] == -1 || seen[index] == health[index]),
            "unsupported wake actor mobj=" + id[index]);
        require(rejected == 1, "LOS-dependent wake actor mobj=" + id[index]);
        boolean wake = playerMadeSound == 1 && reaches == 1;
        nextSeen[index] = health[index]; nextCooldown[index] = Math.max(0, cooldown[index] - 1);
        nextAwake[index] = wake ? 1 : awake[index];
        nextStateIndex[index] = wake ? seeStateIndex[index] : stateIndex[index];
        nextStateTics[index] = wake ? seeStateTics[index] : stateTics[index];
        nextTarget[index] = wake ? playerTarget : target[index];
        if (nextSeen[index] != seen[index] || nextCooldown[index] != cooldown[index] || wake)
          dirtyIndex[dirty++] = index;
        if (wake) wakeIndex[wakes++] = index;
      }
      for (int index = 0; index < delta.length; index++) delta[index] = 0;
      putInt(delta, 0, 0x4441574b); // DAWK
      delta[4] = 1; delta[5] = 0; putShort(delta, 6, dirty); putShort(delta, 8, wakes);
      for (int item = 0; item < dirty; item++) {
        int actor = dirtyIndex[item], offset = 12 + item * 32;
        int mask = (nextSeen[actor] != seen[actor] || nextCooldown[actor] != cooldown[actor] ? 1 : 0) |
            (nextAwake[actor] != awake[actor] ? 2 : 0);
        putInt(delta, offset, id[actor]); putInt(delta, offset + 4, mask);
        putInt(delta, offset + 8, nextSeen[actor]); putInt(delta, offset + 12, nextCooldown[actor]);
        putInt(delta, offset + 16, nextAwake[actor]); putInt(delta, offset + 20, nextStateIndex[actor]);
        putInt(delta, offset + 24, nextStateTics[actor]); putInt(delta, offset + 28, nextTarget[actor]);
      }
      int eventOffset = 12 + dirty * 32;
      for (int item = 0; item < wakes; item++) {
        int actor = wakeIndex[item], offset = eventOffset + item * 12;
        putInt(delta, offset, firstEventOrdinal + item); putInt(delta, offset + 4, id[actor]);
        putInt(delta, offset + 8, playerTarget);
      }
      pending = true; pendingRequest = request; lastError = ""; return delta;
    } catch (Throwable error) {
      fail(error); for (int index = 0; index < 12; index++) delta[index] = 0;
      putInt(delta, 0, 0x4441574b); delta[4] = 1; delta[5] = 1; return delta;
    }
  }

  public static String accept(String expectedSession, String expectedLineage,
      long expectedGeneration, String request) {
    try {
      fence(expectedSession, expectedLineage, expectedGeneration);
      require(pending && request != null && request.equals(pendingRequest), "wake pending request");
      for (int index = 0; index < count; index++) {
        seen[index] = nextSeen[index]; cooldown[index] = nextCooldown[index];
        awake[index] = nextAwake[index]; stateIndex[index] = nextStateIndex[index];
        stateTics[index] = nextStateTics[index]; target[index] = nextTarget[index];
      }
      pending = false; pendingRequest = null; lastError = ""; return "OK";
    } catch (Throwable error) { return fail(error); }
  }
  public static String discard(String expectedSession, String expectedLineage,
      long expectedGeneration, String request) {
    try {
      fence(expectedSession, expectedLineage, expectedGeneration);
      require(pending && request != null && request.equals(pendingRequest), "wake pending request");
      pending = false; pendingRequest = null; lastError = ""; return "OK";
    } catch (Throwable error) { return fail(error); }
  }
  public static String lastError() {
    try { return lastError; } catch (Throwable error) { return error.getClass().getName(); }
  }
}
