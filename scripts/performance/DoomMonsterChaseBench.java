import java.sql.Clob;
import oracle.sql.NUMBER;

/** Retained, exact-coordinate kernel for the movement-only MONSTER CHASE phase. */
public final class DoomMonsterChaseBench {
  private static final NUMBER ZERO = NUMBER.zero();
  private static final NUMBER ONE = new NUMBER(1);
  private static final NUMBER TWO = new NUMBER(2);
  private static final NUMBER FOUR = new NUMBER(4);
  private static final NUMBER STEP = new NUMBER(24);
  private static final int RECORD_BYTES = 58;
  private static final byte[] delta = new byte[8 + 255 * RECORD_BYTES];

  private static boolean loaded;
  private static String session, lineage, lastError = "";
  private static long generation;
  private static int count;
  private static int[] id, health;
  private static NUMBER[] x, y, z, radius, height, speed;
  private static NUMBER[] floor, ceiling;
  private static int[] candidates, seen;
  private static int candidateGeneration, candidateCount;

  private DoomMonsterChaseBench() {}

  private static void require(boolean value, String message) {
    if (!value) throw new IllegalStateException(message);
  }

  private static final class Parser {
    final String text; int offset;
    Parser(String text) { this.text = text; }
    void whitespace() { while (offset < text.length() && text.charAt(offset) <= ' ') offset++; }
    void expect(char value) {
      whitespace(); require(offset < text.length() && text.charAt(offset++) == value,
          "chase JSON syntax");
    }
    boolean take(char value) {
      whitespace();
      if (offset < text.length() && text.charAt(offset) == value) { offset++; return true; }
      return false;
    }
    String numberToken() {
      whitespace(); int start = offset;
      while (offset < text.length()) {
        char value = text.charAt(offset);
        if ((value >= '0' && value <= '9') || value == '-' || value == '+' || value == '.' ||
            value == 'e' || value == 'E') offset++; else break;
      }
      require(offset > start, "chase JSON number"); return text.substring(start, offset);
    }
    int integer() { return Integer.parseInt(numberToken()); }
    void end() { whitespace(); require(offset == text.length(), "chase JSON trailing bytes"); }
  }

  private static void putInt(byte[] bytes, int offset, int value) {
    bytes[offset] = (byte) (value >>> 24); bytes[offset + 1] = (byte) (value >>> 16);
    bytes[offset + 2] = (byte) (value >>> 8); bytes[offset + 3] = (byte) value;
  }

  private static void putShort(byte[] bytes, int offset, int value) {
    bytes[offset] = (byte) (value >>> 8); bytes[offset + 1] = (byte) value;
  }

  private static void putNumber(byte[] bytes, int offset, NUMBER value) {
    byte[] encoded = value.toBytes();
    require(encoded.length >= 1 && encoded.length <= 22, "chase NUMBER length");
    bytes[offset] = (byte) encoded.length;
    for (int index = 0; index < 22; index++)
      bytes[offset + 1 + index] = index < encoded.length ? encoded[index] : 0;
  }

  private static byte[] failure(Throwable error) {
    lastError = error.getClass().getName() + ":" + error.getMessage();
    byte[] result = new byte[8];
    result[0] = 'D'; result[1] = 'M'; result[2] = 'C'; result[3] = 'H';
    result[4] = 1; result[5] = 1; return result;
  }

  private static String fail(Throwable error) {
    loaded = false; lastError = error.getClass().getName() + ":" + error.getMessage();
    return "ERR|" + lastError;
  }

