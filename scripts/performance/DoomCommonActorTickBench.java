import java.sql.Clob;

/** Fail-closed first phase of retained MOBJ advancement. */
public final class DoomCommonActorTickBench {
  private static boolean loaded, pending;
  private static String session, lineage, pendingRequest, lastError = "";
  private static long generation;
  private static int count;
  private static int[] mobjId, health, healthSeen, cooldown, awake, stateTics, sector;
  private static int[] pendingHealthSeen, pendingCooldown, dirtyIndex;
  private static final byte[] delta = new byte[8 + 255 * 12];

  private DoomCommonActorTickBench() {}

  private static void require(boolean value, String message) {
    if (!value) throw new IllegalStateException(message);
  }

  private static final class Parser {
    final String text; int offset;
    Parser(String text) { this.text = text; }
    void whitespace() { while (offset < text.length() && text.charAt(offset) <= ' ') offset++; }
    void expect(char value) { whitespace(); require(offset < text.length() &&
        text.charAt(offset++) == value, "actor JSON syntax"); }
    boolean take(char value) { whitespace(); if (offset < text.length() &&
        text.charAt(offset) == value) { offset++; return true; } return false; }
    int integer(boolean nullable) {
      whitespace();
      if (nullable && text.startsWith("null", offset)) { offset += 4; return -1; }
      int sign = 1, value = 0; if (text.charAt(offset) == '-') { sign = -1; offset++; }
      int start = offset; while (offset < text.length() && Character.isDigit(text.charAt(offset)))
        value = value * 10 + text.charAt(offset++) - '0';
      require(offset > start, "actor JSON integer"); return sign * value;
    }
  }

  private static void putInt(byte[] bytes, int offset, int value) {
    bytes[offset] = (byte) (value >>> 24); bytes[offset + 1] = (byte) (value >>> 16);
    bytes[offset + 2] = (byte) (value >>> 8); bytes[offset + 3] = (byte) value;
  }

  private static String fail(Throwable error) {
    lastError = error.getClass().getName() + ":" + error.getMessage();
    return "ERR|" + lastError;
  }

  public static String load(String loadedSession, String loadedLineage, long loadedGeneration,
      Clob snapshot) {
    try {
      require(!pending, "pending actor load");
      require(loadedSession != null && loadedSession.matches("[0-9a-f]{32}"), "session");
      require(loadedLineage != null && loadedLineage.matches("[0-9a-f]{64}"), "lineage");
      require(loadedGeneration > 0 && snapshot != null && snapshot.length() <= 1048576, "load");
      Parser parser = new Parser(snapshot.getSubString(1, (int) snapshot.length()));
      parser.expect('['); int rows = 0;
      if (!parser.take(']')) {
        do { parser.expect('['); for (int field = 0; field < 7; field++) {
            parser.integer(field == 2); if (field < 6) parser.expect(',');
          } parser.expect(']'); rows++;
        } while (parser.take(',')); parser.expect(']');
      }
      require(rows >= 0 && rows <= 255, "actor count");
      int[] newMobjId = new int[rows], newHealth = new int[rows], newHealthSeen = new int[rows];
      int[] newCooldown = new int[rows], newAwake = new int[rows], newStateTics = new int[rows];
      int[] newSector = new int[rows];
      parser = new Parser(snapshot.getSubString(1, (int) snapshot.length())); parser.expect('[');
      int index = 0;
      if (!parser.take(']')) {
        do {
          parser.expect('['); newMobjId[index] = parser.integer(false); parser.expect(',');
          newHealth[index] = parser.integer(false); parser.expect(',');
          newHealthSeen[index] = parser.integer(true); parser.expect(',');
          newCooldown[index] = parser.integer(false); parser.expect(',');
          newAwake[index] = parser.integer(false); parser.expect(',');
          newStateTics[index] = parser.integer(false); parser.expect(',');
          newSector[index] = parser.integer(false); parser.expect(']');
          require(newMobjId[index] >= 0 &&
              (index == 0 || newMobjId[index] > newMobjId[index - 1]),
              "actor order");
          require(newHealth[index] >= 0 &&
              (newHealthSeen[index] == -1 || newHealthSeen[index] >= 0) &&
              newCooldown[index] >= 0 && (newAwake[index] == 0 || newAwake[index] == 1) &&
              newStateTics[index] >= -1 && newSector[index] >= 0, "actor value");
          index++;
        } while (parser.take(',')); parser.expect(']');
      }
      require(index == rows && parser.offset == parser.text.length(), "actor snapshot trailing bytes");
      mobjId = newMobjId; health = newHealth; healthSeen = newHealthSeen;
      cooldown = newCooldown; awake = newAwake; stateTics = newStateTics; sector = newSector;
      pendingHealthSeen = new int[rows]; pendingCooldown = new int[rows];
      dirtyIndex = new int[rows];
      session = loadedSession; lineage = loadedLineage; generation = loadedGeneration;
      count = rows; pending = false; pendingRequest = null; loaded = true; lastError = "";
      return "OK|" + count;
    } catch (Throwable error) {
      return fail(error);
    }
  }

