import oracle.sql.NUMBER;
import java.util.Arrays;
import java.sql.Clob;
import java.math.BigDecimal;

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
  static boolean resultRequiresWorld;
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
  private static double[] liveFloor,liveCeiling,priorFloor,priorCeiling;
  private static boolean geometryPending;

  private DoomPlayerMovementBench() {}

  private static void require(boolean value, String message) {
    if (!value) throw new IllegalStateException(message);
  }

  private static NUMBER integerCoordinate(double value) {
    return new NUMBER((long) value);
  }
  private static void ensureGeometry(){if(liveFloor==null){liveFloor=DoomSimCatalogBench.baseFloor.clone();
    liveCeiling=DoomSimCatalogBench.baseCeiling.clone();}}
  static String loadDynamicSectors(Clob snapshot){try{String text=snapshot.getSubString(1,(int)snapshot.length());
    String body=text.substring(1,text.length()-1).trim();String[] rows=body.length()==0?new String[0]:
      body.split("\\]\\s*,\\s*\\[");require(rows.length==DoomSimCatalogBench.baseFloor.length,"movement sector count");
    liveFloor=new double[rows.length];liveCeiling=new double[rows.length];for(int i=0;i<rows.length;i++){
      String[] f=rows[i].replace("[","").replace("]","").split(",");require(f.length==3&&
        Integer.parseInt(f[0])==i,"movement sector order");liveFloor[i]=Double.parseDouble(f[1]);
      liveCeiling[i]=Double.parseDouble(f[2]);require(liveCeiling[i]>=liveFloor[i],"movement sector height");}
    geometryPending=false;return "OK|"+rows.length;}catch(Throwable e){return "ERR|"+e.getMessage();}}
  static void stageWorldGeometry(byte[] pack){ensureGeometry();require(!geometryPending&&pack!=null&&
      pack.length>=55&&((pack[6]&255)<<8|(pack[7]&255))==liveFloor.length,"movement geometry pack");
    priorFloor=liveFloor.clone();priorCeiling=liveCeiling.clone();int p=55;
    for(int i=0;i<liveFloor.length;i++,p+=20){require((((pack[p]&255)<<24)|((pack[p+1]&255)<<16)|
      ((pack[p+2]&255)<<8)|(pack[p+3]&255))==i,"movement geometry order");
      liveFloor[i]=((pack[p+4]&255)<<24)|((pack[p+5]&255)<<16)|((pack[p+6]&255)<<8)|(pack[p+7]&255);
      liveCeiling[i]=((pack[p+8]&255)<<24)|((pack[p+9]&255)<<16)|((pack[p+10]&255)<<8)|(pack[p+11]&255);}
    geometryPending=true;}
  static void acceptWorldGeometry(){if(geometryPending)geometryPending=false;}
  static void discardWorldGeometry(){if(geometryPending){liveFloor=priorFloor;liveCeiling=priorCeiling;geometryPending=false;}}

  private static boolean blocking(int line, double z) {
    ensureGeometry();
    int left = DoomSimCatalogBench.lineLeftSector[line];
    if (left < 0 || (DoomSimCatalogBench.lineFlags[line] & 1) != 0) return true;
    int right = DoomSimCatalogBench.lineRightSector[line];
    double bottom = Math.max(liveFloor[right],liveFloor[left]);
    double top = Math.min(liveCeiling[right],liveCeiling[left]);
    return bottom - z > STEP || top - bottom < HEIGHT || top - Math.max(z, bottom) < HEIGHT;
  }

  /** SQL combat/splash blocker: one-sided or dynamically closed geometry only. */
  static double firstBlockingFraction(double x0,double y0,double x1,double y1){
    ensureGeometry();collectCandidates(x0,y0,x1,y1,128.0);
    double dx=x1-x0,dy=y1-y0,best=Double.POSITIVE_INFINITY;
    for(int candidate=0;candidate<candidateCount;candidate++){
      int line=candidateLines[candidate],left=DoomSimCatalogBench.lineLeftSector[line];
      int right=DoomSimCatalogBench.lineRightSector[line];
      if(left>=0&&right>=0&&Math.min(liveCeiling[left],liveCeiling[right])>
          Math.max(liveFloor[left],liveFloor[right]))continue;
      double sx=DoomSimCatalogBench.lineX2[line]-DoomSimCatalogBench.lineX1[line];
      double sy=DoomSimCatalogBench.lineY2[line]-DoomSimCatalogBench.lineY1[line];
      double determinant=dx*sy-dy*sx;if(determinant==0.0)continue;
      double rx=DoomSimCatalogBench.lineX1[line]-x0,ry=DoomSimCatalogBench.lineY1[line]-y0;
      double u=(rx*dy-ry*dx)/determinant,t=(rx*sy-ry*sx)/determinant;
      if(t>0.0&&t<1.0&&u>=0.0&&u<=1.0&&t<best)best=t;
    }
    return best;
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
        ensureGeometry();double bottom = Math.max(liveFloor[right],liveFloor[left]);
        double top = Math.min(liveCeiling[right],liveCeiling[left]);
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
      ensureGeometry();NUMBER z = new NUMBER(BigDecimal.valueOf(liveFloor[sector]));
      resultX = x; resultY = y; resultZ = z; resultSector = sector;
      resultRequiresWorld=DoomSimCatalogBench.sectorWorldEffect[sector]!=0;
      if(!resultRequiresWorld&&(startX.compareTo(x)!=0||startY.compareTo(y)!=0)){
        collectCandidates(startX.doubleValue(),startY.doubleValue(),x.doubleValue(),y.doubleValue(),0.0);
        for(int candidate=0;candidate<candidateCount;candidate++){
          int line=candidateLines[candidate];
          if(DoomSimCatalogBench.lineWalkSpecial[line]!=0&&segmentCrosses(
              startX.doubleValue(),startY.doubleValue(),x.doubleValue(),y.doubleValue(),
              DoomSimCatalogBench.lineX1[line],DoomSimCatalogBench.lineY1[line],
              DoomSimCatalogBench.lineX2[line],DoomSimCatalogBench.lineY2[line])){
            resultRequiresWorld=true;break;
          }
        }
      }
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

  static boolean requiresWorldAdvance(){return resultRequiresWorld;}

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
