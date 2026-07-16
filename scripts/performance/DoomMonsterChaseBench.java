import java.sql.Clob;
import oracle.sql.NUMBER;

/** Retained, exact-coordinate kernel for the movement-only MONSTER CHASE phase. */
public final class DoomMonsterChaseBench {
  private static final NUMBER ZERO = NUMBER.zero();
  private static final NUMBER NEGATIVE_ONE = new NUMBER(-1);
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
  private static NUMBER[] negativeSpeed, xMinus, xPlus, yMinus, yPlus;
  private static byte[][] xCenterField, xMinusField, xPlusField;
  private static byte[][] yCenterField, yMinusField, yPlusField;
  private static double[] xd, yd, zd, radiusDouble, heightDouble, speedDouble;
  private static NUMBER[] floor, ceiling;
  private static double[] floorDouble, ceilingDouble;
  private static NUMBER[] lineX1Exact, lineY1Exact, lineX2Exact, lineY2Exact;
  private static NUMBER[] lineNormalXExact, lineNormalYExact;
  private static int[] candidates, seen;
  private static int candidateGeneration, candidateCount;

  private DoomMonsterChaseBench() {}

  private static void require(boolean value, String message) {
    if (!value) throw new IllegalStateException(message);
  }

  private static boolean hex(String value, int length) {
    if (value == null || value.length() != length) return false;
    for (int index = 0; index < length; index++) {
      char character = value.charAt(index);
      if (!((character >= '0' && character <= '9') ||
          (character >= 'a' && character <= 'f'))) return false;
    }
    return true;
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

  private static byte[] numberField(NUMBER value) {
    byte[] encoded = value.toBytes();
    require(encoded.length >= 1 && encoded.length <= 22, "chase NUMBER length");
    byte[] field = new byte[23]; field[0] = (byte) encoded.length;
    System.arraycopy(encoded, 0, field, 1, encoded.length); return field;
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
      require(hex(loadedSession, 32), "session");
      require(hex(loadedLineage, 64), "lineage");
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
      double[] newFloorDouble = new double[sectorCount],
          newCeilingDouble = new double[sectorCount];
      parser = new Parser(sectorJson); parser.expect('['); int sector = 0;
      if (!parser.take(']')) {
        do {
          parser.expect('['); require(parser.integer() == sector, "chase sector order");
          parser.expect(','); newFloor[sector] = new NUMBER(parser.numberToken());
          parser.expect(','); newCeiling[sector] = new NUMBER(parser.numberToken());
          parser.expect(']');
          require(newCeiling[sector].compareTo(newFloor[sector]) >= 0, "chase sector height");
          newFloorDouble[sector] = newFloor[sector].doubleValue();
          newCeilingDouble[sector] = newCeiling[sector].doubleValue();
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
      double[] newXd = new double[rows], newYd = new double[rows], newZd = new double[rows];
      double[] newRadiusDouble = new double[rows], newHeightDouble = new double[rows],
          newSpeedDouble = new double[rows];
      NUMBER[] newNegativeSpeed = new NUMBER[rows], newXMinus = new NUMBER[rows],
          newXPlus = new NUMBER[rows], newYMinus = new NUMBER[rows], newYPlus = new NUMBER[rows];
      byte[][] newXCenterField = new byte[rows][], newXMinusField = new byte[rows][],
          newXPlusField = new byte[rows][], newYCenterField = new byte[rows][],
          newYMinusField = new byte[rows][], newYPlusField = new byte[rows][];
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
          newXd[row] = newX[row].doubleValue(); newYd[row] = newY[row].doubleValue();
          newZd[row] = newZ[row].doubleValue(); newRadiusDouble[row] = newRadius[row].doubleValue();
          newHeightDouble[row] = newHeight[row].doubleValue();
          newSpeedDouble[row] = newSpeed[row].doubleValue();
          newNegativeSpeed[row] = newSpeed[row].negate();
          newXMinus[row] = newX[row].add(newNegativeSpeed[row]);
          newXPlus[row] = newX[row].add(newSpeed[row]);
          newYMinus[row] = newY[row].add(newNegativeSpeed[row]);
          newYPlus[row] = newY[row].add(newSpeed[row]);
          newXCenterField[row] = numberField(newX[row]);
          newXMinusField[row] = numberField(newXMinus[row]);
          newXPlusField[row] = numberField(newXPlus[row]);
          newYCenterField[row] = numberField(newY[row]);
          newYMinusField[row] = numberField(newYMinus[row]);
          newYPlusField[row] = numberField(newYPlus[row]);
          row++;
        } while (parser.take(',')); parser.expect(']');
      }
      parser.end(); require(row == rows, "chase actor rows");

      session = loadedSession; lineage = loadedLineage; generation = loadedGeneration;
      floor = newFloor; ceiling = newCeiling; floorDouble = newFloorDouble;
      ceilingDouble = newCeilingDouble; count = rows; id = newId; health = newHealth;
      x = newX; y = newY; z = newZ; radius = newRadius; height = newHeight; speed = newSpeed;
      negativeSpeed = newNegativeSpeed; xMinus = newXMinus; xPlus = newXPlus;
      yMinus = newYMinus; yPlus = newYPlus;
      xCenterField = newXCenterField; xMinusField = newXMinusField; xPlusField = newXPlusField;
      yCenterField = newYCenterField; yMinusField = newYMinusField; yPlusField = newYPlusField;
      xd = newXd; yd = newYd; zd = newZd; radiusDouble = newRadiusDouble;
      heightDouble = newHeightDouble; speedDouble = newSpeedDouble;
      candidates = new int[DoomSimCatalogBench.lineId.length];
      seen = new int[DoomSimCatalogBench.lineId.length]; candidateGeneration = 0;
      int lines = DoomSimCatalogBench.lineId.length;
      lineX1Exact = new NUMBER[lines]; lineY1Exact = new NUMBER[lines];
      lineX2Exact = new NUMBER[lines]; lineY2Exact = new NUMBER[lines];
      lineNormalXExact = new NUMBER[lines]; lineNormalYExact = new NUMBER[lines];
      for (int line = 0; line < lines; line++) {
        lineX1Exact[line] = new NUMBER((long) DoomSimCatalogBench.lineX1[line]);
        lineY1Exact[line] = new NUMBER((long) DoomSimCatalogBench.lineY1[line]);
        lineX2Exact[line] = new NUMBER((long) DoomSimCatalogBench.lineX2[line]);
        lineY2Exact[line] = new NUMBER((long) DoomSimCatalogBench.lineY2[line]);
        lineNormalXExact[line] = DoomSimCatalogBench.lineDirectionYExact[line].negate();
        lineNormalYExact[line] = DoomSimCatalogBench.lineDirectionXExact[line];
      }
      loaded = true; lastError = ""; return "OK|" + count;
    } catch (Throwable error) { return fail(error); }
  }