  public static String load(String loadedSession, String loadedLineage, long loadedGeneration,
      Clob sectorSnapshot, Clob actorSnapshot) {
    try {
      require(loadedSession != null && loadedSession.matches("[0-9a-f]{32}"), "session");
      require(loadedLineage != null && loadedLineage.matches("[0-9a-f]{64}"), "lineage");
      require(loadedGeneration > 0 && sectorSnapshot != null && actorSnapshot != null &&
          sectorSnapshot.length() <= 1048576 && actorSnapshot.length() <= 1048576, "load");

      String sectorJson = sectorSnapshot.getSubString(1, (int) sectorSnapshot.length());
      Parser parser = new Parser(sectorJson); parser.expect('['); int sectorCount = 0;
      if (!parser.take(']')) {
        do {
          parser.expect('['); parser.integer(); parser.expect(','); parser.numberToken();
          parser.expect(','); parser.numberToken(); parser.expect(']'); sectorCount++;
        } while (parser.take(',')); parser.expect(']');
      }
      parser.end();
      require(sectorCount == DoomSimCatalogBench.baseFloor.length, "chase sector count");
      NUMBER[] newFloor = new NUMBER[sectorCount], newCeiling = new NUMBER[sectorCount];
      parser = new Parser(sectorJson); parser.expect('['); int sector = 0;
      if (!parser.take(']')) {
        do {
          parser.expect('['); require(parser.integer() == sector, "chase sector order");
          parser.expect(','); newFloor[sector] = new NUMBER(parser.numberToken());
          parser.expect(','); newCeiling[sector] = new NUMBER(parser.numberToken());
          parser.expect(']');
          require(newCeiling[sector].compareTo(newFloor[sector]) >= 0, "chase sector height");
          sector++;
        } while (parser.take(',')); parser.expect(']');
      }
      parser.end(); require(sector == sectorCount, "chase sector rows");

      String actorJson = actorSnapshot.getSubString(1, (int) actorSnapshot.length());
      parser = new Parser(actorJson); parser.expect('['); int rows = 0;
      if (!parser.take(']')) {
        do {
          parser.expect('[');
          for (int field = 0; field < 8; field++) {
            parser.numberToken(); if (field < 7) parser.expect(',');
          }
          parser.expect(']'); rows++;
        } while (parser.take(',')); parser.expect(']');
      }
      parser.end(); require(rows > 0 && rows <= 255, "chase actor count");
      int[] newId = new int[rows], newHealth = new int[rows];
      NUMBER[] newX = new NUMBER[rows], newY = new NUMBER[rows], newZ = new NUMBER[rows];
      NUMBER[] newRadius = new NUMBER[rows], newHeight = new NUMBER[rows],
          newSpeed = new NUMBER[rows];
      parser = new Parser(actorJson); parser.expect('['); int row = 0;
      if (!parser.take(']')) {
        do {
          parser.expect('['); newId[row] = parser.integer(); parser.expect(',');
          newX[row] = new NUMBER(parser.numberToken()); parser.expect(',');
          newY[row] = new NUMBER(parser.numberToken()); parser.expect(',');
          newZ[row] = new NUMBER(parser.numberToken()); parser.expect(',');
          newRadius[row] = new NUMBER(parser.numberToken()); parser.expect(',');
          newHeight[row] = new NUMBER(parser.numberToken()); parser.expect(',');
          newHealth[row] = parser.integer(); parser.expect(',');
          newSpeed[row] = new NUMBER(parser.numberToken()); parser.expect(']');
          require(newId[row] >= 0 && (row == 0 || newId[row] > newId[row - 1]) &&
              newRadius[row].compareTo(ZERO) > 0 && newHeight[row].compareTo(ZERO) > 0 &&
              newSpeed[row].compareTo(ZERO) >= 0 && newHealth[row] >= 0,
              "chase actor value");
          row++;
        } while (parser.take(',')); parser.expect(']');
      }
      parser.end(); require(row == rows, "chase actor rows");

      session = loadedSession; lineage = loadedLineage; generation = loadedGeneration;
      floor = newFloor; ceiling = newCeiling; count = rows; id = newId; health = newHealth;
      x = newX; y = newY; z = newZ; radius = newRadius; height = newHeight; speed = newSpeed;
      candidates = new int[DoomSimCatalogBench.lineId.length];
      seen = new int[DoomSimCatalogBench.lineId.length]; candidateGeneration = 0;
      loaded = true; lastError = ""; return "OK|" + count;
    } catch (Throwable error) { return fail(error); }
  }

