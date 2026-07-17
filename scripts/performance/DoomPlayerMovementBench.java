import oracle.sql.NUMBER;
import java.util.Arrays;

/** First exact retained-array implementation of DOOM_PLAYER_MOVE_PAYLOAD. */
public final class DoomPlayerMovementBench {
  private static final NUMBER ZERO = NUMBER.zero();
  private static final NUMBER ONE = new NUMBER(1);
  private static final NUMBER TWO = new NUMBER(2);
  private static final NUMBER FOUR = new NUMBER(4);
  private static final NUMBER RADIUS = new NUMBER(16);
  private static final double RADIUS_DOUBLE = 16.0;
  private static final double HEIGHT = 56.0;
  private static final double STEP = 24.0;

  private static int contactLine;
  private static NUMBER contactT;
  private static NUMBER contactDirectionX;
  private static NUMBER contactDirectionY;
  static NUMBER resultX;
  static NUMBER resultY;
  static NUMBER resultZ;
  static int resultSector;
  static boolean traceEnabled;
  static long traceCandidateNs,traceSideNs,traceInteriorNs,traceEndpointNs,tracePortalNs;
  static int traceCandidates,traceSideTests,traceInteriorTests,traceEndpointTests;
  private static boolean[] reachableScratch;
  private static boolean[] nextScratch;
  private static int[] candidateLines;
  private static int[] lineSeen;
  private static int candidateGeneration;
  private static int candidateCount;
  private static String lastError = "";

  private DoomPlayerMovementBench() {}

  private static void require(boolean value, String message) {
    if (!value) throw new IllegalStateException(message);
  }

  private static NUMBER integerCoordinate(double value) {
    return new NUMBER((long) value);
  }

  private static boolean blocking(int line, double z) {
    int left = DoomSimCatalogBench.lineLeftSector[line];
    if (left < 0 || (DoomSimCatalogBench.lineFlags[line] & 1) != 0) return true;
    int right = DoomSimCatalogBench.lineRightSector[line];
    double bottom = Math.max(DoomSimCatalogBench.baseFloor[right],
        DoomSimCatalogBench.baseFloor[left]);
    double top = Math.min(DoomSimCatalogBench.baseCeiling[right],
        DoomSimCatalogBench.baseCeiling[left]);
    return bottom - z > STEP || top - bottom < HEIGHT || top - Math.max(z, bottom) < HEIGHT;
  }

  private static int clamp(int value, int minimum, int maximum) {
    return Math.max(minimum, Math.min(maximum, value));
  }

  private static void collectCandidates(double startX, double startY, double endX,
      double endY, double padding) {
    int lineCount = DoomSimCatalogBench.lineId.length;
    if (candidateLines == null || candidateLines.length != lineCount) {
      candidateLines = new int[lineCount]; lineSeen = new int[lineCount]; candidateGeneration = 0;
    }
    if (++candidateGeneration == 0) {
      for (int index = 0; index < lineSeen.length; index++) lineSeen[index] = 0;
      candidateGeneration = 1;
    }
    candidateCount = 0;
    int minBlockX = clamp((int) Math.floor((Math.min(startX, endX) - padding -
        DoomSimCatalogBench.blockOriginX) / 128.0), 0, DoomSimCatalogBench.blockWidth - 1);
    int maxBlockX = clamp((int) Math.floor((Math.max(startX, endX) + padding -
        DoomSimCatalogBench.blockOriginX) / 128.0), 0, DoomSimCatalogBench.blockWidth - 1);
    int minBlockY = clamp((int) Math.floor((Math.min(startY, endY) - padding -
        DoomSimCatalogBench.blockOriginY) / 128.0), 0, DoomSimCatalogBench.blockHeight - 1);
    int maxBlockY = clamp((int) Math.floor((Math.max(startY, endY) + padding -
        DoomSimCatalogBench.blockOriginY) / 128.0), 0, DoomSimCatalogBench.blockHeight - 1);
    for (int blockY = minBlockY; blockY <= maxBlockY; blockY++) {
      for (int blockX = minBlockX; blockX <= maxBlockX; blockX++) {
        int cell = blockY * DoomSimCatalogBench.blockWidth + blockX;
        for (int offset = DoomSimCatalogBench.blockOffset[cell];
             offset < DoomSimCatalogBench.blockOffset[cell + 1]; offset++) {
          int line = DoomSimCatalogBench.blockLines[offset];
          if (lineSeen[line] != candidateGeneration) {
            lineSeen[line] = candidateGeneration; candidateLines[candidateCount++] = line;
          }
        }
      }
    }
  }

