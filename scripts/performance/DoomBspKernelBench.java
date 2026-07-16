import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Paths;
import java.sql.Connection;
import java.sql.Blob;
import java.sql.CallableStatement;
import java.sql.DriverManager;
import java.sql.PreparedStatement;
import java.sql.ResultSet;
import java.sql.Statement;
import java.sql.Types;
import java.util.Arrays;

/**
 * Disposable clean-room BSP/projection spike. This is deliberately outside the
 * production call path: SQL remains the independent accepted-hit oracle.
 */
public final class DoomBspKernelBench {
  private static final int WIDTH = 320;
  private static final double NEAR = 1e-9;
  private static final double PAD = 1e-7;

  private static int nodeCount;
  private static int[] nodeX, nodeY, nodeDx, nodeDy;
  private static int[] bboxTop, bboxBottom, bboxLeft, bboxRight;
  private static int[] childId;
  private static byte[] childLeaf;
  private static int ssectorCount;
  private static int[] firstSeg, segCount;
  private static int segTotal;
  private static int[] segStartX, segStartY, segEndX, segEndY;
  private static int[] segLineId, lineStartX, lineStartY, lineEndX, lineEndY;
  private static int[] rightSector, leftSector;
  private static byte[] segSolid;
  private static int[] sectorFloor, sectorCeiling;
  private static double[] camX;
  private static final int ANGLES = 64;
  private static double[] angleDegrees = new double[ANGLES];
  private static double[] directionX = new double[ANGLES];
  private static double[] directionY = new double[ANGLES];
  private static double[] planeX = new double[ANGLES];
  private static double[] planeY = new double[ANGLES];
  private static int[] stackId;
  private static byte[] stackLeaf;
  private static byte[] rawCandidates;
  private static byte[] visibleCandidates;
  private static int[] projectedFirst, projectedLast;
  private static double[] nearestSolidDepth;
  private static int[] columnCounts, columnSegs, orderedSegs;
  private static double[] orderedDepths;
  private static byte[] portalCandidates;
  private static double[] portalClipTop, portalClipBottom;

  private static int visitedNodes;
  private static int visitedSubsectors;
  private static int projectedSegs;
  private static int candidatePairs;
  private static int acceptedPairs;
  private static int visiblePairs;
  private static int activePortalPairs;
  private static volatile long sink;

  private DoomBspKernelBench() {}

  private static void require(boolean condition, String message) {
    if (!condition) throw new IllegalStateException(message);
  }