  private static void fence(String expectedSession, String expectedLineage,
      long expectedGeneration, String request) {
    require(loaded && session.equals(expectedSession) && lineage.equals(expectedLineage) &&
        generation == expectedGeneration, "chase fence");
    require(request != null && request.matches("[0-9a-f]{32}"), "chase request");
  }

  private static int clamp(int value, int low, int high) {
    return Math.max(low, Math.min(high, value));
  }

  private static boolean collect(NUMBER startX, NUMBER startY, NUMBER dx, NUMBER dy,
      NUMBER padding) {
    double sx = startX.doubleValue(), sy = startY.doubleValue();
    double ex = sx + dx.doubleValue(), ey = sy + dy.doubleValue(), pad = padding.doubleValue();
    double worldMinX = DoomSimCatalogBench.blockOriginX;
    double worldMinY = DoomSimCatalogBench.blockOriginY;
    double worldMaxX = worldMinX + DoomSimCatalogBench.blockWidth * 128.0;
    double worldMaxY = worldMinY + DoomSimCatalogBench.blockHeight * 128.0;
    // The retained BLOCKMAP is only a safe broad phase inside its represented world.
    if (Math.min(sx, ex) - pad < worldMinX || Math.max(sx, ex) + pad > worldMaxX ||
        Math.min(sy, ey) - pad < worldMinY || Math.max(sy, ey) + pad > worldMaxY) return false;
    if (++candidateGeneration == 0) {
      for (int index = 0; index < seen.length; index++) seen[index] = 0;
      candidateGeneration = 1;
    }
    candidateCount = 0;
    int minX = clamp((int) Math.floor((Math.min(sx, ex) - pad - worldMinX) / 128.0),
        0, DoomSimCatalogBench.blockWidth - 1);
    int maxX = clamp((int) Math.floor((Math.max(sx, ex) + pad - worldMinX) / 128.0),
        0, DoomSimCatalogBench.blockWidth - 1);
    int minY = clamp((int) Math.floor((Math.min(sy, ey) - pad - worldMinY) / 128.0),
        0, DoomSimCatalogBench.blockHeight - 1);
    int maxY = clamp((int) Math.floor((Math.max(sy, ey) + pad - worldMinY) / 128.0),
        0, DoomSimCatalogBench.blockHeight - 1);
    for (int blockY = minY; blockY <= maxY; blockY++) {
      for (int blockX = minX; blockX <= maxX; blockX++) {
        int cell = blockY * DoomSimCatalogBench.blockWidth + blockX;
        for (int offset = DoomSimCatalogBench.blockOffset[cell];
             offset < DoomSimCatalogBench.blockOffset[cell + 1]; offset++) {
          int line = DoomSimCatalogBench.blockLines[offset];
          require(line >= 0 && line < seen.length && DoomSimCatalogBench.lineId[line] == line,
              "chase BLOCKMAP line index");
          if (seen[line] != candidateGeneration) {
            seen[line] = candidateGeneration; candidates[candidateCount++] = line;
          }
        }
      }
    }
    return true;
  }

  private static NUMBER maximum(NUMBER first, NUMBER second) {
    return first.compareTo(second) >= 0 ? first : second;
  }

  private static NUMBER minimum(NUMBER first, NUMBER second) {
    return first.compareTo(second) <= 0 ? first : second;
  }

  private static boolean blocking(int line, NUMBER actorZ, NUMBER actorHeight) throws Exception {
    int left = DoomSimCatalogBench.lineLeftSector[line];
    if (left < 0 || (DoomSimCatalogBench.lineFlags[line] & 1) != 0) return true;
    int right = DoomSimCatalogBench.lineRightSector[line];
    NUMBER bottom = maximum(floor[right], floor[left]);
    NUMBER top = minimum(ceiling[right], ceiling[left]);
    return bottom.sub(actorZ).compareTo(STEP) > 0 ||
        top.sub(bottom).compareTo(actorHeight) < 0 ||
        top.sub(maximum(actorZ, bottom)).compareTo(actorHeight) < 0;
  }

