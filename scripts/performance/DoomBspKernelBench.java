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
import java.util.HashMap;
import java.util.Map;

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
  private static int[] lineFlags, segOffset, rightXOffset, rightYOffset;
  private static int[] leftXOffset, leftYOffset;
  private static String[] rightUpper, rightLower, rightMiddle;
  private static String[] leftUpper, leftLower, leftMiddle;
  private static byte[] segSolid;
  private static int[] sectorFloor, sectorCeiling;
  private static int[] sectorLight;
  private static String[] sectorCeilingFlat, sectorFloorFlat;
  private static Map<String, Integer> wallAssetByName;
  private static int[] wallAssetWidth, wallAssetHeight;
  private static short[][] wallAssetTexels;
  private static Map<String, Integer> flatAssetByName;
  private static short[][] flatAssetTexels;
  private static short[] colormap;
  private static double[] camX;
  private static final int ANGLES = 64;
  private static double[] angleDegrees = new double[ANGLES];
  private static double[] directionX = new double[ANGLES];
  private static double[] directionY = new double[ANGLES];
  private static double[] planeX = new double[ANGLES];
  private static double[] planeY = new double[ANGLES];
  private static double[] rayXProfile = new double[ANGLES * WIDTH];
  private static double[] rayYProfile = new double[ANGLES * WIDTH];
  private static int activeAngle;
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
  private static short[] wallFrame;
  private static byte[] wallOwned;
  private static byte[] wallColored;
  private static final int MAX_INTERVALS = 32768;
  private static int[] intervalOffset, intervalCount, intervalSector;
  private static double[] intervalStart, intervalEnd, intervalClipTop, intervalClipBottom;
  private static int intervalTotal;
  private static double farDistance;
  private static double projectionK;
  private static short[] presentationFrame, overlayPalette;
  private static double[] overlayDepth;
  private static byte[] overlayKind;
  private static int[] overlaySource, overlayAssetX, overlayAssetY;
  private static Map<Integer, Integer> spriteAssetById;
  private static int[] spriteAssetWidth, spriteAssetHeight;
  private static short[][] spriteAssetTexels;
  private static int catalogStateCount;
  private static Map<String, Integer> stateIndexByName;
  private static int[] catalogAsset, catalogLeft, catalogTop;
  private static byte[] catalogFlip, catalogPresent;
  private static int mobjCount;
  private static int[] mobjId, mobjX, mobjY, mobjZ, mobjAngle, mobjState;

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
    lineFlags = new int[segTotal]; segOffset = new int[segTotal];
    rightXOffset = new int[segTotal]; rightYOffset = new int[segTotal];
    leftXOffset = new int[segTotal]; leftYOffset = new int[segTotal];
    rightUpper = new String[segTotal]; rightLower = new String[segTotal];
    rightMiddle = new String[segTotal]; leftUpper = new String[segTotal];
    leftLower = new String[segTotal]; leftMiddle = new String[segTotal];
    segSolid = new byte[segTotal];
    Arrays.fill(leftSector, -1);
    try (Statement statement = connection.createStatement();
         ResultSet rows = statement.executeQuery(
             "select s.seg_id,a.x,a.y,b.x,b.y,l.linedef_id,la.x,la.y,lb.x,lb.y," +
             "rs.sector_id,ls.sector_id,l.flags,s.offset," +
             "r.x_offset,r.y_offset,r.upper_texture,r.lower_texture,r.middle_texture," +
             "q.x_offset,q.y_offset,q.upper_texture,q.lower_texture,q.middle_texture " +
             "from doom_map_seg s " +
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
        lineFlags[id] = rows.getInt(13); segOffset[id] = rows.getInt(14);
        rightXOffset[id] = rows.getInt(15); rightYOffset[id] = rows.getInt(16);
        rightUpper[id] = rows.getString(17); rightLower[id] = rows.getString(18);
        rightMiddle[id] = rows.getString(19);
        leftXOffset[id] = rows.getInt(20); leftYOffset[id] = rows.getInt(21);
        leftUpper[id] = rows.getString(22); leftLower[id] = rows.getString(23);
        leftMiddle[id] = rows.getString(24);
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
    sectorLight = new int[sectorCount]; sectorCeilingFlat = new String[sectorCount];
    sectorFloorFlat = new String[sectorCount];
    try (Statement statement = connection.createStatement();
         ResultSet rows = statement.executeQuery(
             "select sector_id,floor_height,ceiling_height,light_level,ceiling_flat,floor_flat " +
             "from doom_map_sector order by sector_id")) {
      int expected = 0;
      while (rows.next()) {
        int id = rows.getInt(1);
        require(id == expected++, "sector order mismatch");
        sectorFloor[id] = rows.getInt(2); sectorCeiling[id] = rows.getInt(3);
        sectorLight[id] = rows.getInt(4); sectorCeilingFlat[id] = rows.getString(5);
        sectorFloorFlat[id] = rows.getString(6);
      }
    }
    try (Statement statement = connection.createStatement();
         ResultSet rows = statement.executeQuery(
             "select number_value from doom_config where config_key='FAR_DISTANCE'")) {
      rows.next(); farDistance = rows.getDouble(1);
    }
    try (Statement statement = connection.createStatement();
         ResultSet rows = statement.executeQuery(
             "select cast(320 as binary_double)/2/tan(cast(90 as binary_double)*" +
             "cast(acos(-1) as binary_double)/360) from dual")) {
      rows.next(); projectionK = rows.getDouble(1);
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
    int wallAssetCount;
    try (Statement statement = connection.createStatement();
         ResultSet rows = statement.executeQuery(
             "select count(*) from doom_asset where asset_kind='wall_texture'")) {
      rows.next(); wallAssetCount = rows.getInt(1);
    }
    wallAssetByName = new HashMap<>();
    wallAssetWidth = new int[wallAssetCount]; wallAssetHeight = new int[wallAssetCount];
    wallAssetTexels = new short[wallAssetCount][];
    Map<Integer, Integer> wallAssetById = new HashMap<>();
    try (Statement statement = connection.createStatement();
         ResultSet rows = statement.executeQuery(
             "select asset_id,asset_name,width,height from doom_asset " +
             "where asset_kind='wall_texture' order by asset_id")) {
      int index = 0;
      while (rows.next()) {
        wallAssetById.put(rows.getInt(1), index);
        wallAssetByName.put(rows.getString(2), index);
        wallAssetWidth[index] = rows.getInt(3); wallAssetHeight[index] = rows.getInt(4);
        wallAssetTexels[index] = new short[wallAssetWidth[index] * wallAssetHeight[index]];
        index++;
      }
      require(index == wallAssetCount, "wall asset count mismatch");
    }
    try (Statement statement = connection.createStatement();
         ResultSet rows = statement.executeQuery(
             "select t.a,t.x,t.y,t.c from at t join doom_asset a on a.asset_id=t.a " +
             "where a.asset_kind='wall_texture' order by t.a,t.x,t.y")) {
      int texels = 0;
      while (rows.next()) {
        int asset = wallAssetById.get(rows.getInt(1));
        int offset = rows.getInt(2) * wallAssetHeight[asset] + rows.getInt(3);
        wallAssetTexels[asset][offset] = (short) rows.getInt(4); texels++;
      }
      require(texels == 1_256_192, "wall texel count mismatch");
    }
    int flatAssetCount;
    try (Statement statement = connection.createStatement();
         ResultSet rows = statement.executeQuery(
             "select count(*) from doom_asset where asset_kind='flat'")) {
      rows.next(); flatAssetCount = rows.getInt(1);
    }
    flatAssetByName = new HashMap<>(); flatAssetTexels = new short[flatAssetCount][];
    Map<Integer, Integer> flatAssetById = new HashMap<>();
    try (Statement statement = connection.createStatement();
         ResultSet rows = statement.executeQuery(
             "select asset_id,asset_name,width,height from doom_asset " +
             "where asset_kind='flat' order by asset_id")) {
      int index = 0;
      while (rows.next()) {
        require(rows.getInt(3) == 64 && rows.getInt(4) == 64, "flat dimensions mismatch");
        flatAssetById.put(rows.getInt(1), index);
        flatAssetByName.put(rows.getString(2), index);
        flatAssetTexels[index] = new short[4096]; index++;
      }
      require(index == flatAssetCount, "flat asset count mismatch");
    }
    try (Statement statement = connection.createStatement();
         ResultSet rows = statement.executeQuery(
             "select t.a,t.x,t.y,t.c from at t join doom_asset a on a.asset_id=t.a " +
             "where a.asset_kind='flat' order by t.a,t.x,t.y")) {
      int texels = 0;
      while (rows.next()) {
        int asset = flatAssetById.get(rows.getInt(1));
        flatAssetTexels[asset][rows.getInt(2) * 64 + rows.getInt(3)] =
            (short) rows.getInt(4); texels++;
      }
      require(texels == 200_704, "flat texel count mismatch");
    }
    int spriteAssetCount;
    try (Statement statement = connection.createStatement();
         ResultSet rows = statement.executeQuery(
             "select count(*) from doom_asset where asset_kind='sprite_patch'")) {
      rows.next(); spriteAssetCount = rows.getInt(1);
    }
    spriteAssetById = new HashMap<>();
    spriteAssetWidth = new int[spriteAssetCount]; spriteAssetHeight = new int[spriteAssetCount];
    spriteAssetTexels = new short[spriteAssetCount][];
    try (Statement statement = connection.createStatement();
         ResultSet rows = statement.executeQuery(
             "select asset_id,width,height from doom_asset where asset_kind='sprite_patch' " +
             "order by asset_id")) {
      int index = 0;
      while (rows.next()) {
        spriteAssetById.put(rows.getInt(1), index);
        spriteAssetWidth[index] = rows.getInt(2); spriteAssetHeight[index] = rows.getInt(3);
        spriteAssetTexels[index] = new short[spriteAssetWidth[index] * spriteAssetHeight[index]];
        index++;
      }
      require(index == spriteAssetCount, "sprite asset count mismatch");
    }
    try (Statement statement = connection.createStatement();
         ResultSet rows = statement.executeQuery(
             "select t.a,t.x,t.y,t.c from at t join doom_asset a on a.asset_id=t.a " +
             "where a.asset_kind='sprite_patch' order by t.a,t.x,t.y")) {
      int texels = 0;
      while (rows.next()) {
        int asset = spriteAssetById.get(rows.getInt(1));
        int offset = rows.getInt(2) * spriteAssetHeight[asset] + rows.getInt(3);
        spriteAssetTexels[asset][offset] = (short) rows.getInt(4); texels++;
      }
      require(texels == 331_474, "sprite texel count mismatch");
    }
    stateIndexByName = new HashMap<>();
    try (Statement statement = connection.createStatement();
         ResultSet rows = statement.executeQuery("select state_id from doom_state_def order by state_id")) {
      while (rows.next()) stateIndexByName.put(rows.getString(1), stateIndexByName.size());
      catalogStateCount = stateIndexByName.size();
    }
    int catalogSize = catalogStateCount * 9;
    catalogAsset = new int[catalogSize]; catalogLeft = new int[catalogSize];
    catalogTop = new int[catalogSize]; catalogFlip = new byte[catalogSize];
    catalogPresent = new byte[catalogSize];
    try (Statement statement = connection.createStatement();
         ResultSet rows = statement.executeQuery(
             "select state_id,rotation_no,asset_id,left_offset,top_offset,flip_x " +
             "from doom_r2_world_sprite_catalog order by state_id,rotation_no")) {
      while (rows.next()) {
        int index = stateIndexByName.get(rows.getString(1)) * 9 + rows.getInt(2);
        catalogAsset[index] = spriteAssetById.get(rows.getInt(3));
        catalogLeft[index] = rows.getInt(4); catalogTop[index] = rows.getInt(5);
        catalogFlip[index] = (byte) rows.getInt(6); catalogPresent[index] = 1;
      }
    }
    try (Statement statement = connection.createStatement();
         ResultSet rows = statement.executeQuery(
             "select count(*) from doom_map_thing t join doom_thing_type_def d " +
             "on d.thing_type=t.thing_type where t.thing_type<>1 and d.spawn_state_id is not null")) {
      rows.next(); mobjCount = rows.getInt(1);
    }
    mobjId = new int[mobjCount]; mobjX = new int[mobjCount]; mobjY = new int[mobjCount];
    mobjZ = new int[mobjCount]; mobjAngle = new int[mobjCount]; mobjState = new int[mobjCount];
    try (Statement statement = connection.createStatement();
         ResultSet rows = statement.executeQuery(
             "select t.thing_id,t.x,t.y,0,t.angle,d.spawn_state_id from doom_map_thing t " +
             "join doom_thing_type_def d on d.thing_type=t.thing_type " +
             "where t.thing_type<>1 and d.spawn_state_id is not null order by t.thing_id")) {
      int index = 0;
      while (rows.next()) {
        mobjId[index] = rows.getInt(1); mobjX[index] = rows.getInt(2);
        mobjY[index] = rows.getInt(3); mobjZ[index] = rows.getInt(4);
        mobjAngle[index] = rows.getInt(5);
        mobjState[index] = stateIndexByName.get(rows.getString(6)); index++;
      }
      require(index == mobjCount, "mobj count mismatch");
    }
    colormap = new short[32 * 256];
    try (Statement statement = connection.createStatement();
         ResultSet rows = statement.executeQuery(
             "select map_index,palette_index,mapped_index from doom_colormap_texel " +
             "order by map_index,palette_index")) {
      int count = 0;
      while (rows.next()) {
        colormap[rows.getInt(1) * 256 + rows.getInt(2)] = (short) rows.getInt(3);
        count++;
      }
      require(count == colormap.length, "colormap count mismatch");
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
    try (Statement statement = connection.createStatement();
         ResultSet rows = statement.executeQuery(
             "select angle_degrees,column_no,ray_x,ray_y from doom_render_ray " +
             "where profile_id='CANONICAL_320X200' order by angle_degrees,column_no")) {
      int index = 0;
      while (rows.next()) {
        require(rows.getInt(2) == index % WIDTH, "ray profile column mismatch");
        rayXProfile[index] = rows.getDouble(3); rayYProfile[index] = rows.getDouble(4);
        index++;
      }
      require(index == rayXProfile.length, "ray profile size mismatch");
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
    wallFrame = new short[WIDTH * 200]; wallOwned = new byte[wallFrame.length];
    wallColored = new byte[wallFrame.length];
    intervalOffset = new int[WIDTH]; intervalCount = new int[WIDTH];
    intervalSector = new int[MAX_INTERVALS]; intervalStart = new double[MAX_INTERVALS];
    intervalEnd = new double[MAX_INTERVALS]; intervalClipTop = new double[MAX_INTERVALS];
    intervalClipBottom = new double[MAX_INTERVALS];
    presentationFrame = new short[wallFrame.length]; overlayPalette = new short[wallFrame.length];
    overlayDepth = new double[wallFrame.length]; overlayKind = new byte[wallFrame.length];
    overlaySource = new int[wallFrame.length]; overlayAssetX = new int[wallFrame.length];
    overlayAssetY = new int[wallFrame.length];
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
    intervalTotal = 0;
    Arrays.fill(wallFrame, (short) -1); Arrays.fill(wallOwned, (byte) 0);
    Arrays.fill(wallColored, (byte) 0); Arrays.fill(intervalCount, 0);
    Arrays.fill(overlayDepth, Double.POSITIVE_INFINITY);
    Arrays.fill(overlayKind, (byte) 0);
    if (retainCandidates) Arrays.fill(portalCandidates, (byte) 0);
    for (int column = 0; column < WIDTH; column++) {
      intervalOffset[column] = intervalTotal;
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
      double tStart = 0.0;
      boolean hadActive = false;
      boolean terminated = false;
      for (int i = 0; i < orderedCount && !terminated; i++) {
        int id = orderedSegs[i];
        int from = facingSector(id, px, py);
        if (from != currentSector) continue;
        addInterval(column, tStart, orderedDepths[i], currentSector, clipTop, clipBottom);
        hadActive = true;
        activePortalPairs++;
        if (retainCandidates) portalCandidates[id * WIDTH + column] = 1;
        int to = oppositeSector(id, px, py);
        drawActiveWall(id, column, px, py, orderedDepths[i], dirX, dirY, plnX,
            plnY, from, to, clipTop, clipBottom, eyeZ);
        if (to >= 0) drawMaskedWall(id, column, px, py, orderedDepths[i], dirX,
            dirY, plnX, plnY, from, clipTop, clipBottom, eyeZ);
        if (to < 0) {
          terminated = true;
        } else {
          int openingTop = Math.min(sectorCeiling[from], sectorCeiling[to]);
          int openingBottom = Math.max(sectorFloor[from], sectorFloor[to]);
          clipTop = Math.max(clipTop,
              100.0 - (openingTop - eyeZ) * projectionK / orderedDepths[i]);
          clipBottom = Math.min(clipBottom,
              100.0 - (openingBottom - eyeZ) * projectionK / orderedDepths[i]);
          if (openingTop <= openingBottom) terminated = true;
          else currentSector = to;
        }
        tStart = orderedDepths[i];
      }
      if (hadActive && !terminated)
        addInterval(column, tStart, farDistance, currentSector, clipTop, clipBottom);
      portalClipTop[column] = Math.max(0.0, clipTop);
      portalClipBottom[column] = Math.min(200.0, clipBottom);
    }
    drawPlanes(px, py, dirX, dirY, plnX, plnY);
    drawSprites(px, py, dirX, dirY);
    System.arraycopy(wallFrame, 0, presentationFrame, 0, wallFrame.length);
    for (int index = 0; index < presentationFrame.length; index++)
      if (overlayKind[index] != 0) presentationFrame[index] = overlayPalette[index];
  }

  private static void addInterval(int column, double start, double end, int sector,
      double clipTop, double clipBottom) {
    require(intervalTotal < MAX_INTERVALS, "sector interval capacity exceeded");
    intervalStart[intervalTotal] = start; intervalEnd[intervalTotal] = end;
    intervalSector[intervalTotal] = sector;
    intervalClipTop[intervalTotal] = Math.max(0.0, clipTop);
    intervalClipBottom[intervalTotal] = Math.min(200.0, clipBottom);
    intervalTotal++; intervalCount[column]++;
  }

  private static void drawPlanes(int px, int py, double dirX, double dirY,
      double plnX, double plnY) {
    for (int column = 0; column < WIDTH; column++) {
      double rayX = rayXProfile[activeAngle * WIDTH + column];
      double rayY = rayYProfile[activeAngle * WIDTH + column];
      int firstInterval = intervalOffset[column];
      int endInterval = firstInterval + intervalCount[column];
      for (int interval = firstInterval; interval < endInterval; interval++) {
        int sector = intervalSector[interval];
        double eyeZ = sectorFloor[intervalSector[firstInterval]] + 41.0;
        int firstRow = Math.max(0, (int) Math.ceil(intervalClipTop[interval] - .5));
        int endRow = Math.min(200, (int) Math.ceil(intervalClipBottom[interval] - .5));
        for (int row = firstRow; row < endRow; row++) {
          int frameOffset = column * 200 + row;
          if (wallOwned[frameOffset] != 0 || wallFrame[frameOffset] >= 0) continue;
          double center = row + .5;
          boolean ceiling = center < 100.0;
          if (ceiling && sectorCeiling[sector] <= eyeZ) continue;
          if (!ceiling && sectorFloor[sector] >= eyeZ) continue;
          double distance = ceiling ?
              (sectorCeiling[sector] - eyeZ) * projectionK / (100.0 - center) :
              (eyeZ - sectorFloor[sector]) * projectionK / (center - 100.0);
          if (distance < intervalStart[interval] || distance >= intervalEnd[interval]) continue;
          int raw;
          int light;
          if (ceiling && "F_SKY1".equals(sectorCeilingFlat[sector])) {
            Integer asset = wallAssetByName.get("SKY1");
            require(asset != null, "SKY1 asset missing");
            int x = wrap(sqlFloor(column / 2.0), wallAssetWidth[asset]);
            int y = wrap(sqlFloor(center), wallAssetHeight[asset]);
            raw = wallAssetTexels[asset][x * wallAssetHeight[asset] + y];
            light = 255;
          } else {
            String name = ceiling ? sectorCeilingFlat[sector] : sectorFloorFlat[sector];
            Integer asset = flatAssetByName.get(name);
            require(asset != null, "flat asset missing: " + name);
            int x = wrap((int) Math.floor(px + rayX * distance), 64);
            int y = wrap((int) Math.floor(py + rayY * distance), 64);
            raw = flatAssetTexels[asset][x * 64 + y];
            light = sectorLight[sector];
          }
          if (raw < 0) continue;
          int lightBand = Math.max(0, Math.min(31, (255 - light) / 8));
          wallFrame[frameOffset] = colormap[lightBand * 256 + raw];
        }
      }
    }
  }

  private static void drawSprites(int px, int py, double forwardX, double forwardY) {
    int centerColumn = WIDTH / 2;
    if (intervalCount[centerColumn] == 0) return;
    double eyeZ = sectorFloor[intervalSector[intervalOffset[centerColumn]]] + 41.0;
    for (int mobj = 0; mobj < mobjCount; mobj++) {
      double relX = mobjX[mobj] - px, relY = mobjY[mobj] - py;
      double depth = relX * forwardX + relY * forwardY;
      if (depth <= 1.0) continue;
      double lateral = -relX * forwardY + relY * forwardX;
      double bearing = Math.atan2(py - mobjY[mobj], px - mobjX[mobj]) * 180.0 / Math.PI;
      double normalized = (bearing - mobjAngle[mobj] + 720.0) % 360.0;
      int rotation = ((int) Math.floor((normalized + 22.5) / 45.0)) % 8 + 1;
      int state = mobjState[mobj];
      if (state < 0 || state >= catalogStateCount) continue;
      int catalog = state * 9 + (catalogPresent[state * 9] != 0 ? 0 : rotation);
      if (catalogPresent[catalog] == 0) continue;
      int asset = catalogAsset[catalog];
      int width = spriteAssetWidth[asset], height = spriteAssetHeight[asset];
      double screenCenter = 160.0 + lateral * 160.0 / depth;
      double scale = 160.0 / depth;
      int left = (int) Math.floor(screenCenter - catalogLeft[catalog] * scale);
      int right = (int) Math.ceil(screenCenter +
          (width - catalogLeft[catalog]) * scale) - 1;
      int top = (int) Math.floor(100.0 -
          (mobjZ[mobj] + catalogTop[catalog] - eyeZ) * scale);
      int bottom = (int) Math.ceil(100.0 -
          (mobjZ[mobj] + catalogTop[catalog] - height - eyeZ) * scale) - 1;
      int firstColumn = Math.max(0, left), endColumn = Math.min(WIDTH, right + 1);
      int screenWidth = right - left + 1, screenHeight = bottom - top + 1;
      if (firstColumn >= endColumn || screenWidth <= 0 || screenHeight <= 0) continue;
      for (int column = firstColumn; column < endColumn; column++) {
        if (!(depth < nearestSolidDepth[column] - 1e-9)) continue;
        int interval = -1;
        int firstInterval = intervalOffset[column];
        int endInterval = firstInterval + intervalCount[column];
        for (int candidate = firstInterval; candidate < endInterval; candidate++) {
          if (depth >= intervalStart[candidate] && depth < intervalEnd[candidate]) {
            interval = candidate; break;
          }
        }
        if (interval < 0) continue;
        int firstRow = Math.max(Math.max(0, top),
            (int) Math.ceil(intervalClipTop[interval] - .5));
        int endRow = Math.min(Math.min(200, bottom + 1),
            (int) Math.ceil(intervalClipBottom[interval] - .5));
        if (firstRow >= endRow) continue;
        int assetX = (int) Math.min(width - 1, Math.max(0,
            ((long) (column - left) * width) / screenWidth));
        int sampleX = catalogFlip[catalog] != 0 ? width - 1 - assetX : assetX;
        for (int row = firstRow; row < endRow; row++) {
          int assetY = (int) Math.min(height - 1, Math.max(0,
              ((long) (row - top) * height) / screenHeight));
          int raw = spriteAssetTexels[asset][sampleX * height + assetY];
          if (raw < 0) continue;
          int index = column * 200 + row;
          if (overlayWins(index, depth, (byte) 2, mobjId[mobj], assetY, assetX)) {
            overlayDepth[index] = depth; overlayKind[index] = 2;
            overlaySource[index] = mobjId[mobj]; overlayAssetX[index] = assetX;
            overlayAssetY[index] = assetY; overlayPalette[index] = (short) raw;
          }
        }
      }
    }
  }

  private static double acceptedDepth(int id, int column, int px, int py,
      double dirX, double dirY, double plnX, double plnY) {
    double rayX = rayXProfile[activeAngle * WIDTH + column];
    double rayY = rayYProfile[activeAngle * WIDTH + column];
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

  private static double acceptedU(int id, int column, int px, int py,
      double dirX, double dirY, double plnX, double plnY) {
    double rayX = rayXProfile[activeAngle * WIDTH + column];
    double rayY = rayYProfile[activeAngle * WIDTH + column];
    double segX = segEndX[id] - segStartX[id];
    double segY = segEndY[id] - segStartY[id];
    double determinant = rayX * segY - rayY * segX;
    double relX = segStartX[id] - px, relY = segStartY[id] - py;
    return (relX * rayY - relY * rayX) / determinant;
  }

  private static int wrap(int value, int modulus) {
    int result = value % modulus;
    return result < 0 ? result + modulus : result;
  }

  private static int sqlFloor(double value) {
    double nearest = Math.rint(value);
    if (Math.abs(value - nearest) <= 1e-12) value = nearest;
    return (int) Math.floor(value);
  }

  private static void drawWallPiece(int id, int column, double depth, double hitU,
      double clipTop, double clipBottom, double worldTop, double worldBottom,
      String texture, double anchor, int xOffset, int yOffset, int light,
      double eyeZ) {
    double screenTop = 100.0 - (worldTop - eyeZ) * projectionK / depth;
    double screenBottom = 100.0 - (worldBottom - eyeZ) * projectionK / depth;
    int first = Math.max(0, (int) Math.ceil(Math.max(clipTop, screenTop) - .5));
    int end = Math.min(200, (int) Math.ceil(Math.min(clipBottom, screenBottom) - .5));
    if (first >= end) return;
    Integer asset = wallAssetByName.get(texture);
    double deltaX = segEndX[id] - segStartX[id];
    double deltaY = segEndY[id] - segStartY[id];
    double length = Math.sqrt(deltaX * deltaX + deltaY * deltaY);
    double sampleX = segOffset[id] + xOffset + hitU * length;
    int base = column * 200;
    for (int row = first; row < end; row++) {
      int frameOffset = base + row;
      if (wallOwned[frameOffset] != 0) continue;
      wallOwned[frameOffset] = 1;
      if (asset == null) continue;
      int sampleColumn = wrap(sqlFloor(sampleX), wallAssetWidth[asset]);
      double sampleY = anchor - (eyeZ + (100.0 - (row + .5)) * depth / projectionK) + yOffset;
      int sampleRow = wrap(sqlFloor(sampleY), wallAssetHeight[asset]);
      int raw = wallAssetTexels[asset][sampleColumn * wallAssetHeight[asset] + sampleRow];
      if (raw < 0) continue;
      int lightBand = Math.max(0, Math.min(31, (255 - light) / 8));
      wallFrame[frameOffset] = colormap[lightBand * 256 + raw];
      wallColored[frameOffset] = 1;
    }
  }

  private static void drawActiveWall(int id, int column, int px, int py,
      double depth, double dirX, double dirY, double plnX, double plnY,
      int from, int to, double clipTop, double clipBottom, double eyeZ) {
    long cross = (long) (px - lineStartX[id]) * (lineEndY[id] - lineStartY[id])
        - (long) (py - lineStartY[id]) * (lineEndX[id] - lineStartX[id]);
    boolean right = cross > 0;
    String upper = right ? rightUpper[id] : leftUpper[id];
    String lower = right ? rightLower[id] : leftLower[id];
    String middle = right ? rightMiddle[id] : leftMiddle[id];
    int xOffset = right ? rightXOffset[id] : leftXOffset[id];
    int yOffset = right ? rightYOffset[id] : leftYOffset[id];
    double hitU = acceptedU(id, column, px, py, dirX, dirY, plnX, plnY);
    boolean termination = to < 0 || Math.min(sectorCeiling[from], sectorCeiling[to]) <=
        Math.max(sectorFloor[from], sectorFloor[to]);
    if (termination) {
      String texture = !"-".equals(middle) ? middle :
          (!"-".equals(upper) ? upper : lower);
      double anchor = (lineFlags[id] & 16) != 0 ? sectorFloor[from] + 128.0 :
          sectorCeiling[from];
      drawWallPiece(id, column, depth, hitU, clipTop, clipBottom,
          sectorCeiling[from], sectorFloor[from], texture, anchor,
          xOffset, yOffset, sectorLight[from], eyeZ);
      return;
    }
    if (sectorFloor[to] > sectorFloor[from] && !"-".equals(lower)) {
      double anchor = (lineFlags[id] & 16) != 0 ? sectorCeiling[from] : sectorFloor[to];
      drawWallPiece(id, column, depth, hitU, clipTop, clipBottom,
          sectorFloor[to], sectorFloor[from], lower, anchor,
          xOffset, yOffset, sectorLight[from], eyeZ);
    }
    if (sectorCeiling[to] < sectorCeiling[from] && !"-".equals(upper) &&
        !("F_SKY1".equals(sectorCeilingFlat[from]) &&
          "F_SKY1".equals(sectorCeilingFlat[to]))) {
      double anchor = (lineFlags[id] & 8) != 0 ? sectorCeiling[to] + 128.0 :
          sectorCeiling[from];
      drawWallPiece(id, column, depth, hitU, clipTop, clipBottom,
          sectorCeiling[from], sectorCeiling[to], upper, anchor,
          xOffset, yOffset, sectorLight[from], eyeZ);
    }
  }

  private static boolean overlayWins(int index, double depth, byte kind, int source,
      int assetY, int assetX) {
    if (depth < overlayDepth[index]) return true;
    if (depth > overlayDepth[index]) return false;
    if (overlayKind[index] == 0 || kind < overlayKind[index]) return true;
    if (kind > overlayKind[index]) return false;
    if (source < overlaySource[index]) return true;
    if (source > overlaySource[index]) return false;
    if (assetY < overlayAssetY[index]) return true;
    return assetY == overlayAssetY[index] && assetX < overlayAssetX[index];
  }

  private static void drawMaskedWall(int id, int column, int px, int py,
      double depth, double dirX, double dirY, double plnX, double plnY,
      int from, double clipTop, double clipBottom, double eyeZ) {
    long cross = (long) (px - lineStartX[id]) * (lineEndY[id] - lineStartY[id])
        - (long) (py - lineStartY[id]) * (lineEndX[id] - lineStartX[id]);
    boolean right = cross > 0;
    String texture = right ? rightMiddle[id] : leftMiddle[id];
    if (texture == null || "-".equals(texture)) return;
    Integer asset = wallAssetByName.get(texture);
    if (asset == null) return;
    int xOffset = right ? rightXOffset[id] : leftXOffset[id];
    int yOffset = right ? rightYOffset[id] : leftYOffset[id];
    double hitU = acceptedU(id, column, px, py, dirX, dirY, plnX, plnY);
    double deltaX = segEndX[id] - segStartX[id];
    double deltaY = segEndY[id] - segStartY[id];
    double length = Math.sqrt(deltaX * deltaX + deltaY * deltaY);
    int assetX = wrap(sqlFloor(segOffset[id] + xOffset + hitU * length),
        wallAssetWidth[asset]);
    int first = Math.max(0, (int) Math.ceil(Math.max(0.0, clipTop) - .5));
    int end = Math.min(200, (int) Math.ceil(Math.min(200.0, clipBottom) - .5));
    for (int row = first; row < end; row++) {
      double center = row + .5;
      double sampleY = sectorCeiling[from] -
          (eyeZ + (100.0 - center) * depth / 160.0) + yOffset;
      int assetY = wrap(sqlFloor(sampleY), wallAssetHeight[asset]);
      int raw = wallAssetTexels[asset][assetX * wallAssetHeight[asset] + assetY];
      if (raw < 0) continue;
      int index = column * 200 + row;
      if (overlayWins(index, depth, (byte) 1, segLineId[id], assetY, assetX)) {
        overlayDepth[index] = depth; overlayKind[index] = 1;
        overlaySource[index] = segLineId[id]; overlayAssetX[index] = assetX;
        overlayAssetY[index] = assetY; overlayPalette[index] = (short) raw;
      }
    }
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
    activeAngle = angle;
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
    int sqlWallPixels = 0, wallMissing = 0, wallColorMismatch = 0, wallExtra = 0;
    int sqlWorldPixels = 0, worldMissing = 0, worldColorMismatch = 0, worldExtra = 0;
    int sqlMaskedWall = 0, maskedWallMissing = 0, maskedWallColor = 0, maskedWallExtra = 0;
    int sqlMaskedTotal = 0, maskedMissing = 0, maskedColor = 0, maskedExtra = 0;
    byte[] oracleWall = new byte[wallFrame.length];
    byte[] oracleWorld = new byte[wallFrame.length];
    byte[] oracleMasked = new byte[wallFrame.length];
    byte[] oracleMaskedTotal = new byte[wallFrame.length];
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
               "where h.session_token=? and h.is_active=1 group by h.column_no");
           PreparedStatement wallOracle = connection.prepareStatement(
               "select column_no,row_no,palette_index,layer_ordinal " +
               "from doom_r2_staged_pixel_rows where session_token=?");
           PreparedStatement maskedOracle = connection.prepareStatement(
               "select column_no,row_no,palette_index from " +
               "doom_r2_staged_masked_candidate_rows where session_token=? " +
               "and source_kind='MASKED' and is_selected=1");
           PreparedStatement fullMaskedOracle = connection.prepareStatement(
               "select column_no,row_no,palette_index from " +
               "doom_r2_staged_masked_candidate_rows where session_token=? " +
               "and is_selected=1")) {
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
          staging.executeUpdate("delete from frame_portal_hit");
          staging.executeUpdate("insert into frame_portal_hit select * " +
              "from doom_r2_staged_portal_hit_rows where session_token='" + session + "'");
          staging.executeUpdate("delete from frame_sector_interval");
          staging.executeUpdate("insert into frame_sector_interval select * " +
              "from doom_r2_staged_sector_interval_rows where session_token='" + session + "'");
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
          if (pose == 0) {
            Arrays.fill(oracleWall, (byte) 0);
            Arrays.fill(oracleWorld, (byte) 0);
            wallOracle.setString(1, session);
            try (ResultSet rows = wallOracle.executeQuery()) {
              while (rows.next()) {
                int index = rows.getInt(1) * 200 + rows.getInt(2);
                oracleWorld[index] = 1; sqlWorldPixels++;
                if (wallFrame[index] < 0) worldMissing++;
                else if (wallFrame[index] != rows.getInt(3)) {
                  worldColorMismatch++;
                }
                int layer = rows.getInt(4);
                if (layer >= 10 && layer <= 12) {
                  sqlWallPixels++; oracleWall[index] = 1;
                  if (wallColored[index] == 0) wallMissing++;
                  else if (wallFrame[index] != rows.getInt(3)) wallColorMismatch++;
                }
              }
            }
            for (int index = 0; index < wallFrame.length; index++) {
              if (wallColored[index] != 0 && oracleWall[index] == 0) wallExtra++;
              if (wallFrame[index] >= 0 && oracleWorld[index] == 0) worldExtra++;
            }
            maskedOracle.setString(1, session);
            Arrays.fill(oracleMasked, (byte) 0);
            try (ResultSet rows = maskedOracle.executeQuery()) {
              while (rows.next()) {
                sqlMaskedWall++;
                int index = rows.getInt(1) * 200 + rows.getInt(2);
                oracleMasked[index] = 1;
                if (overlayKind[index] != 1) maskedWallMissing++;
                else if (overlayPalette[index] != rows.getInt(3)) maskedWallColor++;
              }
            }
            for (int index = 0; index < overlayKind.length; index++)
              if (overlayKind[index] == 1 && oracleMasked[index] == 0) maskedWallExtra++;
            fullMaskedOracle.setString(1, session);
            Arrays.fill(oracleMaskedTotal, (byte) 0);
            try (ResultSet rows = fullMaskedOracle.executeQuery()) {
              while (rows.next()) {
                sqlMaskedTotal++;
                int index = rows.getInt(1) * 200 + rows.getInt(2);
                oracleMaskedTotal[index] = 1;
                if (overlayKind[index] == 0) maskedMissing++;
                else if (overlayPalette[index] != rows.getInt(3)) maskedColor++;
              }
            }
            for (int index = 0; index < overlayKind.length; index++)
              if (overlayKind[index] != 0 && oracleMaskedTotal[index] == 0) maskedExtra++;
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
    return new int[] {sqlActive, missing, extra, clipMismatch, sqlWallPixels,
        wallMissing, wallColorMismatch, wallExtra, sqlWorldPixels, worldMissing,
        worldColorMismatch, worldExtra, sqlMaskedWall, maskedWallMissing,
        maskedWallColor, maskedWallExtra, sqlMaskedTotal, maskedMissing,
        maskedColor, maskedExtra};
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
      require(portalOracle[1] == 0 && portalOracle[2] == 0 && portalOracle[3] == 0 &&
          portalOracle[5] == 0 && portalOracle[6] == 0 && portalOracle[7] == 0 &&
          portalOracle[9] == 0 && portalOracle[10] == 0 && portalOracle[11] == 0 &&
          portalOracle[13] == 0 && portalOracle[14] == 0 && portalOracle[15] == 0 &&
          portalOracle[17] == 0 && portalOracle[18] == 0 && portalOracle[19] == 0,
          "portal walk differs from production SQL: missing=" + portalOracle[1] +
          " extra=" + portalOracle[2] + " clip_mismatch=" + portalOracle[3] +
          " wall_missing=" + portalOracle[5] + " wall_color=" + portalOracle[6] +
          " wall_extra=" + portalOracle[7] + " world_missing=" + portalOracle[9] +
          " world_color=" + portalOracle[10] + " world_extra=" + portalOracle[11] +
          " masked_missing=" + portalOracle[13] + " masked_color=" + portalOracle[14] +
          " masked_extra=" + portalOracle[15] + " full_masked_missing=" + portalOracle[17] +
          " full_masked_color=" + portalOracle[18] + " full_masked_extra=" + portalOracle[19]);

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
      require(p95 <= 8.0, "exact opaque-world p95 gate failed: " + p95 + " ms");
      require(retention <= .25, "candidate retention gate failed: " + retention);
      System.out.printf(java.util.Locale.ROOT,
          "BSP_KERNEL load_ms=%.3f p50_ms=%.6f p95_ms=%.6f p99_ms=%.6f " +
          "audit_poses=12 sql_accepted=%d missing=%d candidate_retention=%.6f " +
          "sql_visible=%d visible_missing=%d visible_retention=%.6f " +
          "sql_portal_active=%d portal_missing=%d portal_extra=%d clip_mismatch=%d " +
          "sql_wall_pixels=%d wall_missing=%d wall_color=%d wall_extra=%d " +
          "sql_world_pixels=%d world_missing=%d world_color=%d world_extra=%d " +
          "sql_masked_wall=%d masked_missing=%d masked_color=%d masked_extra=%d " +
          "sql_masked_total=%d full_masked_missing=%d full_masked_color=%d full_masked_extra=%d " +
          "max_nodes=%d max_ssectors=%d sink=%d%n",
          loadMs, percentile(samples, .50), p95, percentile(samples, .99),
          auditAccepted, auditMissing, retention, auditVisible, auditVisibleMissing,
          visibleRetention, portalOracle[0], portalOracle[1], portalOracle[2], portalOracle[3],
          portalOracle[4], portalOracle[5], portalOracle[6], portalOracle[7],
          portalOracle[8], portalOracle[9], portalOracle[10], portalOracle[11],
          portalOracle[12], portalOracle[13], portalOracle[14], portalOracle[15],
          portalOracle[16], portalOracle[17], portalOracle[18], portalOracle[19],
          maxNodes, maxSubsectors, sink);
    }
  }
}