  private static void load(Connection connection) throws Exception {
    try (Statement statement = connection.createStatement();
         ResultSet rows = statement.executeQuery("select count(*),max(node_id) from doom_map_node")) {
      rows.next();
      nodeCount = rows.getInt(1);
      int max = rows.getInt(2);
      require(nodeCount == max + 1, "node ids are not dense");
    }
    nodeX = new int[nodeCount]; nodeY = new int[nodeCount];
    nodeDx = new int[nodeCount]; nodeDy = new int[nodeCount];
    bboxTop = new int[nodeCount * 2]; bboxBottom = new int[nodeCount * 2];
    bboxLeft = new int[nodeCount * 2]; bboxRight = new int[nodeCount * 2];
    childId = new int[nodeCount * 2]; childLeaf = new byte[nodeCount * 2];
    try (Statement statement = connection.createStatement();
         ResultSet rows = statement.executeQuery(
             "select node_id,x,y,dx,dy,bbox0_top,bbox0_bottom,bbox0_left,bbox0_right," +
             "bbox1_top,bbox1_bottom,bbox1_left,bbox1_right,child0_is_ssector," +
             "child0_id,child1_is_ssector,child1_id from doom_map_node order by node_id")) {
      int expected = 0;
      while (rows.next()) {
        int id = rows.getInt(1);
        require(id == expected++, "node order mismatch");
        nodeX[id] = rows.getInt(2); nodeY[id] = rows.getInt(3);
        nodeDx[id] = rows.getInt(4); nodeDy[id] = rows.getInt(5);
        for (int side = 0; side < 2; side++) {
          int offset = id * 2 + side;
          int base = side == 0 ? 6 : 10;
          bboxTop[offset] = rows.getInt(base);
          bboxBottom[offset] = rows.getInt(base + 1);
          bboxLeft[offset] = rows.getInt(base + 2);
          bboxRight[offset] = rows.getInt(base + 3);
          childLeaf[offset] = (byte) rows.getInt(side == 0 ? 14 : 16);
          childId[offset] = rows.getInt(side == 0 ? 15 : 17);
        }
      }
    }

    try (Statement statement = connection.createStatement();
         ResultSet rows = statement.executeQuery("select count(*),max(ssector_id) from doom_map_ssector")) {
      rows.next();
      ssectorCount = rows.getInt(1);
      require(ssectorCount == rows.getInt(2) + 1, "subsector ids are not dense");
    }
    firstSeg = new int[ssectorCount]; segCount = new int[ssectorCount];
    try (Statement statement = connection.createStatement();
         ResultSet rows = statement.executeQuery(
             "select ssector_id,first_seg_id,seg_count from doom_map_ssector order by ssector_id")) {
      int expected = 0;
      while (rows.next()) {
        int id = rows.getInt(1);
        require(id == expected++, "subsector order mismatch");
        firstSeg[id] = rows.getInt(2); segCount[id] = rows.getInt(3);
      }
    }

    try (Statement statement = connection.createStatement();
         ResultSet rows = statement.executeQuery("select count(*),max(seg_id) from doom_map_seg")) {
      rows.next();
      segTotal = rows.getInt(1);
      require(segTotal == rows.getInt(2) + 1, "seg ids are not dense");
    }
    segStartX = new int[segTotal]; segStartY = new int[segTotal];
    segEndX = new int[segTotal]; segEndY = new int[segTotal];
    segLineId = new int[segTotal];
    lineStartX = new int[segTotal]; lineStartY = new int[segTotal];
    lineEndX = new int[segTotal]; lineEndY = new int[segTotal];
    rightSector = new int[segTotal]; leftSector = new int[segTotal];
    segSolid = new byte[segTotal];
    Arrays.fill(leftSector, -1);
    try (Statement statement = connection.createStatement();
         ResultSet rows = statement.executeQuery(
             "select s.seg_id,a.x,a.y,b.x,b.y,l.linedef_id,la.x,la.y,lb.x,lb.y," +
             "rs.sector_id,ls.sector_id from doom_map_seg s " +
             "join doom_map_linedef l on l.linedef_id=s.linedef_id " +
             "join doom_map_vertex a on a.vertex_id=s.start_vertex_id " +
             "join doom_map_vertex b on b.vertex_id=s.end_vertex_id " +
             "join doom_map_vertex la on la.vertex_id=l.start_vertex_id " +
             "join doom_map_vertex lb on lb.vertex_id=l.end_vertex_id " +
             "join doom_map_sidedef r on r.sidedef_id=l.right_sidedef_id " +
             "join doom_map_sector rs on rs.sector_id=r.sector_id " +
             "left join doom_map_sidedef q on q.sidedef_id=l.left_sidedef_id " +
             "left join doom_map_sector ls on ls.sector_id=q.sector_id order by s.seg_id")) {
      int expected = 0;
      while (rows.next()) {
        int id = rows.getInt(1);
        require(id == expected++, "seg order mismatch");
        segStartX[id] = rows.getInt(2); segStartY[id] = rows.getInt(3);
        segEndX[id] = rows.getInt(4); segEndY[id] = rows.getInt(5);
        segLineId[id] = rows.getInt(6);
        lineStartX[id] = rows.getInt(7); lineStartY[id] = rows.getInt(8);
        lineEndX[id] = rows.getInt(9); lineEndY[id] = rows.getInt(10);
        rightSector[id] = rows.getInt(11);
        int left = rows.getInt(12);
        if (!rows.wasNull()) leftSector[id] = left;
      }
    }
    int sectorCount;
    try (Statement statement = connection.createStatement();
         ResultSet rows = statement.executeQuery("select count(*),max(sector_id) from doom_map_sector")) {
      rows.next();
      sectorCount = rows.getInt(1);
      require(sectorCount == rows.getInt(2) + 1, "sector ids are not dense");
    }
    sectorFloor = new int[sectorCount]; sectorCeiling = new int[sectorCount];
    try (Statement statement = connection.createStatement();
         ResultSet rows = statement.executeQuery(
             "select sector_id,floor_height,ceiling_height from doom_map_sector order by sector_id")) {
      int expected = 0;
      while (rows.next()) {
        int id = rows.getInt(1);
        require(id == expected++, "sector order mismatch");
        sectorFloor[id] = rows.getInt(2); sectorCeiling[id] = rows.getInt(3);
      }
    }
    try (Statement statement = connection.createStatement();
         ResultSet rows = statement.executeQuery(
             "select s.seg_id,case when l.left_sidedef_id is null then 1 " +
             "when least(rs.ceiling_height,ls.ceiling_height)-" +
             "greatest(rs.floor_height,ls.floor_height)<=0 then 1 else 0 end " +
             "from doom_map_seg s join doom_map_linedef l on l.linedef_id=s.linedef_id " +
             "join doom_map_sidedef r on r.sidedef_id=l.right_sidedef_id " +
             "join doom_map_sector rs on rs.sector_id=r.sector_id " +
             "left join doom_map_sidedef q on q.sidedef_id=l.left_sidedef_id " +
             "left join doom_map_sector ls on ls.sector_id=q.sector_id order by s.seg_id")) {
      int expected = 0;
      while (rows.next()) {
        int id = rows.getInt(1);
        require(id == expected++, "seg solidity order mismatch");
        segSolid[id] = (byte) rows.getInt(2);
      }
      require(expected == segTotal, "seg solidity count mismatch");
    }

    camX = new double[WIDTH];
    try (Statement statement = connection.createStatement();
         ResultSet rows = statement.executeQuery(
             "select column_no,cam_x from doom_render_ray where profile_id='CANONICAL_320X200' " +
             "and angle_degrees=0 order by column_no")) {
      int expected = 0;
      while (rows.next()) {
        require(rows.getInt(1) == expected, "ray order mismatch");
        camX[expected++] = rows.getDouble(2);
      }
      require(expected == WIDTH, "canonical profile width mismatch");
    }
    try (Statement statement = connection.createStatement();
         ResultSet rows = statement.executeQuery(
             "select angle_degrees,direction_x,direction_y,plane_x,plane_y from doom_render_ray " +
             "where profile_id='CANONICAL_320X200' and column_no=0 order by angle_degrees")) {
      int expected = 0;
      while (rows.next()) {
        require(expected < ANGLES, "too many angle profiles");
        angleDegrees[expected] = rows.getDouble(1);
        directionX[expected] = rows.getDouble(2); directionY[expected] = rows.getDouble(3);
        planeX[expected] = rows.getDouble(4); planeY[expected] = rows.getDouble(5);
        expected++;
      }
      require(expected == ANGLES, "canonical angle count mismatch");
    }
    stackId = new int[nodeCount * 2 + 4];
    stackLeaf = new byte[stackId.length];
    rawCandidates = new byte[segTotal * WIDTH];
    visibleCandidates = new byte[segTotal * WIDTH];
    portalCandidates = new byte[segTotal * WIDTH];
    projectedFirst = new int[segTotal]; projectedLast = new int[segTotal];
    nearestSolidDepth = new double[WIDTH];
    columnCounts = new int[WIDTH]; columnSegs = new int[WIDTH * segTotal];
    orderedSegs = new int[segTotal]; orderedDepths = new double[segTotal];
    portalClipTop = new double[WIDTH]; portalClipBottom = new double[WIDTH];
  }

