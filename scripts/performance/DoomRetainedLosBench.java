import java.sql.Clob;
import java.util.Arrays;
import oracle.sql.NUMBER;

/** Exact retained-array LOS over the packed BLOCKMAP and live sector heights. */
public final class DoomRetainedLosBench {
  private static final NUMBER ZERO = NUMBER.zero();
  private static final NUMBER ONE = new NUMBER(1);
  private static double[] floor, ceiling;
  private static int[] candidates, seen;
  private static int generation, candidateCount;
  private static boolean loaded;
  private static String lastError = "";

  private DoomRetainedLosBench() {}
  private static void require(boolean value, String message) {
    if (!value) throw new IllegalStateException(message);
  }

  public static String load(Clob snapshot) {
    try {
      require(snapshot != null && snapshot.length() <= 1048576, "LOS snapshot");
      String text = snapshot.getSubString(1, (int) snapshot.length());
      String body = text.substring(1, text.length() - 1).trim();
      int sectors = DoomSimCatalogBench.baseFloor.length;
      double[] newFloor = new double[sectors], newCeiling = new double[sectors];
      if (body.length() > 0) {
        String[] rows = body.split("\\]\\s*,\\s*\\[");
        require(rows.length == sectors, "LOS sector count");
        for (int index = 0; index < rows.length; index++) {
          String row = rows[index].replace("[", "").replace("]", "");
          String[] fields = row.split(",");
          require(fields.length == 3 && Integer.parseInt(fields[0]) == index, "LOS sector order");
          newFloor[index] = Double.parseDouble(fields[1]);
          newCeiling[index] = Double.parseDouble(fields[2]);
          require(Double.isFinite(newFloor[index]) && Double.isFinite(newCeiling[index]) &&
              newCeiling[index] >= newFloor[index], "LOS sector height");
        }
      } else require(sectors == 0, "LOS empty snapshot");
      floor = newFloor; ceiling = newCeiling;
      candidates = new int[DoomSimCatalogBench.lineId.length];
      seen = new int[DoomSimCatalogBench.lineId.length]; generation = 0;
      loaded = true; lastError = ""; return "OK|" + sectors;
    } catch (Throwable error) {
      lastError = error.getClass().getName() + ":" + error.getMessage(); return "ERR|" + lastError;
    }
  }

  private static int clamp(int value, int low, int high) {
    return Math.max(low, Math.min(high, value));
  }

  private static void collect(double x1, double y1, double x2, double y2) {
    if (++generation == 0) {
      for (int index = 0; index < seen.length; index++) seen[index] = 0;
      generation = 1;
    }
    candidateCount = 0;
    int minX = clamp((int) Math.floor((Math.min(x1, x2) -
        DoomSimCatalogBench.blockOriginX) / 128.0) - 1, 0, DoomSimCatalogBench.blockWidth - 1);
    int maxX = clamp((int) Math.floor((Math.max(x1, x2) -
        DoomSimCatalogBench.blockOriginX) / 128.0) + 1, 0, DoomSimCatalogBench.blockWidth - 1);
    int minY = clamp((int) Math.floor((Math.min(y1, y2) -
        DoomSimCatalogBench.blockOriginY) / 128.0) - 1, 0, DoomSimCatalogBench.blockHeight - 1);
    int maxY = clamp((int) Math.floor((Math.max(y1, y2) -
        DoomSimCatalogBench.blockOriginY) / 128.0) + 1, 0, DoomSimCatalogBench.blockHeight - 1);
    for (int blockY = minY; blockY <= maxY; blockY++) {
      for (int blockX = minX; blockX <= maxX; blockX++) {
        int cell = blockY * DoomSimCatalogBench.blockWidth + blockX;
        for (int offset = DoomSimCatalogBench.blockOffset[cell];
             offset < DoomSimCatalogBench.blockOffset[cell + 1]; offset++) {
          int line = DoomSimCatalogBench.blockLines[offset];
          if (seen[line] != generation) {
            seen[line] = generation; candidates[candidateCount++] = line;
          }
        }
      }
    }
  }

  private static NUMBER integer(double value) throws Exception {
    return new NUMBER((long) value);
  }

  private static boolean exactIntersection(int line, NUMBER x, NUMBER y,
      NUMBER targetX, NUMBER targetY) throws Exception {
    double vx = DoomSimCatalogBench.lineX1[line], vy = DoomSimCatalogBench.lineY1[line];
    double ex = DoomSimCatalogBench.lineX2[line], ey = DoomSimCatalogBench.lineY2[line];
    NUMBER lineX = integer(vx), lineY = integer(vy);
    NUMBER sx = integer(ex - vx), sy = integer(ey - vy);
    NUMBER dx = targetX.sub(x), dy = targetY.sub(y);
    NUMBER denominator = dx.mul(sy).sub(dy.mul(sx));
    if (denominator.isZero()) return false;
    NUMBER numerator = lineX.sub(x).mul(sy).sub(lineY.sub(y).mul(sx));
    NUMBER distance = numerator.div(denominator);
    if (distance.compareTo(ZERO) <= 0 || distance.compareTo(ONE) >= 0) return false;
    NUMBER fraction = lineX.sub(x).mul(dy).sub(lineY.sub(y).mul(dx)).div(denominator);
    return fraction.compareTo(ZERO) >= 0 && fraction.compareTo(ONE) <= 0;
  }