  private static boolean wallCollision(NUMBER actorX, NUMBER actorY, NUMBER actorZ,
      NUMBER dx, NUMBER dy, NUMBER actorRadius, NUMBER actorHeight) throws Exception {
    if (!collect(actorX, actorY, dx, dy, actorRadius)) return true;
    double sx = actorX.doubleValue(), sy = actorY.doubleValue();
    double ex = sx + dx.doubleValue(), ey = sy + dy.doubleValue();
    double pad = actorRadius.doubleValue();
    for (int item = 0; item < candidateCount; item++) {
      int line = candidates[item];
      if (!blocking(line, actorZ, actorHeight)) continue;
      double x1d = DoomSimCatalogBench.lineX1[line], y1d = DoomSimCatalogBench.lineY1[line];
      double x2d = DoomSimCatalogBench.lineX2[line], y2d = DoomSimCatalogBench.lineY2[line];
      if (Math.min(x1d, x2d) > Math.max(sx, ex) + pad ||
          Math.max(x1d, x2d) < Math.min(sx, ex) - pad ||
          Math.min(y1d, y2d) > Math.max(sy, ey) + pad ||
          Math.max(y1d, y2d) < Math.min(sy, ey) - pad) continue;

      NUMBER x1 = new NUMBER((long) x1d), y1 = new NUMBER((long) y1d);
      NUMBER ux = DoomSimCatalogBench.lineDirectionXExact[line];
      NUMBER uy = DoomSimCatalogBench.lineDirectionYExact[line];
      NUMBER nx = uy.negate(), ny = ux;
      NUMBER distance = actorX.sub(x1).mul(nx).add(actorY.sub(y1).mul(ny));
      NUMBER normalVelocity = dx.mul(nx).add(dy.mul(ny));
      if (!normalVelocity.isZero()) {
        for (int side = -1; side <= 1; side += 2) {
          NUMBER signed = new NUMBER(side);
          NUMBER contact = signed.mul(actorRadius).sub(distance).div(normalVelocity);
          if (contact.compareTo(ZERO) < 0 || contact.compareTo(ONE) > 0 ||
              signed.mul(normalVelocity).compareTo(ZERO) >= 0) continue;
          NUMBER hitX = actorX.add(contact.mul(dx)), hitY = actorY.add(contact.mul(dy));
          NUMBER along = hitX.sub(x1).mul(ux).add(hitY.sub(y1).mul(uy));
          if (along.compareTo(ZERO) >= 0 &&
              along.compareTo(DoomSimCatalogBench.lineLengthExact[line]) <= 0) return true;
        }
      }

      NUMBER qa = dx.mul(dx).add(dy.mul(dy));
      if (qa.isZero()) continue;
      for (int endpoint = 0; endpoint < 2; endpoint++) {
        NUMBER endpointX = new NUMBER((long) (endpoint == 0 ? x1d : x2d));
        NUMBER endpointY = new NUMBER((long) (endpoint == 0 ? y1d : y2d));
        NUMBER rx = actorX.sub(endpointX), ry = actorY.sub(endpointY);
        NUMBER qb = TWO.mul(rx.mul(dx).add(ry.mul(dy)));
        NUMBER constant = rx.mul(rx).add(ry.mul(ry)).sub(actorRadius.mul(actorRadius));
        NUMBER discriminant = qb.mul(qb).sub(FOUR.mul(qa).mul(constant));
        if (discriminant.compareTo(ZERO) < 0) continue;
        NUMBER contact = qb.negate().sub(discriminant.sqroot()).div(TWO.mul(qa));
        if (contact.compareTo(ZERO) < 0 || contact.compareTo(ONE) > 0) continue;
        NUMBER hitX = actorX.add(contact.mul(dx)), hitY = actorY.add(contact.mul(dy));
        NUMBER approach = hitX.sub(endpointX).mul(dx).add(hitY.sub(endpointY).mul(dy));
        // Exact tangencies are deliberately blocked; the SQL oracle only opens a
        // reviewed thin-portal exception, so this is the safe catch-all behavior.
        if (approach.compareTo(ZERO) <= 0) return true;
      }
    }
    return false;
  }