  private static int side(int px, int py, int id) {
    int dx = nodeDx[id], dy = nodeDy[id];
    if (dx == 0) return px <= nodeX[id] ? (dy > 0 ? 1 : 0) : (dy < 0 ? 1 : 0);
    if (dy == 0) return py <= nodeY[id] ? (dx < 0 ? 1 : 0) : (dx > 0 ? 1 : 0);
    long cross = (long) (px - nodeX[id]) * dy - (long) (py - nodeY[id]) * dx;
    return cross > 0 ? 0 : 1;
  }

  private static boolean bboxVisible(int offset, int px, int py,
      double dirX, double dirY, double plnX, double plnY, double planeSquared) {
    int left = bboxLeft[offset], right = bboxRight[offset];
    int bottom = bboxBottom[offset], top = bboxTop[offset];
    int front = 0;
    double min = Double.POSITIVE_INFINITY, max = Double.NEGATIVE_INFINITY;
    for (int i = 0; i < 4; i++) {
      double relX = ((i == 0 || i == 3) ? left : right) - px;
      double relY = (i < 2 ? bottom : top) - py;
      double depth = relX * dirX + relY * dirY;
      if (depth > NEAR) {
        front++;
        double projected = (relX * plnX + relY * plnY) / (depth * planeSquared);
        if (projected < min) min = projected;
        if (projected > max) max = projected;
      }
    }
    if (front == 0) return false;
    if (front != 4) return true; // Near-plane crossing: never risk a false reject.
    return max >= camX[0] - PAD && min <= camX[WIDTH - 1] + PAD;
  }