  public static int visible(NUMBER x, NUMBER y, int sourceSector,
      NUMBER targetX, NUMBER targetY, int targetSector) {
    try {
      require(loaded && x != null && y != null && targetX != null && targetY != null, "LOS input");
      int rejected = DoomSimCatalogBench.rejected(sourceSector, targetSector);
      require(rejected >= 0, DoomSimCatalogBench.lastError());
      if (rejected == 1) return 0;
      double xd = x.doubleValue(), yd = y.doubleValue();
      double txd = targetX.doubleValue(), tyd = targetY.doubleValue();
      collect(xd, yd, txd, tyd);
      for (int item = 0; item < candidateCount; item++) {
        int line = candidates[item];
        double vx = DoomSimCatalogBench.lineX1[line], vy = DoomSimCatalogBench.lineY1[line];
        double ex = DoomSimCatalogBench.lineX2[line], ey = DoomSimCatalogBench.lineY2[line];
        if (Math.max(vx, ex) < Math.min(xd, txd) || Math.min(vx, ex) > Math.max(xd, txd) ||
            Math.max(vy, ey) < Math.min(yd, tyd) || Math.min(vy, ey) > Math.max(yd, tyd)) continue;
        int left = DoomSimCatalogBench.lineLeftSector[line];
        int right = DoomSimCatalogBench.lineRightSector[line];
        boolean blocking = left < 0 || Math.min(ceiling[right], ceiling[left]) <=
            Math.max(floor[right], floor[left]);
        if (!blocking) continue;
        double sx = ex - vx, sy = ey - vy, dx = txd - xd, dy = tyd - yd;
        double denominator = dx * sy - dy * sx;
        if (Math.abs(denominator) < 1e-9) {
          if (exactIntersection(line, x, y, targetX, targetY)) return 0;
          continue;
        }
        double distance = ((vx - xd) * sy - (vy - yd) * sx) / denominator;
        double fraction = ((vx - xd) * dy - (vy - yd) * dx) / denominator;
        boolean boundary = Math.abs(distance) < 1e-10 || Math.abs(distance - 1.0) < 1e-10 ||
            Math.abs(fraction) < 1e-10 || Math.abs(fraction - 1.0) < 1e-10;
        if (boundary) {
          if (exactIntersection(line, x, y, targetX, targetY)) return 0;
        } else if (distance > 0.0 && distance < 1.0 && fraction > 0.0 && fraction < 1.0) {
          return 0;
        }
      }
      lastError = ""; return 1;
    } catch (Throwable error) {
      lastError = error.getClass().getName() + ":" + error.getMessage(); return -1;
    }
  }

  public static String benchmarkActorBatch(Clob actors, NUMBER targetX, NUMBER targetY,
      int targetSector, int iterations) {
    try {
      require(loaded && actors != null && targetX != null && targetY != null &&
          iterations >= 30 && iterations <= 10000, "LOS benchmark input");
      String text = actors.getSubString(1, (int) actors.length());
      String body = text.substring(1, text.length() - 1).trim();
      String[] rows = body.length() == 0 ? new String[0] : body.split("\\]\\s*,\\s*\\[");
      NUMBER[] x = new NUMBER[rows.length], y = new NUMBER[rows.length];
      int[] sector = new int[rows.length];
      for (int index = 0; index < rows.length; index++) {
        String[] fields = rows[index].replace("[", "").replace("]", "").split(",");
        require(fields.length == 3, "LOS benchmark row");
        x[index] = new NUMBER(fields[0]); y[index] = new NUMBER(fields[1]);
        sector[index] = Integer.parseInt(fields[2]);
      }
      long[] timings = new long[iterations]; int visibleCount = 0;
      for (int sample = -30; sample < iterations; sample++) {
        long started = System.nanoTime(); int visibleThisBatch = 0;
        for (int actor = 0; actor < rows.length; actor++) {
          int result = visible(x[actor], y[actor], sector[actor], targetX, targetY, targetSector);
          require(result >= 0, lastError); visibleThisBatch += result;
        }
        long elapsed = System.nanoTime() - started;
        if (sample >= 0) { timings[sample] = elapsed; visibleCount = visibleThisBatch; }
      }
      Arrays.sort(timings);
      return "OK|" + iterations + "|" + rows.length + "|" +
          (long) rows.length * iterations + "|" + timings[(int) Math.ceil(iterations * .5) - 1] +
          "|" + timings[(int) Math.ceil(iterations * .95) - 1] + "|" +
          timings[iterations - 1] + "|" + visibleCount;
    } catch (Throwable error) {
      lastError = error.getClass().getName() + ":" + error.getMessage(); return "ERR|" + lastError;
    }
  }

  public static String lastError() {
    try { return lastError; } catch (Throwable error) { return error.getClass().getName(); }
  }
}