  private static void consider(int line, NUMBER t, NUMBER directionX, NUMBER directionY) {
    if (t.compareTo(ZERO) < 0 || t.compareTo(ONE) > 0) return;
    if (contactT == null || t.compareTo(contactT) < 0 ||
        (t.compareTo(contactT) == 0 && DoomSimCatalogBench.lineId[line] < contactLine)) {
      contactLine = DoomSimCatalogBench.lineId[line]; contactT = t;
      contactDirectionX = directionX; contactDirectionY = directionY;
    }
  }

  private static void sweep(NUMBER x, NUMBER y, NUMBER z, NUMBER dx, NUMBER dy,
      int excludedLine) throws Exception {
    contactLine = -1; contactT = null; contactDirectionX = null; contactDirectionY = null;
    double px = x.doubleValue(), py = y.doubleValue(), pz = z.doubleValue();
    double mx = dx.doubleValue(), my = dy.doubleValue();
    double minX = Math.min(px, px + mx) - RADIUS_DOUBLE;
    double maxX = Math.max(px, px + mx) + RADIUS_DOUBLE;
    double minY = Math.min(py, py + my) - RADIUS_DOUBLE;
    double maxY = Math.max(py, py + my) + RADIUS_DOUBLE;
    long phase=traceEnabled?System.nanoTime():0;
    collectCandidates(px, py, px + mx, py + my, RADIUS_DOUBLE);
    if(traceEnabled){traceCandidateNs+=System.nanoTime()-phase;traceCandidates+=candidateCount;}
    for (int candidate = 0; candidate < candidateCount; candidate++) {
      int line = candidateLines[candidate];
      if (DoomSimCatalogBench.lineId[line] == excludedLine || !blocking(line, pz)) continue;
      double x1d = DoomSimCatalogBench.lineX1[line], x2d = DoomSimCatalogBench.lineX2[line];
      double y1d = DoomSimCatalogBench.lineY1[line], y2d = DoomSimCatalogBench.lineY2[line];
      if (Math.min(x1d, x2d) > maxX || Math.max(x1d, x2d) < minX ||
          Math.min(y1d, y2d) > maxY || Math.max(y1d, y2d) < minY) continue;
      phase=traceEnabled?System.nanoTime():0;long interiorBefore=traceInteriorNs;
      NUMBER x1 = integerCoordinate(x1d), y1 = integerCoordinate(y1d);
      NUMBER directionX = DoomSimCatalogBench.lineDirectionXExact[line];
      NUMBER directionY = DoomSimCatalogBench.lineDirectionYExact[line];
      NUMBER normalX = directionY.negate(), normalY = directionX;
      NUMBER distance = x.sub(x1).mul(normalX).add(y.sub(y1).mul(normalY));
      NUMBER velocityNormal = dx.mul(normalX).add(dy.mul(normalY));
      if (!velocityNormal.isZero()) {
        for (int side = -1; side <= 1; side += 2) {
          if(traceEnabled)traceSideTests++;
          NUMBER sideNumber = new NUMBER(side);
          NUMBER t = sideNumber.mul(RADIUS).sub(distance).div(velocityNormal);
          if (t.compareTo(ZERO) < 0 || t.compareTo(ONE) > 0 ||
              sideNumber.mul(velocityNormal).compareTo(ZERO) >= 0) continue;
          NUMBER hitX = x.add(t.mul(dx)), hitY = y.add(t.mul(dy));
          long interior=traceEnabled?System.nanoTime():0;if(traceEnabled)traceInteriorTests++;
          NUMBER along = hitX.sub(x1).mul(directionX).add(hitY.sub(y1).mul(directionY));
          if(traceEnabled)traceInteriorNs+=System.nanoTime()-interior;
          if (along.compareTo(ZERO) >= 0 &&
              along.compareTo(DoomSimCatalogBench.lineLengthExact[line]) <= 0) {
            consider(line, t, directionX, directionY);
          }
        }
      }
      if(traceEnabled)traceSideNs+=System.nanoTime()-phase-(traceInteriorNs-interiorBefore);
      phase=traceEnabled?System.nanoTime():0;
      NUMBER qa = dx.mul(dx).add(dy.mul(dy));
      if (qa.isZero()){if(traceEnabled)traceEndpointNs+=System.nanoTime()-phase;continue;}
      for (int endpoint = 0; endpoint < 2; endpoint++) {
        if(traceEnabled)traceEndpointTests++;
        NUMBER ex = integerCoordinate(endpoint == 0 ? x1d : x2d);
        NUMBER ey = integerCoordinate(endpoint == 0 ? y1d : y2d);
        NUMBER rx = x.sub(ex), ry = y.sub(ey);
        NUMBER qb = TWO.mul(rx.mul(dx).add(ry.mul(dy)));
        NUMBER constant = rx.mul(rx).add(ry.mul(ry)).sub(RADIUS.mul(RADIUS));
        NUMBER discriminant = qb.mul(qb).sub(FOUR.mul(qa).mul(constant));
        if (discriminant.compareTo(ZERO) < 0) continue;
        NUMBER t = qb.negate().sub(discriminant.sqroot()).div(TWO.mul(qa));
        if (t.compareTo(ZERO) < 0 || t.compareTo(ONE) > 0) continue;
        NUMBER hitX = x.add(t.mul(dx)), hitY = y.add(t.mul(dy));
        NUMBER approach = hitX.sub(ex).mul(dx).add(hitY.sub(ey).mul(dy));
        // The rare exact-tangent thin-portal exception is deliberately
        // fail-closed until its dedicated parity corpus lands.
        if (approach.compareTo(ZERO) <= 0) consider(line, t, directionX, directionY);
      }
      if(traceEnabled)traceEndpointNs+=System.nanoTime()-phase;
    }
  }