  private static void projectSeg(int id, int px, int py, double dirX, double dirY,
      double plnX, double plnY, double planeSquared, boolean retainCandidates) {
    double ax = segStartX[id] - px, ay = segStartY[id] - py;
    double bx = segEndX[id] - px, by = segEndY[id] - py;
    double ad = ax * dirX + ay * dirY, bd = bx * dirX + by * dirY;
    if (Math.max(ad, bd) <= NEAR) return;
    double ap = ax * plnX + ay * plnY, bp = bx * plnX + by * plnY;
    double ac = ad > NEAR ? ap / (ad * planeSquared)
        : (ap + (NEAR - ad) * (bp - ap) / (bd - ad)) / (NEAR * planeSquared);
    double bc = bd > NEAR ? bp / (bd * planeSquared)
        : (bp + (NEAR - bd) * (ap - bp) / (ad - bd)) / (NEAR * planeSquared);
    double min = Math.min(ac, bc) - PAD, max = Math.max(ac, bc) + PAD;
    if (max < camX[0] || min > camX[WIDTH - 1]) return;
    int first = Arrays.binarySearch(camX, min);
    first = first >= 0 ? first : -first - 1;
    int last = Arrays.binarySearch(camX, max);
    last = last >= 0 ? last : -last - 2;
    if (first < 0) first = 0;
    if (last >= WIDTH) last = WIDTH - 1;
    if (first > last) return;
    projectedSegs++;
    candidatePairs += last - first + 1;
    projectedFirst[id] = first;
    projectedLast[id] = last;
    for (int column = first; column <= last; column++)
      columnSegs[column * segTotal + columnCounts[column]++] = id;
    if (retainCandidates) {
      int base = id * WIDTH;
      Arrays.fill(rawCandidates, base + first, base + last + 1, (byte) 1);
    }
  }

  private static int facingSector(int id, int px, int py) {
    long cross = (long) (px - lineStartX[id]) * (lineEndY[id] - lineStartY[id])
        - (long) (py - lineStartY[id]) * (lineEndX[id] - lineStartX[id]);
    return cross > 0 ? rightSector[id] : leftSector[id];
  }

  private static int oppositeSector(int id, int px, int py) {
    long cross = (long) (px - lineStartX[id]) * (lineEndY[id] - lineStartY[id])
        - (long) (py - lineStartY[id]) * (lineEndX[id] - lineStartX[id]);
    return cross > 0 ? leftSector[id] : rightSector[id];
  }