  private static void fence(String expectedSession, String expectedLineage, long expectedGeneration) {
    require(loaded, "actors not loaded");
    require(session.equals(expectedSession) && lineage.equals(expectedLineage) &&
        generation == expectedGeneration, "actor fence");
  }

  public static byte[] prepareQuiet(String expectedSession, String expectedLineage,
      long expectedGeneration, String request, double playerX, double playerY,
      int playerMadeSound) {
    try {
      fence(expectedSession, expectedLineage, expectedGeneration);
      require(!pending && request != null && request.matches("[0-9a-f]{32}"), "actor request");
      require(Double.isFinite(playerX) && Double.isFinite(playerY) &&
          (playerMadeSound == 0 || playerMadeSound == 1), "quiet actor input");
      int playerSector = DoomSimCatalogBench.locateSector(playerX, playerY);
      require(playerSector >= 0, "player sector");
      int dirty = 0;
      for (int index = 0; index < count; index++) {
        int rejected = DoomSimCatalogBench.rejected(sector[index], playerSector);
        int soundReach = DoomSimCatalogBench.soundReach(playerSector, sector[index]);
        require(health[index] > 0 && awake[index] == 0 &&
            (healthSeen[index] == -1 || healthSeen[index] == health[index]),
            "unsupported actor action mobj=" + mobjId[index]);
        require(rejected == 1 && (playerMadeSound == 0 || soundReach == 0),
            "actor wake proof mobj=" + mobjId[index]);
        pendingHealthSeen[index] = health[index];
        pendingCooldown[index] = Math.max(0, cooldown[index] - 1);
        if (pendingHealthSeen[index] != healthSeen[index] ||
            pendingCooldown[index] != cooldown[index]) dirtyIndex[dirty++] = index;
      }
      for (int index = 0; index < delta.length; index++) delta[index] = 0;
      putInt(delta, 0, 0x44414354); // DACT
      delta[4] = 1; delta[5] = 0; delta[6] = (byte) dirty;
      for (int item = 0; item < dirty; item++) {
        int actor = dirtyIndex[item], offset = 8 + item * 12;
        putInt(delta, offset, mobjId[actor]);
        putInt(delta, offset + 4, pendingHealthSeen[actor]);
        putInt(delta, offset + 8, pendingCooldown[actor]);
      }
      pending = true; pendingRequest = request; lastError = ""; return delta;
    } catch (Throwable error) {
      fail(error); for (int index = 0; index < 8; index++) delta[index] = 0;
      putInt(delta, 0, 0x44414354); delta[4] = 1; delta[5] = 1; return delta;
    }
  }

  public static String accept(String expectedSession, String expectedLineage,
      long expectedGeneration, String request) {
    try {
      fence(expectedSession, expectedLineage, expectedGeneration);
      require(pending && request != null && request.equals(pendingRequest), "actor pending request");
      for (int index = 0; index < count; index++) {
        healthSeen[index] = pendingHealthSeen[index]; cooldown[index] = pendingCooldown[index];
      }
      pending = false; pendingRequest = null; lastError = ""; return "OK";
    } catch (Throwable error) { return fail(error); }
  }

  public static String discard(String expectedSession, String expectedLineage,
      long expectedGeneration, String request) {
    try {
      fence(expectedSession, expectedLineage, expectedGeneration);
      require(pending && request != null && request.equals(pendingRequest), "actor pending request");
      pending = false; pendingRequest = null; lastError = ""; return "OK";
    } catch (Throwable error) { return fail(error); }
  }

  public static String lastError() {
    try { return lastError; } catch (Throwable error) { return error.getClass().getName(); }
  }
}