  private static boolean segmentCrosses(double ax, double ay, double bx, double by,
      double cx, double cy, double dx, double dy) {
    double first = (dx - cx) * (ay - cy) - (dy - cy) * (ax - cx);
    double second = (dx - cx) * (by - cy) - (dy - cy) * (bx - cx);
    double third = (bx - ax) * (cy - ay) - (by - ay) * (cx - ax);
    double fourth = (bx - ax) * (dy - ay) - (by - ay) * (dx - ax);
    return first * second <= 0.0 && third * fourth <= 0.0;
  }

  private static boolean portalTransition(double startX, double startY, double z,
      double endX, double endY, int startSector, int endSector) {
    if (startSector == endSector) return true;
    if (reachableScratch == null || reachableScratch.length != DoomSimCatalogBench.baseFloor.length) {
      reachableScratch = new boolean[DoomSimCatalogBench.baseFloor.length];
      nextScratch = new boolean[DoomSimCatalogBench.baseFloor.length];
    }
    boolean[] reachable = reachableScratch, next = nextScratch;
    for (int index = 0; index < reachable.length; index++) reachable[index] = false;
    reachable[startSector] = true;
    collectCandidates(startX, startY, endX, endY, 0.0);
    for (int hop = 0; hop < 2; hop++) {
      for (int index = 0; index < reachable.length; index++) next[index] = reachable[index];
      for (int candidate = 0; candidate < candidateCount; candidate++) {
        int line = candidateLines[candidate];
        int left = DoomSimCatalogBench.lineLeftSector[line];
        if (left < 0 || (DoomSimCatalogBench.lineFlags[line] & 1) != 0) continue;
        int right = DoomSimCatalogBench.lineRightSector[line];
        double bottom = Math.max(DoomSimCatalogBench.baseFloor[right],
            DoomSimCatalogBench.baseFloor[left]);
        double top = Math.min(DoomSimCatalogBench.baseCeiling[right],
            DoomSimCatalogBench.baseCeiling[left]);
        if (bottom - z > STEP || top - Math.max(z, bottom) < HEIGHT) continue;
        if (!segmentCrosses(startX, startY, endX, endY,
            DoomSimCatalogBench.lineX1[line], DoomSimCatalogBench.lineY1[line],
            DoomSimCatalogBench.lineX2[line], DoomSimCatalogBench.lineY2[line])) continue;
        if (reachable[right]) next[left] = true;
        if (reachable[left]) next[right] = true;
      }
      boolean[] swap = reachable; reachable = next; next = swap;
      if (reachable[endSector]) return true;
    }
    return false;
  }