  private static void applyPortalWalk(int px, int py, double dirX, double dirY,
      double plnX, double plnY, boolean retainCandidates) {
    activePortalPairs = 0;
    if (retainCandidates) Arrays.fill(portalCandidates, (byte) 0);
    for (int column = 0; column < WIDTH; column++) {
      portalClipTop[column] = 0.0; portalClipBottom[column] = 200.0;
      int orderedCount = 0;
      int base = column * segTotal;
      for (int i = 0; i < columnCounts[column]; i++) {
        int id = columnSegs[base + i];
        double depth = acceptedDepth(id, column, px, py, dirX, dirY, plnX, plnY);
        if (Double.isNaN(depth)) continue;
        int at = orderedCount;
        while (at > 0 && (orderedDepths[at - 1] > depth ||
            (orderedDepths[at - 1] == depth &&
             (segLineId[orderedSegs[at - 1]] > segLineId[id] ||
              (segLineId[orderedSegs[at - 1]] == segLineId[id] &&
               orderedSegs[at - 1] > id))))) {
          orderedDepths[at] = orderedDepths[at - 1];
          orderedSegs[at] = orderedSegs[at - 1];
          at--;
        }
        orderedDepths[at] = depth; orderedSegs[at] = id; orderedCount++;
      }
      if (orderedCount == 0) continue;
      int currentSector = facingSector(orderedSegs[0], px, py);
      double eyeZ = sectorFloor[currentSector] + 41.0;
      double clipTop = 0.0, clipBottom = 200.0;
      boolean terminated = false;
      for (int i = 0; i < orderedCount && !terminated; i++) {
        int id = orderedSegs[i];
        int from = facingSector(id, px, py);
        if (from != currentSector) continue;
        activePortalPairs++;
        if (retainCandidates) portalCandidates[id * WIDTH + column] = 1;
        int to = oppositeSector(id, px, py);
        if (to < 0) {
          terminated = true;
        } else {
          int openingTop = Math.min(sectorCeiling[from], sectorCeiling[to]);
          int openingBottom = Math.max(sectorFloor[from], sectorFloor[to]);
          clipTop = Math.max(clipTop,
              100.0 - (openingTop - eyeZ) * 160.0 / orderedDepths[i]);
          clipBottom = Math.min(clipBottom,
              100.0 - (openingBottom - eyeZ) * 160.0 / orderedDepths[i]);
          if (openingTop <= openingBottom) terminated = true;
          else currentSector = to;
        }
      }
      portalClipTop[column] = Math.max(0.0, clipTop);
      portalClipBottom[column] = Math.min(200.0, clipBottom);
    }
  }

  private static double acceptedDepth(int id, int column, int px, int py,
      double dirX, double dirY, double plnX, double plnY) {
    double rayX = dirX + camX[column] * plnX;
    double rayY = dirY + camX[column] * plnY;
    double segX = segEndX[id] - segStartX[id];
    double segY = segEndY[id] - segStartY[id];
    double determinant = rayX * segY - rayY * segX;
    if (Math.abs(determinant) < 1e-12) return Double.NaN;
    double relX = segStartX[id] - px, relY = segStartY[id] - py;
    double hitT = (relX * segY - relY * segX) / determinant;
    if (hitT <= NEAR) return Double.NaN;
    double hitU = (relX * rayY - relY * rayX) / determinant;
    return hitU >= 0.0 && hitU <= 1.0 ? hitT : Double.NaN;
  }

  private static void applySolidCoverage(int px, int py, double dirX, double dirY,
      double plnX, double plnY, boolean retainCandidates) {
    Arrays.fill(nearestSolidDepth, Double.POSITIVE_INFINITY);
    acceptedPairs = 0; visiblePairs = 0;
    if (retainCandidates) Arrays.fill(visibleCandidates, (byte) 0);
    for (int id = 0; id < segTotal; id++) {
      int last = projectedLast[id];
      if (last < 0) continue;
      for (int column = projectedFirst[id]; column <= last; column++) {
        double depth = acceptedDepth(id, column, px, py, dirX, dirY, plnX, plnY);
        if (!Double.isNaN(depth)) {
          acceptedPairs++;
          if (segSolid[id] != 0 && depth < nearestSolidDepth[column])
            nearestSolidDepth[column] = depth;
        }
      }
    }
    for (int id = 0; id < segTotal; id++) {
      int last = projectedLast[id];
      if (last < 0) continue;
      for (int column = projectedFirst[id]; column <= last; column++) {
        double depth = acceptedDepth(id, column, px, py, dirX, dirY, plnX, plnY);
        if (!Double.isNaN(depth) && depth <= nearestSolidDepth[column] + 1e-9) {
          visiblePairs++;
          if (retainCandidates) visibleCandidates[id * WIDTH + column] = 1;
        }
      }
    }
  }