  private static void fence(String expectedSession, String expectedLineage,
      long expectedGeneration, String request) {
    require(loaded && session.equals(expectedSession) && lineage.equals(expectedLineage) &&
        generation == expectedGeneration, "chase fence");
    require(hex(request, 32), "chase request");
  }

  private static int clamp(int value, int low, int high) {
    return Math.max(low, Math.min(high, value));
  }

  private static boolean collect(double sx, double sy, double dxd, double dyd,
      double pad) {
    double ex = sx + dxd, ey = sy + dyd;
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

  private static boolean blocking(int line, NUMBER actorZ, NUMBER actorHeight,
      double actorZd, double actorHeightd) throws Exception {
    int left = DoomSimCatalogBench.lineLeftSector[line];
    if (left < 0 || (DoomSimCatalogBench.lineFlags[line] & 1) != 0) return true;
    int right = DoomSimCatalogBench.lineRightSector[line];
    double bottomDouble = Math.max(floorDouble[right], floorDouble[left]);
    double topDouble = Math.min(ceilingDouble[right], ceilingDouble[left]);
    double stepMargin = bottomDouble - actorZd - 24.0;
    double openingMargin = topDouble - bottomDouble - actorHeightd;
    double headMargin = topDouble - Math.max(actorZd, bottomDouble) - actorHeightd;
    if (Math.abs(stepMargin) > 1e-9 && Math.abs(openingMargin) > 1e-9 &&
        Math.abs(headMargin) > 1e-9)
      return stepMargin > 0.0 || openingMargin < 0.0 || headMargin < 0.0;
    NUMBER bottom = maximum(floor[right], floor[left]);
    NUMBER top = minimum(ceiling[right], ceiling[left]);
    return bottom.sub(actorZ).compareTo(STEP) > 0 ||
        top.sub(bottom).compareTo(actorHeight) < 0 ||
        top.sub(maximum(actorZ, bottom)).compareTo(actorHeight) < 0;
  }

  private static double pointSegmentDistanceSquared(double px, double py, double ax,
      double ay, double bx, double by) {
    double dx = bx - ax, dy = by - ay;
    double length = dx * dx + dy * dy;
    if (length == 0.0) { dx = px - ax; dy = py - ay; return dx * dx + dy * dy; }
    double t = ((px - ax) * dx + (py - ay) * dy) / length;
    if (t <= 0.0) { dx = px - ax; dy = py - ay; }
    else if (t >= 1.0) { dx = px - bx; dy = py - by; }
    else { dx = px - (ax + t * dx); dy = py - (ay + t * dy); }
    return dx * dx + dy * dy;
  }

  private static double orientation(double ax, double ay, double bx, double by,
      double cx, double cy) {
    return (bx - ax) * (cy - ay) - (by - ay) * (cx - ax);
  }

  private static double segmentDistanceSquared(double ax, double ay, double bx, double by,
      double cx, double cy, double dx, double dy) {
    double first = orientation(ax, ay, bx, by, cx, cy);
    double second = orientation(ax, ay, bx, by, dx, dy);
    double third = orientation(cx, cy, dx, dy, ax, ay);
    double fourth = orientation(cx, cy, dx, dy, bx, by);
    if (((first <= 0.0 && second >= 0.0) || (first >= 0.0 && second <= 0.0)) &&
        ((third <= 0.0 && fourth >= 0.0) || (third >= 0.0 && fourth <= 0.0))) return 0.0;
    return Math.min(Math.min(pointSegmentDistanceSquared(ax, ay, cx, cy, dx, dy),
        pointSegmentDistanceSquared(bx, by, cx, cy, dx, dy)),
        Math.min(pointSegmentDistanceSquared(cx, cy, ax, ay, bx, by),
        pointSegmentDistanceSquared(dx, dy, ax, ay, bx, by)));
  }

  // Returns 1 for a decisive contact, 0 for a decisive miss and -1 when an
  // exact NUMBER predicate is required at a body/cap boundary.
  private static int doubleContact(double sx, double sy, double dxd, double dyd,
      double radius, int line) {
    double x1 = DoomSimCatalogBench.lineX1[line], y1 = DoomSimCatalogBench.lineY1[line];
    double x2 = DoomSimCatalogBench.lineX2[line], y2 = DoomSimCatalogBench.lineY2[line];
    double ux = DoomSimCatalogBench.lineDirectionX[line];
    double uy = DoomSimCatalogBench.lineDirectionY[line];
    double length = DoomSimCatalogBench.lineLength[line];
    double nx = -uy, ny = ux;
    double distance = (sx - x1) * nx + (sy - y1) * ny;
    double velocity = dxd * nx + dyd * ny;
    boolean ambiguous = false;
    double epsilon = 1e-9 * (1.0 + Math.abs(distance) + radius + length);
    if (Math.abs(velocity) > epsilon) {
      for (int side = -1; side <= 1; side += 2) {
        double contact = (side * radius - distance) / velocity;
        double approach = side * velocity;
        if (contact < -epsilon || contact > 1.0 + epsilon || approach > epsilon) continue;
        double hitX = sx + contact * dxd, hitY = sy + contact * dyd;
        double along = (hitX - x1) * ux + (hitY - y1) * uy;
        if (along < -epsilon || along > length + epsilon) continue;
        if (contact > epsilon && contact < 1.0 - epsilon && approach < -epsilon &&
            along > epsilon && along < length - epsilon) return 1;
        ambiguous = true;
      }
    } else if (Math.abs(velocity) <= epsilon) {
      // Parallel body roots divide by zero in SQL; caps below still decide.
      if (Math.abs(velocity) > 0.0) ambiguous = true;
    }
    double qa = dxd * dxd + dyd * dyd;
    if (qa != 0.0) {
      for (int endpoint = 0; endpoint < 2; endpoint++) {
        double ex = endpoint == 0 ? x1 : x2, ey = endpoint == 0 ? y1 : y2;
        double rx = sx - ex, ry = sy - ey;
        double qb = 2.0 * (rx * dxd + ry * dyd);
        double discriminant = qb * qb - 4.0 * qa *
            (rx * rx + ry * ry - radius * radius);
        double discEpsilon = 1e-9 * (1.0 + Math.abs(qb * qb) +
            Math.abs(4.0 * qa * (rx * rx + ry * ry - radius * radius)));
        if (discriminant < -discEpsilon) continue;
        if (Math.abs(discriminant) <= discEpsilon) { ambiguous = true; continue; }
        double contact = (-qb - Math.sqrt(discriminant)) / (2.0 * qa);
        if (contact < -epsilon || contact > 1.0 + epsilon) continue;
        double hitX = sx + contact * dxd, hitY = sy + contact * dyd;
        double approach = (hitX - ex) * dxd + (hitY - ey) * dyd;
        if (contact > epsilon && contact < 1.0 - epsilon && approach < -epsilon) return 1;
        if (contact >= -epsilon && contact <= 1.0 + epsilon && approach <= epsilon)
          ambiguous = true;
      }
    }
    return ambiguous ? -1 : 0;
  }

  private static boolean exactContact(NUMBER actorX, NUMBER actorY, NUMBER dx, NUMBER dy,
      NUMBER actorRadius, int line) throws Exception {
    NUMBER x1 = lineX1Exact[line], y1 = lineY1Exact[line];
    NUMBER ux = DoomSimCatalogBench.lineDirectionXExact[line];
    NUMBER uy = DoomSimCatalogBench.lineDirectionYExact[line];
    NUMBER nx = lineNormalXExact[line], ny = lineNormalYExact[line];
    NUMBER distance = actorX.sub(x1).mul(nx).add(actorY.sub(y1).mul(ny));
    NUMBER normalVelocity = dx.mul(nx).add(dy.mul(ny));
    if (!normalVelocity.isZero()) {
      for (int side = -1; side <= 1; side += 2) {
        NUMBER signed = side < 0 ? NEGATIVE_ONE : ONE;
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
    if (qa.isZero()) return false;
    for (int endpoint = 0; endpoint < 2; endpoint++) {
      NUMBER endpointX = endpoint == 0 ? lineX1Exact[line] : lineX2Exact[line];
      NUMBER endpointY = endpoint == 0 ? lineY1Exact[line] : lineY2Exact[line];
      NUMBER rx = actorX.sub(endpointX), ry = actorY.sub(endpointY);
      NUMBER qb = TWO.mul(rx.mul(dx).add(ry.mul(dy)));
      NUMBER constant = rx.mul(rx).add(ry.mul(ry)).sub(actorRadius.mul(actorRadius));
      NUMBER discriminant = qb.mul(qb).sub(FOUR.mul(qa).mul(constant));
      if (discriminant.compareTo(ZERO) < 0) continue;
      NUMBER contact = qb.negate().sub(discriminant.sqroot()).div(TWO.mul(qa));
      if (contact.compareTo(ZERO) < 0 || contact.compareTo(ONE) > 0) continue;
      NUMBER hitX = actorX.add(contact.mul(dx)), hitY = actorY.add(contact.mul(dy));
      NUMBER approach = hitX.sub(endpointX).mul(dx).add(hitY.sub(endpointY).mul(dy));
      if (approach.compareTo(ZERO) <= 0) return true;
    }
    return false;
  }

  private static boolean wallCollision(NUMBER actorX, NUMBER actorY, NUMBER actorZ,
      NUMBER dx, NUMBER dy, NUMBER actorRadius, NUMBER actorHeight,
      double actorXd, double actorYd, double actorZd, double dxd, double dyd,
      double actorRadiusd, double actorHeightd) throws Exception {
    if (!collect(actorXd, actorYd, dxd, dyd, actorRadiusd)) return true;
    double sx = actorXd, sy = actorYd;
    double ex = sx + dxd, ey = sy + dyd, pad = actorRadiusd;
    for (int item = 0; item < candidateCount; item++) {
      int line = candidates[item];
      double x1d = DoomSimCatalogBench.lineX1[line], y1d = DoomSimCatalogBench.lineY1[line];
      double x2d = DoomSimCatalogBench.lineX2[line], y2d = DoomSimCatalogBench.lineY2[line];
      if (Math.min(x1d, x2d) > Math.max(sx, ex) + pad ||
          Math.max(x1d, x2d) < Math.min(sx, ex) - pad ||
          Math.min(y1d, y2d) > Math.max(sy, ey) + pad ||
          Math.max(y1d, y2d) < Math.min(sy, ey) - pad) continue;
      double radiusSquared = pad * pad;
      if (segmentDistanceSquared(sx, sy, ex, ey, x1d, y1d, x2d, y2d) >
          radiusSquared + 1e-6 * (1.0 + radiusSquared)) continue;
      if (!blocking(line, actorZ, actorHeight, actorZd, actorHeightd)) continue;
      int contact = doubleContact(sx, sy, dxd, dyd, actorRadiusd, line);
      if (contact > 0 || (contact < 0 && exactContact(actorX, actorY, dx, dy,
          actorRadius, line))) return true;
    }
    return false;
  }

  private static boolean actorCollision(int actor, NUMBER destinationX,
      NUMBER destinationY, double destinationXd, double destinationYd) throws Exception {
    for (int other = 0; other < count; other++) {
      if (other == actor || health[other] <= 0) continue;
      double dxd = xd[other] - destinationXd, dyd = yd[other] - destinationYd;
      double sumd = radiusDouble[actor] + radiusDouble[other];
      double distanceSquared = dxd * dxd + dyd * dyd, threshold = sumd * sumd;
      double tolerance = 1e-9 * (1.0 + threshold);
      if (distanceSquared < threshold - tolerance) return true;
      if (distanceSquared > threshold + tolerance) continue;
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
        NUMBER destinationX = x[actor], destinationY = y[actor]; int moveDirection = -1;
        int selectedX = 0, selectedY = 0;
        for (int candidate = 0; candidate < 3; candidate++) {
          int candidateX = candidate < 2 ? sx : 0;
          int candidateY = candidate == 1 ? 0 : sy;
          if (candidateX == 0 && candidateY == 0) continue;
          NUMBER dx = candidateX == 0 ? ZERO : candidateX > 0 ? speed[actor] : negativeSpeed[actor];
          NUMBER dy = candidateY == 0 ? ZERO : candidateY > 0 ? speed[actor] : negativeSpeed[actor];
          double dxd = candidateX * speedDouble[actor], dyd = candidateY * speedDouble[actor];
          NUMBER nextX = candidateX < 0 ? xMinus[actor] : candidateX > 0 ? xPlus[actor] : x[actor];
          NUMBER nextY = candidateY < 0 ? yMinus[actor] : candidateY > 0 ? yPlus[actor] : y[actor];
          if (!wallCollision(x[actor], y[actor], z[actor], dx, dy,
                  radius[actor], height[actor], xd[actor], yd[actor], zd[actor], dxd, dyd,
                  radiusDouble[actor], heightDouble[actor]) &&
              !actorCollision(actor, nextX, nextY, xd[actor] + dxd, yd[actor] + dyd)) {
            destinationX = nextX; destinationY = nextY;
            selectedX = candidateX; selectedY = candidateY;
            moveDirection = candidate == 0 ? direction(sx, sy) :
                candidate == 1 ? (sx >= 0 ? 0 : 4) : (sy >= 0 ? 2 : 6);
            break;
          }
        }
        int destinationSector = DoomSimCatalogBench.locateSector(
            destinationX.doubleValue(), destinationY.doubleValue());
        require(destinationSector >= 0, "chase destination sector mobj=" + id[actor]);
        int offset = 8 + actor * RECORD_BYTES;
        putInt(delta, offset, id[actor]);
        System.arraycopy(selectedX < 0 ? xMinusField[actor] : selectedX > 0 ?
            xPlusField[actor] : xCenterField[actor], 0, delta, offset + 4, 23);
        System.arraycopy(selectedY < 0 ? yMinusField[actor] : selectedY > 0 ?
            yPlusField[actor] : yCenterField[actor], 0, delta, offset + 27, 23);
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