  private static String moveInternal(NUMBER startX, NUMBER startY, NUMBER startZ, int angleIndex,
      int forward, int strafe, int run, boolean report) {
    try {
      if(traceEnabled){traceCandidateNs=traceSideNs=traceInteriorNs=traceEndpointNs=tracePortalNs=0;
        traceCandidates=traceSideTests=traceInteriorTests=traceEndpointTests=0;}
      require(startX != null && startY != null && startZ != null, "missing position");
      NUMBER deltaX = DoomSimCatalogBench.movementX(angleIndex, forward, strafe, run);
      NUMBER deltaY = DoomSimCatalogBench.movementY(angleIndex, forward, strafe, run);
      require(deltaX != null && deltaY != null, DoomSimCatalogBench.lastError());
      long portal=traceEnabled?System.nanoTime():0;int startSector = DoomSimCatalogBench.locateSector(startX.doubleValue(),startY.doubleValue());
      if(traceEnabled)tracePortalNs+=System.nanoTime()-portal;
      require(startSector >= 0, DoomSimCatalogBench.lastError());
      NUMBER x = startX, y = startY, remainingX = deltaX, remainingY = deltaY;
      int firstLine = -1, secondLine = -1; NUMBER firstT = null, secondT = null;
      sweep(x, y, startZ, remainingX, remainingY, -1);
      if (contactT != null) {
        firstLine = contactLine; firstT = contactT;
        NUMBER directionX = contactDirectionX, directionY = contactDirectionY;
        x = x.add(deltaX.mul(firstT)); y = y.add(deltaY.mul(firstT));
        NUMBER remainder = deltaX.mul(ONE.sub(firstT)).mul(directionX)
            .add(deltaY.mul(ONE.sub(firstT)).mul(directionY));
        remainingX = remainder.mul(directionX); remainingY = remainder.mul(directionY);
        if (!remainingX.isZero() || !remainingY.isZero()) {
          sweep(x, y, startZ, remainingX, remainingY, firstLine);
          if (contactT != null) {
            secondLine = contactLine; secondT = contactT;
            x = x.add(remainingX.mul(secondT)); y = y.add(remainingY.mul(secondT));
          } else {
            x = x.add(remainingX); y = y.add(remainingY);
          }
        }
      } else {
        x = x.add(remainingX); y = y.add(remainingY);
      }
      portal=traceEnabled?System.nanoTime():0;int transitionSector =
          DoomSimCatalogBench.locateSector(x.doubleValue(),y.doubleValue());
      require(transitionSector >= 0, DoomSimCatalogBench.lastError());
      if (!portalTransition(startX.doubleValue(), startY.doubleValue(), startZ.doubleValue(),
          x.doubleValue(), y.doubleValue(), startSector, transitionSector)) {
        x = startX; y = startY;
        firstLine = -1; secondLine = -1; firstT = null; secondT = null;
      }
      // The durable SQL contract uses exact NUMBER BSP tie rules. Keep the
      // established double portal traversal, then canonicalize the final
      // boundary point before encoding the command delta.
      int sector=DoomSimCatalogBench.locateSector(x,y);
      require(sector>=0,DoomSimCatalogBench.lastError());
      if(traceEnabled)tracePortalNs+=System.nanoTime()-portal;
      NUMBER z = new NUMBER((long) DoomSimCatalogBench.baseFloor[sector]);
      resultX = x; resultY = y; resultZ = z; resultSector = sector;
      lastError = "";if (!report) return "OK";
      return "{\"dest_x\":" + x.stringValue() + ",\"dest_y\":" + y.stringValue() +
          ",\"dest_z\":" + z.stringValue() + ",\"destination_sector_id\":" + sector +
          ",\"contact_count\":" + (firstLine < 0 ? 0 : secondLine < 0 ? 1 : 2) +
          ",\"first_blocker_id\":" + (firstLine < 0 ? "null" : Integer.toString(firstLine)) +
          ",\"first_fraction\":" + (firstT == null ? "null" : firstT.stringValue()) +
          ",\"second_blocker_id\":" + (secondLine < 0 ? "null" : Integer.toString(secondLine)) +
          ",\"second_fraction\":" + (secondT == null ? "null" : secondT.stringValue()) + "}";
    } catch (Throwable error) {
      lastError = error.getClass().getName() + ":" + error.getMessage();
      return "{\"error\":\"movement failed\"}";
    }
  }

  public static String move(NUMBER startX, NUMBER startY, NUMBER startZ, int angleIndex,
      int forward, int strafe, int run) {
    return moveInternal(startX,startY,startZ,angleIndex,forward,strafe,run,true);
  }

  /** Allocation-light retained-owner boundary; exact results remain in the package fields. */
  static String moveRetained(NUMBER startX, NUMBER startY, NUMBER startZ, int angleIndex,
      int forward, int strafe, int run) {
    return moveInternal(startX,startY,startZ,angleIndex,forward,strafe,run,false);
  }

  public static String benchmark(int iterations) {
    try {
      require(iterations >= 30 && iterations <= 10000, "benchmark iterations");
      long[] timings = new long[iterations];
      NUMBER x = new NUMBER(-416), y = new NUMBER(256), z = ZERO;
      for (int index = -30; index < iterations; index++) {
        int angle = ((Math.max(index, 0) / 64) * 16) & 63;
        long started = System.nanoTime();
        String payload = move(x, y, z, angle, 1, 0, Math.max(index, 0) % 5 == 0 ? 1 : 0);
        long elapsed = System.nanoTime() - started;
        require(payload.indexOf("\"error\"") < 0, lastError);
        x = resultX; y = resultY; z = resultZ;
        if (index >= 0) timings[index] = elapsed;
      }
      Arrays.sort(timings);
      long p50 = timings[(int) Math.ceil(iterations * 0.50) - 1];
      long p95 = timings[(int) Math.ceil(iterations * 0.95) - 1];
      long maximum = timings[iterations - 1];
      return "OK|" + iterations + "|" + p50 + "|" + p95 + "|" + maximum;
    } catch (Throwable error) {
      lastError = error.getClass().getName() + ":" + error.getMessage();
      return "ERR|" + lastError;
    }
  }

  public static String lastError() {
    try { return lastError; } catch (Throwable error) { return error.getClass().getName(); }
  }
}