  private static int traverseAndProject(int px, int py, int angle, boolean retainCandidates) {
    visitedNodes = 0; visitedSubsectors = 0; projectedSegs = 0; candidatePairs = 0;
    Arrays.fill(projectedLast, -1);
    Arrays.fill(columnCounts, 0);
    if (retainCandidates) Arrays.fill(rawCandidates, (byte) 0);
    double dirX = directionX[angle], dirY = directionY[angle];
    double plnX = planeX[angle], plnY = planeY[angle];
    double planeSquared = plnX * plnX + plnY * plnY;
    int top = 0;
    stackId[top] = nodeCount - 1; stackLeaf[top++] = 0;
    while (top != 0) {
      --top;
      int id = stackId[top];
      if (stackLeaf[top] != 0) {
        visitedSubsectors++;
        int end = firstSeg[id] + segCount[id];
        for (int seg = firstSeg[id]; seg < end; seg++)
          projectSeg(seg, px, py, dirX, dirY, plnX, plnY, planeSquared, retainCandidates);
        continue;
      }
      visitedNodes++;
      int near = side(px, py, id), far = near ^ 1;
      int farOffset = id * 2 + far;
      if (bboxVisible(farOffset, px, py, dirX, dirY, plnX, plnY, planeSquared)) {
        stackId[top] = childId[farOffset]; stackLeaf[top++] = childLeaf[farOffset];
      }
      int nearOffset = id * 2 + near;
      if (bboxVisible(nearOffset, px, py, dirX, dirY, plnX, plnY, planeSquared)) {
        stackId[top] = childId[nearOffset]; stackLeaf[top++] = childLeaf[nearOffset];
      }
    }
    applySolidCoverage(px, py, dirX, dirY, plnX, plnY, retainCandidates);
    applyPortalWalk(px, py, dirX, dirY, plnX, plnY, retainCandidates);
    sink += activePortalPairs + visiblePairs + candidatePairs + visitedNodes;
    return activePortalPairs;
  }

  private static int[] sqlOracle(Connection connection, int px, int py, int angleProfile) throws Exception {
    String sql =
        "select s.seg_id,r.column_no,case when l.left_sidedef_id is null then 1 " +
        "when least(rs.ceiling_height,ls.ceiling_height)-" +
        "greatest(rs.floor_height,ls.floor_height)<=0 then 1 else 0 end is_solid from doom_map_seg s " +
        "join doom_map_linedef l on l.linedef_id=s.linedef_id " +
        "join doom_map_sidedef sd on sd.sidedef_id=l.right_sidedef_id " +
        "join doom_map_sector rs on rs.sector_id=sd.sector_id " +
        "left join doom_map_sidedef osd on osd.sidedef_id=l.left_sidedef_id " +
        "left join doom_map_sector ls on ls.sector_id=osd.sector_id " +
        "join doom_map_vertex a on a.vertex_id=s.start_vertex_id " +
        "join doom_map_vertex b on b.vertex_id=s.end_vertex_id " +
        "cross join doom_render_ray r where r.profile_id='CANONICAL_320X200' " +
        "and r.angle_degrees=? and abs(r.ray_x*(b.y-a.y)-r.ray_y*(b.x-a.x))>=1e-12 " +
        "and ((a.x-?)*(b.y-a.y)-(a.y-?)*(b.x-a.x))/" +
        "nullif(r.ray_x*(b.y-a.y)-r.ray_y*(b.x-a.x),0)>1e-9 " +
        "and ((a.x-?)*r.ray_y-(a.y-?)*r.ray_x)/" +
        "nullif(r.ray_x*(b.y-a.y)-r.ray_y*(b.x-a.x),0) between 0 and 1 " +
        "order by r.column_no,((a.x-?)*(b.y-a.y)-(a.y-?)*(b.x-a.x))/" +
        "nullif(r.ray_x*(b.y-a.y)-r.ray_y*(b.x-a.x),0),l.linedef_id,s.seg_id";
    int accepted = 0, missing = 0, visible = 0, visibleMissing = 0;
    try (PreparedStatement statement = connection.prepareStatement(sql)) {
      statement.setDouble(1, angleDegrees[angleProfile]);
      statement.setInt(2, px); statement.setInt(3, py);
      statement.setInt(4, px); statement.setInt(5, py);
      statement.setInt(6, px); statement.setInt(7, py);
      try (ResultSet rows = statement.executeQuery()) {
        int priorColumn = -1;
        boolean blocked = false;
        while (rows.next()) {
          accepted++;
          int column = rows.getInt(2);
          if (column != priorColumn) { priorColumn = column; blocked = false; }
          int index = rows.getInt(1) * WIDTH + column;
          if (rawCandidates[index] == 0) missing++;
          if (!blocked) {
            visible++;
            if (visibleCandidates[index] == 0) visibleMissing++;
            if (rows.getInt(3) != 0) blocked = true;
          }
        }
      }
    }
    return new int[] {accepted, missing, visible, visibleMissing};
  }