  private static boolean actorCollision(int actor, NUMBER destinationX,
      NUMBER destinationY) throws Exception {
    for (int other = 0; other < count; other++) {
      if (other == actor || health[other] <= 0) continue;
      NUMBER dx = x[other].sub(destinationX), dy = y[other].sub(destinationY);
      NUMBER sum = radius[actor].add(radius[other]);
      if (dx.mul(dx).add(dy.mul(dy)).compareTo(sum.mul(sum)) < 0) return true;
    }
    return false;
  }

  private static int direction(int sx, int sy) {
    if (sx == 1 && sy == 0) return 0;
    if (sx == 1 && sy == 1) return 1;
    if (sx == 0 && sy == 1) return 2;
    if (sx == -1 && sy == 1) return 3;
    if (sx == -1 && sy == 0) return 4;
    if (sx == -1 && sy == -1) return 5;
    if (sx == 0 && sy == -1) return 6;
    return 7;
  }

  public static byte[] prepare(String expectedSession, String expectedLineage,
      long expectedGeneration, String request, NUMBER playerX, NUMBER playerY) {
    try {
      fence(expectedSession, expectedLineage, expectedGeneration, request);
      require(playerX != null && playerY != null, "chase player");
      delta[0] = 'D'; delta[1] = 'M'; delta[2] = 'C'; delta[3] = 'H';
      delta[4] = 1; delta[5] = 0; putShort(delta, 6, count);
      for (int actor = 0; actor < count; actor++) {
        require(health[actor] > 0, "dead CHASE actor mobj=" + id[actor]);
        int sx = playerX.compareTo(x[actor]); int sy = playerY.compareTo(y[actor]);
        int[] candidateX = {sx, sx, 0};
        int[] candidateY = {sy, 0, sy};
        int[] candidateDirection = {direction(sx, sy), sx >= 0 ? 0 : 4, sy >= 0 ? 2 : 6};
        NUMBER destinationX = x[actor], destinationY = y[actor]; int moveDirection = -1;
        for (int candidate = 0; candidate < 3; candidate++) {
          if (candidateX[candidate] == 0 && candidateY[candidate] == 0) continue;
          NUMBER dx = speed[actor].mul(new NUMBER(candidateX[candidate]));
          NUMBER dy = speed[actor].mul(new NUMBER(candidateY[candidate]));
          NUMBER nextX = x[actor].add(dx), nextY = y[actor].add(dy);
          if (!wallCollision(x[actor], y[actor], z[actor], dx, dy,
                  radius[actor], height[actor]) && !actorCollision(actor, nextX, nextY)) {
            destinationX = nextX; destinationY = nextY;
            moveDirection = candidateDirection[candidate]; break;
          }
        }
        int destinationSector = DoomSimCatalogBench.locateSector(
            destinationX.doubleValue(), destinationY.doubleValue());
        require(destinationSector >= 0, "chase destination sector mobj=" + id[actor]);
        int offset = 8 + actor * RECORD_BYTES;
        putInt(delta, offset, id[actor]); putNumber(delta, offset + 4, destinationX);
        putNumber(delta, offset + 27, destinationY);
        putInt(delta, offset + 50, destinationSector); putInt(delta, offset + 54, moveDirection);
      }
      byte[] result = new byte[8 + count * RECORD_BYTES];
      System.arraycopy(delta, 0, result, 0, result.length); lastError = ""; return result;
    } catch (Throwable error) { return failure(error); }
  }

  public static String lastError() {
    try { return lastError; } catch (Throwable error) { return error.getClass().getName(); }
  }
}