  private static int[] productionPortalOracle(Connection connection, int px, int py)
      throws Exception {
    String session = null;
    byte[] oracleActive = new byte[segTotal * WIDTH];
    int sqlActive = 0, missing = 0, extra = 0, clipMismatch = 0;
    try {
      try (CallableStatement call = connection.prepareCall("{call doom_api.new_game(?,?,?)}")) {
        call.setInt(1, 3);
        call.registerOutParameter(2, Types.VARCHAR);
        call.registerOutParameter(3, Types.BLOB);
        call.execute();
        session = call.getString(2);
        Blob payload = call.getBlob(3);
        if (payload != null) payload.free();
      }
      connection.setAutoCommit(false);
      try (PreparedStatement update = connection.prepareStatement(
               "update players set angle=? where session_token=? and player_id=0");
           Statement staging = connection.createStatement();
           PreparedStatement oracle = connection.prepareStatement(
               "select seg_id,column_no from doom_r2_staged_portal_hit_rows " +
               "where session_token=? and is_active=1");
           PreparedStatement clipOracle = connection.prepareStatement(
               "select h.column_no,greatest(0,coalesce(max(100-(h.opening_top-" +
               "(p.z+p.view_height+p.view_bob))*160/h.hit_t),0))," +
               "least(200,coalesce(min(100-(h.opening_bottom-" +
               "(p.z+p.view_height+p.view_bob))*160/h.hit_t),200)) " +
               "from doom_r2_staged_portal_hit_rows h join players p " +
               "on p.session_token=h.session_token and p.player_id=0 " +
               "where h.session_token=? and h.is_active=1 group by h.column_no")) {
        for (int pose = 0; pose < 12; pose++) {
          int angle = pose * 5;
          update.setDouble(1, angleDegrees[angle]); update.setString(2, session);
          require(update.executeUpdate() == 1, "portal oracle player update failed");
          staging.executeUpdate("delete from frame_render_seg_bound");
          staging.executeUpdate("insert into frame_render_seg_bound select * " +
              "from doom_r1_staged_segment_bound_rows where session_token='" + session + "'");
          staging.executeUpdate("delete from frame_r1_hit");
          staging.executeUpdate("insert into frame_r1_hit select * " +
              "from doom_r1_staged_hit_rows where session_token='" + session + "'");
          traverseAndProject(px, py, angle, true);
          Arrays.fill(oracleActive, (byte) 0);
          oracle.setString(1, session);
          int poseSql = 0;
          try (ResultSet rows = oracle.executeQuery()) {
            while (rows.next()) {
              poseSql++;
              int index = rows.getInt(1) * WIDTH + rows.getInt(2);
              oracleActive[index] = 1;
              if (portalCandidates[index] == 0) missing++;
            }
          }
          sqlActive += poseSql;
          for (int index = 0; index < portalCandidates.length; index++)
            if (portalCandidates[index] != 0 && oracleActive[index] == 0) extra++;
          clipOracle.setString(1, session);
          try (ResultSet rows = clipOracle.executeQuery()) {
            while (rows.next()) {
              int column = rows.getInt(1);
              if (Math.abs(rows.getDouble(2) - portalClipTop[column]) > 1e-8 ||
                  Math.abs(rows.getDouble(3) - portalClipBottom[column]) > 1e-8)
                clipMismatch++;
            }
          }
        }
      }
      connection.rollback();
    } finally {
      if (session != null) {
        connection.rollback();
        connection.setAutoCommit(true);
        try (PreparedStatement cleanup = connection.prepareStatement(
            "delete from game_sessions where session_token=?")) {
          cleanup.setString(1, session); cleanup.executeUpdate();
        }
      }
    }
    return new int[] {sqlActive, missing, extra, clipMismatch};
  }

  private static double percentile(long[] sorted, double quantile) {
    int index = (int) Math.ceil(sorted.length * quantile) - 1;
    return sorted[Math.max(0, index)] / 1_000_000.0;
  }

  public static void main(String[] args) throws Exception {
    require(args.length == 1, "usage: DoomBspKernelBench PASSWORD_FILE");
    String password = new String(Files.readAllBytes(Paths.get(args[0])), StandardCharsets.UTF_8).trim();
    long loadStart = System.nanoTime();
    try (Connection connection = DriverManager.getConnection(
        "jdbc:oracle:thin:@127.0.0.1:1521/FREEPDB1", "DOOM", password)) {
      password = null;
      load(connection);
      double loadMs = (System.nanoTime() - loadStart) / 1_000_000.0;
      int px = -416, py = 256;
      int auditAccepted = 0, auditMissing = 0, auditCandidates = 0;
      int auditVisible = 0, auditVisibleMissing = 0, auditVisibleCandidates = 0;
      int maxNodes = 0, maxSubsectors = 0;
      for (int pose = 0; pose < 12; pose++) {
        int angle = pose * 5;
        traverseAndProject(px, py, angle, true);
        int[] oracle = sqlOracle(connection, px, py, angle);
        auditAccepted += oracle[0]; auditMissing += oracle[1];
        auditVisible += oracle[2]; auditVisibleMissing += oracle[3];
        auditCandidates += candidatePairs;
        auditVisibleCandidates += visiblePairs;
        maxNodes = Math.max(maxNodes, visitedNodes);
        maxSubsectors = Math.max(maxSubsectors, visitedSubsectors);
      }
      require(auditMissing == 0, "BSP/projection omitted SQL-accepted pairs: " + auditMissing);
      require(auditVisibleMissing == 0,
          "solid coverage omitted SQL-visible pairs: " + auditVisibleMissing);
      int[] portalOracle = productionPortalOracle(connection, px, py);
      require(portalOracle[1] == 0 && portalOracle[2] == 0 && portalOracle[3] == 0,
          "portal walk differs from production SQL: missing=" + portalOracle[1] +
          " extra=" + portalOracle[2] + " clip_mismatch=" + portalOracle[3]);

      for (int i = 0; i < 5000; i++)
        traverseAndProject(px + (i % 7) - 3, py + (i % 11) - 5, i % ANGLES, false);
      int sampleCount = 20000;
      long[] samples = new long[sampleCount];
      for (int i = 0; i < sampleCount; i++) {
        long start = System.nanoTime();
        traverseAndProject(px + (i % 7) - 3, py + (i % 11) - 5, i % ANGLES, false);
        samples[i] = System.nanoTime() - start;
      }
      Arrays.sort(samples);
      double retention = auditCandidates / (12.0 * segTotal * WIDTH);
      double visibleRetention = auditVisibleCandidates / (12.0 * segTotal * WIDTH);
      double p95 = percentile(samples, .95);
      require(p95 <= 3.0, "BSP/projection p95 gate failed: " + p95 + " ms");
      require(retention <= .25, "candidate retention gate failed: " + retention);
      System.out.printf(java.util.Locale.ROOT,
          "BSP_KERNEL load_ms=%.3f p50_ms=%.6f p95_ms=%.6f p99_ms=%.6f " +
          "audit_poses=12 sql_accepted=%d missing=%d candidate_retention=%.6f " +
          "sql_visible=%d visible_missing=%d visible_retention=%.6f " +
          "sql_portal_active=%d portal_missing=%d portal_extra=%d clip_mismatch=%d " +
          "max_nodes=%d max_ssectors=%d sink=%d%n",
          loadMs, percentile(samples, .50), p95, percentile(samples, .99),
          auditAccepted, auditMissing, retention, auditVisible, auditVisibleMissing,
          visibleRetention, portalOracle[0], portalOracle[1], portalOracle[2], portalOracle[3],
          maxNodes, maxSubsectors, sink);
    }
  }
}
