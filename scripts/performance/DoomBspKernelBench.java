import java.io.ByteArrayInputStream;
import java.io.ByteArrayOutputStream;
import java.io.DataInputStream;
import java.io.DataOutputStream;
import java.io.InputStream;
import java.nio.charset.StandardCharsets;
import java.nio.ByteBuffer;
import java.nio.CharBuffer;
import java.nio.charset.CodingErrorAction;
import java.nio.file.Files;
import java.nio.file.Paths;
import java.math.BigDecimal;
import java.security.MessageDigest;
import java.sql.Connection;
import java.sql.Blob;
import java.sql.Clob;
import java.sql.CallableStatement;
import java.sql.DriverManager;
import java.sql.PreparedStatement;
import java.sql.ResultSet;
import java.sql.Statement;
import java.sql.Types;
import java.util.Arrays;
import java.util.Base64;
import java.util.HashMap;
import java.util.Map;
import java.util.zip.CRC32;
import java.util.zip.Deflater;
import java.util.zip.GZIPInputStream;
import oracle.sql.NUMBER;

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
  private static double[] segRelativeStartX, segRelativeStartY;
  private static double[] segRelativeEndX, segRelativeEndY;
  private static double[] segExactTNumerator;
  private static int[] segExactEpoch;
  private static int exactGeometryEpoch=1;
  private static int[] uniqueMapX,uniqueMapY,segStartXIndex,segStartYIndex;
  private static int[] segEndXIndex,segEndYIndex,uniqueDirectionX,uniqueDirectionY,segDirectionIndex;
  private static long[] segCrossBase;
  private static double[] exactRelativeX,exactRelativeY;
  private static double[] exactDirectionHi,exactDirectionLo;
  private static double exactCameraXHi,exactCameraXLo,exactCameraYHi,exactCameraYLo;
  private static int[] exactDirectionEpoch;
  private static BigDecimal preparedCameraX,preparedCameraY;
  private static int[] segLineId, lineStartX, lineStartY, lineEndX, lineEndY;
  private static int[] rightSector, leftSector;
  private static int[] facingSectorCache,oppositeSectorCache;
  private static byte[] rightFacingCache;
  private static int[] lineFlags, segOffset, rightXOffset, rightYOffset;
  private static int[] leftXOffset, leftYOffset;
  private static String[] rightUpper, rightLower, rightMiddle;
  private static String[] leftUpper, leftLower, leftMiddle;
  private static int[] rightUpperAsset,rightLowerAsset,rightMiddleAsset;
  private static int[] leftUpperAsset,leftLowerAsset,leftMiddleAsset;
  // Dynamic switch presentation is indexed by immutable map linedef id.  The
  // staged image comes from SQL's LINE_STATE/ACTIVE_SWITCHES oracle; no route
  // or map-specific linedef ids are embedded in the renderer.
  private static byte[] lineSwitchOn;
  private static int[] lineSwitchTimer;
  private static int[] switchOnWallAsset;
  private static int mapLineCount;
  private static boolean anySwitchOn;
  private static double[] segLength;
  private static byte[] segSolid;
  private static double[] sectorFloor, sectorCeiling;
  private static int[] sectorLight;
  private static String[] sectorCeilingFlat, sectorFloorFlat;
  private static int[] sectorCeilingAsset, sectorFloorAsset, sectorLightBand;
  private static int[] activeSectorCeilingAsset, activeSectorFloorAsset;
  private static byte[] sectorCeilingSky;
  private static double[] planeCeilingDistance, planeFloorDistance;
  private static boolean[] visiblePlaneSector;
  private static int skyAsset;
  private static Map<String, Integer> wallAssetByName;
  private static int[] wallAssetWidth, wallAssetHeight;
  private static short[][] wallAssetTexels;
  private static Map<String, Integer> flatAssetByName;
  private static short[][] flatAssetTexels;
  private static Map<String, int[]> animationByAsset;
  private static Map<String, int[]> animationByGroup;
  private static int[][] wallAnimationByAsset;
  private static int[] activeWallAsset;
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
  private static double[] acceptedDepthCache,acceptedUCache;
  private static double[] nearestSolidDepth;
  private static final int MAX_VISIBLE_PER_COLUMN = 128;
  private static int[] columnVisibleCount, columnVisibleSeg, orderedSegs;
  private static double[] columnVisibleDepth, orderedDepths;
  private static int[] orderedSegScratch;
  private static double[] orderedDepthScratch;
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
  private static Map<String, Integer> spriteAssetByName;
  private static int[] spriteAssetWidth, spriteAssetHeight;
  private static short[][] spriteAssetTexels;
  private static int catalogStateCount;
  private static Map<String, Integer> stateIndexByName;
  private static int[] catalogAsset, catalogLeft, catalogTop;
  private static byte[] catalogFlip, catalogPresent;
  private static int mobjCount;
  private static int[] mobjId, mobjState;
  private static double[] mobjX, mobjY, mobjZ, mobjAngle;
  private static Map<String, Integer> uiAssetByName;
  private static int[] uiAssetWidth, uiAssetHeight;
  private static short[][] uiAssetTexels;
  private static int uiStatusBarAsset, uiPauseAsset, weaponAsset;
  private static final int[] uiKeyAsset = new int[3];
  private static final int[] uiDigitAsset = new int[10];
  private static short[] finalFrame;
  private static final byte[] codecFrame = new byte[WIDTH * 200];
  private static final byte[] codecDigest = new byte[32];
  private static final byte[] HEX = "0123456789abcdef".getBytes(StandardCharsets.US_ASCII);
  private static final byte[] BASE64 =
      "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
          .getBytes(StandardCharsets.US_ASCII);
  private static final String ZERO_SHA =
      "0000000000000000000000000000000000000000000000000000000000000000";
  private static final byte[] codecJson = new byte[1_500_000];
  private static final byte[] codecGzip = new byte[1_500_000];
  private static MessageDigest codecSha256;
  private static final CRC32 codecCrc = new CRC32();
  private static final Deflater codecDeflater = new Deflater(1, true);
  private static int codecJsonLength, codecGzipLength, codecRunCount;
  private static boolean databaseCacheLoaded;
  private static final int KERNEL_PACK_MAGIC = 0x44424b50;
  private static final int KERNEL_PACK_VERSION = 1;
  private static long lastKernelLoadNanos, lastSnapshotNanos;
  private static long lastRetainedUpdateNanos;
  private static long retainedDticSeq=-1;
  private static int[] dticActorId=new int[0],dticActorIndex=new int[0],dticActorState=new int[0],dticActorTarget=new int[0];
  private static double[] dticActorX=new double[0],dticActorY=new double[0];
  private static int[] dticSpawnId=new int[0],dticSpawnIndex=new int[0],dticSpawnState=new int[0];
  private static int[] dticSpawnTarget=new int[0],dticSpawnTracer=new int[0],dticSpawnOwner=new int[0];
  private static double[] dticSpawnX=new double[0],dticSpawnY=new double[0],dticSpawnZ=new double[0];
  private static int[] dticOldState=new int[0];
  private static double[] dticOldX=new double[0],dticOldY=new double[0];
  private static double[] directOldZ=new double[0];
  private static int dticAppliedActors,dticPriorMobjCount,dticPriorLiveTic;
  private static long dticPriorSeq;private static boolean dticApplied;
  private static boolean directApplied;private static String directRequest;
  private static int[] directSectorId=new int[0],directOldSectorLight=new int[0];
  private static int[] directOldSectorLightBand=new int[0];
  private static int directSectorChangeCount;
  private static int[] directGeometryId=new int[0];
  private static double[] directOldSectorFloor=new double[0],directOldSectorCeiling=new double[0];
  private static int directGeometryChangeCount;
  private static int[] directSwitchId=new int[0],directOldSwitchTimer=new int[0];
  private static byte[] directOldSwitchOn=new byte[0];
  private static int directSwitchChangeCount;
  private static boolean directOldAnySwitchOn;
  private static double directOldCameraX,directOldCameraY,directOldEyeZ;
  private static BigDecimal directOldExactX,directOldExactY;
  private static int directOldAngle,directOldHealth,directOldArmor,directOldAmmo,directOldWeaponAsset,directOldComplete;
  private static String directOldMode;
  private static String lastDynamicFailure="";
  private static long lastRenderNanos, lastCodecNanos, lastBlobNanos;
  private static long lastBspNanos, lastSolidNanos, lastPortalNanos;
  private static long lastPortalResetNanos,lastPortalSortNanos,lastPortalWalkNanos;
  private static long lastPlaneNanos, lastSpriteNanos, lastPresentationNanos;
  private static double cameraEyeZ = 41.0;
  private static double liveCameraX = -416.0, liveCameraY = 256.0;
  private static BigDecimal liveExactCameraX = BigDecimal.valueOf(-416);
  private static BigDecimal liveExactCameraY = BigDecimal.valueOf(256);
  private static int liveAngle;
  private static int liveTic, liveAmmo = 50, liveHealth = 100, liveArmor;
  private static int liveBlueKey, liveYellowKey, liveRedKey, livePaused, liveComplete;
  private static String liveMode = "game", liveAudio = "[]";

  private static int visitedNodes;
  private static int visitedSubsectors;
  private static int projectedSegs;
  private static int candidatePairs;
  private static int acceptedPairs;
  private static int visiblePairs;
  private static int activePortalPairs;
  private static int largeSortColumns,orderedHitTotal,wallRowAttempts,planeRowAttempts;
  private static int occludedBboxes;
  private static volatile long sink;

  private DoomBspKernelBench() {}

  private static void require(boolean condition, String message) {
    if (!condition) throw new IllegalStateException(message);
  }

  private static int angleProfile(double degrees) {
    double normalized = ((degrees % 360.0) + 360.0) % 360.0;
    int profile = (int) Math.round(normalized / 5.625) % ANGLES;
    require(Math.abs(normalized - profile * 5.625) < 1e-9 ||
        Math.abs(normalized - 360.0) < 1e-9, "camera angle is outside canonical profiles");
    return profile;
  }

  private static String weaponPatch(String weapon) {
    if ("FIST".equals(weapon)) return "PUNGA0";
    if ("SHOTGUN".equals(weapon)) return "SHTGA0";
    if ("CHAINGUN".equals(weapon)) return "CHGGA0";
    if ("ROCKET_LAUNCHER".equals(weapon)) return "MISGA0";
    if ("PLASMA_RIFLE".equals(weapon)) return "PLSGA0";
    if ("CHAINSAW".equals(weapon)) return "SAWGA0";
    return "PISGA0";
  }

  private static int weaponStateAsset(String weapon,String weaponState) {
    if(weaponState!=null){Integer state=stateIndexByName.get(weaponState);
      if(state!=null){int catalog=state*9;
        if(catalog>=0&&catalog<catalogPresent.length&&catalogPresent[catalog]!=0)
          return catalogAsset[catalog];}}
    Integer ready=spriteAssetByName.get(weaponPatch(weapon));
    require(ready!=null,"selected weapon patch missing");return ready.intValue();
  }

  private static void ensureMobjCapacity(int capacity) {
    if (mobjId.length >= capacity) return;
    int next = Math.max(capacity, Math.max(32, mobjId.length * 2));
    mobjId = Arrays.copyOf(mobjId, next); mobjState = Arrays.copyOf(mobjState, next);
    mobjX = Arrays.copyOf(mobjX, next); mobjY = Arrays.copyOf(mobjY, next);
    mobjZ = Arrays.copyOf(mobjZ, next); mobjAngle = Arrays.copyOf(mobjAngle, next);
  }

  private static void prepareExactSegmentRelatives() {
    if(liveExactCameraX.equals(preparedCameraX)&&liveExactCameraY.equals(preparedCameraY))return;
    double cameraX=liveExactCameraX.doubleValue(),cameraY=liveExactCameraY.doubleValue();
    exactCameraXHi=cameraX;exactCameraYHi=cameraY;
    exactCameraXLo=liveExactCameraX.subtract(new BigDecimal(cameraX)).doubleValue();
    exactCameraYLo=liveExactCameraY.subtract(new BigDecimal(cameraY)).doubleValue();
    for(int index=0;index<uniqueMapX.length;index++)exactRelativeX[index]=uniqueMapX[index]-cameraX;
    for(int index=0;index<uniqueMapY.length;index++)exactRelativeY[index]=uniqueMapY[index]-cameraY;
    for (int id = 0; id < segTotal; id++) {
      segRelativeStartX[id]=exactRelativeX[segStartXIndex[id]];
      segRelativeStartY[id]=exactRelativeY[segStartYIndex[id]];
      segRelativeEndX[id]=exactRelativeX[segEndXIndex[id]];
      segRelativeEndY[id]=exactRelativeY[segEndYIndex[id]];
      double cross=(cameraX-lineStartX[id])*(lineEndY[id]-lineStartY[id])-
          (cameraY-lineStartY[id])*(lineEndX[id]-lineStartX[id]);
      boolean right=cross>0;rightFacingCache[id]=(byte)(right?1:0);
      facingSectorCache[id]=right?rightSector[id]:leftSector[id];
      oppositeSectorCache[id]=right?leftSector[id]:rightSector[id];
    }
    if(exactGeometryEpoch==Integer.MAX_VALUE){Arrays.fill(segExactEpoch,0);
      Arrays.fill(exactDirectionEpoch,0);exactGeometryEpoch=1;}
    else exactGeometryEpoch++;
    preparedCameraX=liveExactCameraX;preparedCameraY=liveExactCameraY;
  }

  private static double exactTNumerator(int id){
    if(segExactEpoch[id]!=exactGeometryEpoch){
      int direction=segDirectionIndex[id];
      if(exactDirectionEpoch[direction]!=exactGeometryEpoch){
        double dx=uniqueDirectionX[direction],dy=uniqueDirectionY[direction];
        double yp=exactCameraYHi*dx,ye=productError(exactCameraYHi,dx,yp)+exactCameraYLo*dx;
        double xp=exactCameraXHi*dy,xe=productError(exactCameraXHi,dy,xp)+exactCameraXLo*dy;
        double high=yp-xp,virtualNegative=high-yp;
        double low=(yp-(high-virtualNegative))+(-xp-virtualNegative)+ye-xe;
        double normalized=high+low;
        exactDirectionHi[direction]=normalized;
        exactDirectionLo[direction]=(high-normalized)+low;
        exactDirectionEpoch[direction]=exactGeometryEpoch;
      }
      double cross=segCrossBase[id],high=exactDirectionHi[direction],sum=cross+high;
      double virtualHigh=sum-cross;
      double error=(cross-(sum-virtualHigh))+(high-virtualHigh);
      segExactTNumerator[id]=sum+(error+exactDirectionLo[direction]);
      segExactEpoch[id]=exactGeometryEpoch;
    }
    return segExactTNumerator[id];
  }

  private static double productError(double left,double right,double product){
    double splitLeft=134217729.0*left,leftHigh=splitLeft-(splitLeft-left),leftLow=left-leftHigh;
    double splitRight=134217729.0*right,rightHigh=splitRight-(splitRight-right),rightLow=right-rightHigh;
    return ((leftHigh*rightHigh-product)+leftHigh*rightLow+leftLow*rightHigh)+leftLow*rightLow;
  }

  private static void buildExactGeometryCache() {
    Map<Integer,Integer> xs=new HashMap<>(),ys=new HashMap<>();Map<Long,Integer> dirs=new HashMap<>();
    segStartXIndex=new int[segTotal];segStartYIndex=new int[segTotal];
    segEndXIndex=new int[segTotal];segEndYIndex=new int[segTotal];
    segDirectionIndex=new int[segTotal];segCrossBase=new long[segTotal];
    for(int id=0;id<segTotal;id++) {
      if(!xs.containsKey(segStartX[id]))xs.put(segStartX[id],xs.size());
      if(!xs.containsKey(segEndX[id]))xs.put(segEndX[id],xs.size());
      if(!ys.containsKey(segStartY[id]))ys.put(segStartY[id],ys.size());
      if(!ys.containsKey(segEndY[id]))ys.put(segEndY[id],ys.size());
      segStartXIndex[id]=xs.get(segStartX[id]);segEndXIndex[id]=xs.get(segEndX[id]);
      segStartYIndex[id]=ys.get(segStartY[id]);segEndYIndex[id]=ys.get(segEndY[id]);
      int dx=segEndX[id]-segStartX[id],dy=segEndY[id]-segStartY[id];
      long key=((long)dx<<32)|(dy&0xffffffffL);
      if(!dirs.containsKey(key))dirs.put(key,dirs.size());segDirectionIndex[id]=dirs.get(key);
      segCrossBase[id]=(long)segStartX[id]*dy-(long)segStartY[id]*dx;
    }
    uniqueMapX=new int[xs.size()];for(Map.Entry<Integer,Integer> e:xs.entrySet())uniqueMapX[e.getValue()]=e.getKey();
    uniqueMapY=new int[ys.size()];for(Map.Entry<Integer,Integer> e:ys.entrySet())uniqueMapY[e.getValue()]=e.getKey();
    uniqueDirectionX=new int[dirs.size()];uniqueDirectionY=new int[dirs.size()];
    for(Map.Entry<Long,Integer> e:dirs.entrySet()){uniqueDirectionX[e.getValue()]=(int)(e.getKey()>>32);
      uniqueDirectionY[e.getValue()]=(int)(long)e.getKey();}
    exactRelativeX=new double[uniqueMapX.length];exactRelativeY=new double[uniqueMapY.length];
    exactDirectionEpoch=new int[dirs.size()];exactDirectionHi=new double[dirs.size()];
    exactDirectionLo=new double[dirs.size()];
    preparedCameraX=null;preparedCameraY=null;
  }

  private static void refreshLiveState(Connection connection, String session) throws Exception {
    require(session != null && session.matches("[0-9a-f]{32}"), "invalid session token");
    try (PreparedStatement statement = connection.prepareStatement(
        "select s.current_tic,lower(s.game_mode),case when s.map_status='DONE' then 1 else 0 end," +
        "s.paused,p.x,p.y,p.z+p.view_height+p.view_bob,p.angle,p.health,p.armor," +
        "p.blue_key,p.yellow_key,p.red_key,p.ammo_bullets,p.ammo_shells,p.ammo_rockets," +
        "p.ammo_cells,p.selected_weapon from game_sessions s join players p on " +
        "p.session_token=s.session_token and p.player_id=s.current_player_id " +
        "where s.session_token=?")) {
      statement.setString(1, session);
      try (ResultSet rows = statement.executeQuery()) {
        require(rows.next(), "render session not found");
        liveTic = rows.getInt(1); liveMode = rows.getString(2); liveComplete = rows.getInt(3);
        livePaused = rows.getInt(4); liveCameraX = rows.getDouble(5);
        liveCameraY = rows.getDouble(6); cameraEyeZ = rows.getDouble(7);
        liveAngle = angleProfile(rows.getDouble(8)); liveHealth = rows.getInt(9);
        liveArmor = rows.getInt(10); liveBlueKey = rows.getInt(11);
        liveYellowKey = rows.getInt(12); liveRedKey = rows.getInt(13);
        String weapon = rows.getString(18);
        if ("SHOTGUN".equals(weapon)) liveAmmo = rows.getInt(15);
        else if ("ROCKET_LAUNCHER".equals(weapon)) liveAmmo = rows.getInt(16);
        else if ("PLASMA_RIFLE".equals(weapon)) liveAmmo = rows.getInt(17);
        else liveAmmo = rows.getInt(14);
        Integer selected = spriteAssetByName.get(weaponPatch(weapon));
        require(selected != null, "selected weapon patch missing");
        weaponAsset = selected;
        require(!rows.next(), "duplicate render session");
      }
    }
    int sectors = 0;
    try (PreparedStatement statement = connection.prepareStatement(
        "select sector_id,floor_height,ceiling_height,light_level from sector_state " +
        "where session_token=? order by sector_id")) {
      statement.setString(1, session); statement.setFetchSize(256);
      try (ResultSet rows = statement.executeQuery()) {
        while (rows.next()) {
          int id = rows.getInt(1);
          require(id >= 0 && id < sectorFloor.length, "live sector id out of range");
          sectorFloor[id] = rows.getDouble(2); sectorCeiling[id] = rows.getDouble(3);
          sectorLight[id] = rows.getInt(4);
          sectorLightBand[id] = Math.max(0, Math.min(31, (255 - sectorLight[id]) / 8));
          sectors++;
        }
      }
    }
    require(sectors == sectorFloor.length, "live sector snapshot incomplete");
    for (int id = 0; id < segTotal; id++) {
      int left = leftSector[id], right = rightSector[id];
      segSolid[id] = (byte) (left < 0 || right < 0 ||
          Math.min(sectorCeiling[left], sectorCeiling[right]) <=
          Math.max(sectorFloor[left], sectorFloor[right]) ? 1 : 0);
    }
    int count = 0;
    try (PreparedStatement statement = connection.prepareStatement(
        "select mobj_id,x,y,z,angle,state_id from mobjs where session_token=? order by mobj_id")) {
      statement.setString(1, session); statement.setFetchSize(256);
      try (ResultSet rows = statement.executeQuery()) {
        while (rows.next()) {
          ensureMobjCapacity(count + 1);
          mobjId[count] = rows.getInt(1); mobjX[count] = rows.getDouble(2);
          mobjY[count] = rows.getDouble(3); mobjZ[count] = rows.getDouble(4);
          mobjAngle[count] = rows.getDouble(5);
          Integer state = stateIndexByName.get(rows.getString(6));
          mobjState[count] = state == null ? -1 : state; count++;
        }
      }
    }
    mobjCount = count;
    StringBuilder audio = new StringBuilder("[");
    try (PreparedStatement statement = connection.prepareStatement(
        "select event_ordinal,asset_name,volume,separation from audio_events " +
        "where session_token=? and tic=? order by event_ordinal")) {
      statement.setString(1, session); statement.setInt(2, liveTic);
      try (ResultSet rows = statement.executeQuery()) {
        int countAudio = 0;
        while (rows.next()) {
          if (countAudio != 0) audio.append(',');
          int ordinal = rows.getInt(1);
          String asset = rows.getString(2);
          require(asset.matches("[A-Z0-9_]+"), "invalid audio asset name");
          audio.append('[').append(liveTic).append(',').append(ordinal).append(",\"")
              .append(asset).append("\",").append(rows.getInt(3)).append(',')
              .append(rows.getInt(4)).append(']');
          countAudio++;
        }
      }
    }
    liveAudio = audio.append(']').toString();
  }

  private static void refreshPackedLiveState(Connection connection, String session)
      throws Exception {
    require(session != null && session.matches("[0-9a-f]{32}"), "invalid session token");
    String sql =
        "select kind,id1,text1,text2,n1,n2,n3,n4,n5,n6,n7,n8,n9,n10,n11,n12,n13,n14,n15 from (" +
        "select 0 kind,s.current_tic id1,lower(s.game_mode) text1,p.selected_weapon text2," +
        "case when s.map_status='DONE' then 1 else 0 end n1,s.paused n2,p.x n3,p.y n4," +
        "p.z+p.view_height+p.view_bob n5,p.angle n6,p.health n7,p.armor n8," +
        "p.blue_key n9,p.yellow_key n10,p.red_key n11,p.ammo_bullets n12," +
        "p.ammo_shells n13,p.ammo_rockets n14,p.ammo_cells n15 " +
        "from game_sessions s join players p on p.session_token=s.session_token " +
        "and p.player_id=s.current_player_id where s.session_token=? union all " +
        "select 1,sector_id,null,null,floor_height,ceiling_height,light_level," +
        "null,null,null,null,null,null,null,null,null,null,null,null from sector_state " +
        "where session_token=? union all " +
        "select 2,mobj_id,state_id,null,x,y,z,angle,null,null,null,null,null,null,null,null,null,null,null " +
        "from mobjs where session_token=? union all " +
        "select 3,event_ordinal,asset_name,null,volume,separation,null,null,null,null,null,null,null,null,null,null,null,null,null " +
        "from audio_events where session_token=? and tic=(select current_tic from game_sessions where session_token=?)) " +
        "order by kind,id1";
    int sectors = 0, mobjs = 0, playerRows = 0;
    StringBuilder audio = new StringBuilder("[");
    int audioCount = 0;
    try (PreparedStatement statement = connection.prepareStatement(sql)) {
      for (int bind = 1; bind <= 5; bind++) statement.setString(bind, session);
      statement.setFetchSize(256);
      try (ResultSet rows = statement.executeQuery()) {
        while (rows.next()) {
          int kind = rows.getInt(1), id = rows.getInt(2);
          if (kind == 0) {
            playerRows++;
            liveTic = id; liveMode = rows.getString(3);
            String weapon = rows.getString(4);
            liveComplete = rows.getInt(5); livePaused = rows.getInt(6);
            liveExactCameraX = rows.getBigDecimal(7); liveExactCameraY = rows.getBigDecimal(8);
            liveCameraX = liveExactCameraX.doubleValue(); liveCameraY = liveExactCameraY.doubleValue();
            cameraEyeZ = rows.getDouble(9); liveAngle = angleProfile(rows.getDouble(10));
            liveHealth = rows.getInt(11); liveArmor = rows.getInt(12);
            liveBlueKey = rows.getInt(13); liveYellowKey = rows.getInt(14);
            liveRedKey = rows.getInt(15);
            if ("SHOTGUN".equals(weapon)) liveAmmo = rows.getInt(17);
            else if ("ROCKET_LAUNCHER".equals(weapon)) liveAmmo = rows.getInt(18);
            else if ("PLASMA_RIFLE".equals(weapon)) liveAmmo = rows.getInt(19);
            else liveAmmo = rows.getInt(16);
            Integer selected = spriteAssetByName.get(weaponPatch(weapon));
            require(selected != null, "selected weapon patch missing");
            weaponAsset = selected;
          } else if (kind == 1) {
            require(id >= 0 && id < sectorFloor.length, "live sector id out of range");
            sectorFloor[id] = rows.getDouble(5); sectorCeiling[id] = rows.getDouble(6);
            sectorLight[id] = rows.getInt(7);
            sectorLightBand[id] = Math.max(0, Math.min(31, (255 - sectorLight[id]) / 8));
            sectors++;
          } else if (kind == 2) {
            ensureMobjCapacity(mobjs + 1);
            mobjId[mobjs] = id; mobjState[mobjs] = -1;
            Integer state = stateIndexByName.get(rows.getString(3));
            if (state != null) mobjState[mobjs] = state;
            mobjX[mobjs] = rows.getDouble(5); mobjY[mobjs] = rows.getDouble(6);
            mobjZ[mobjs] = rows.getDouble(7); mobjAngle[mobjs] = rows.getDouble(8);
            mobjs++;
          } else {
            if (audioCount++ != 0) audio.append(',');
            String asset = rows.getString(3);
            require(asset.matches("[A-Z0-9_]+"), "invalid audio asset name");
            audio.append('[').append(liveTic).append(',').append(id).append(",\"")
                .append(asset).append("\",").append(rows.getInt(5)).append(',')
                .append(rows.getInt(6)).append(']');
          }
        }
      }
    }
    require(playerRows == 1, "render session not found or duplicated");
    require(sectors == sectorFloor.length, "live sector snapshot incomplete");
    mobjCount = mobjs; liveAudio = audio.append(']').toString();
    prepareExactSegmentRelatives();
    for (int id = 0; id < segTotal; id++) {
      int left = leftSector[id], right = rightSector[id];
      segSolid[id] = (byte) (left < 0 || right < 0 ||
          Math.min(sectorCeiling[left], sectorCeiling[right]) <=
          Math.max(sectorFloor[left], sectorFloor[right]) ? 1 : 0);
    }
  }

  private static byte[] snapshotBytes(Blob snapshot) throws Exception {
    require(snapshot!=null&&snapshot.length()<=32767,"dynamic snapshot missing or too large");
    byte[] bytes=new byte[(int)snapshot.length()];int offset=0;
    try(InputStream in=snapshot.getBinaryStream()) {
      while(offset<bytes.length){int count=in.read(bytes,offset,bytes.length-offset);
        require(count>0,"dynamic snapshot short read");offset+=count;}
    }
    return bytes;
  }

  private static void decodeDynamicSnapshot(Blob snapshot,String expectedSession) throws Exception {
    // A snapshot starts a new retained/recovery image. Switch state is then
    // supplied by the first complete DMSV trailer; never inherit it from a
    // prior worker generation while waiting for that staged image.
    if(lineSwitchOn!=null){Arrays.fill(lineSwitchOn,(byte)0);Arrays.fill(lineSwitchTimer,-1);}
    anySwitchOn=false;
    byte[] encoded=snapshotBytes(snapshot);
    if(encoded.length>0&&encoded[0]=='{'){
      require(expectedSession==null,"session-fenced renderer requires binary snapshot");
      decodeJsonSnapshot(new JsonInput(encoded));return;}
    KernelInput in=new KernelInput(encoded);
    int magic=in.readInt();
    if(magic==0x44525332){String owner=readString(in);
      require(owner.matches("[0-9a-f]{32}"),"dynamic snapshot owner invalid");
      if(expectedSession!=null)require(owner.equals(expectedSession),"dynamic snapshot session fence");}
    else require(magic==0x44525331&&expectedSession==null,"dynamic snapshot magic mismatch");
    int sectors=0,mobjs=0,playerRows=0,audioCount=0;
    StringBuilder audio=new StringBuilder("[");
    while(!in.exhausted()) {
      int kind=in.readInt();
      if(kind==4) break;
      if(kind==0) {
        playerRows++;liveTic=in.readInt();liveMode=readString(in);
        String weapon=readString(in);liveComplete=in.readInt();livePaused=in.readInt();
        liveExactCameraX=new BigDecimal(readString(in));
        liveExactCameraY=new BigDecimal(readString(in));
        liveCameraX=liveExactCameraX.doubleValue();liveCameraY=liveExactCameraY.doubleValue();
        cameraEyeZ=in.readDouble();liveAngle=angleProfile(in.readDouble());
        liveHealth=in.readInt();liveArmor=in.readInt();liveBlueKey=in.readInt();
        liveYellowKey=in.readInt();liveRedKey=in.readInt();
        int bullets=in.readInt(),shells=in.readInt(),rockets=in.readInt(),cells=in.readInt();
        if("SHOTGUN".equals(weapon))liveAmmo=shells;
        else if("ROCKET_LAUNCHER".equals(weapon))liveAmmo=rockets;
        else if("PLASMA_RIFLE".equals(weapon))liveAmmo=cells;else liveAmmo=bullets;
        Integer selected=spriteAssetByName.get(weaponPatch(weapon));
        require(selected!=null,"selected weapon patch missing");weaponAsset=selected;
      } else if(kind==1) {
        int id=in.readInt();require(id>=0&&id<sectorFloor.length,"snapshot sector invalid");
        sectorFloor[id]=in.readDouble();sectorCeiling[id]=in.readDouble();
        sectorLight[id]=in.readInt();
        sectorLightBand[id]=Math.max(0,Math.min(31,(255-sectorLight[id])/8));sectors++;
      } else if(kind==2) {
        ensureMobjCapacity(mobjs+1);mobjId[mobjs]=in.readInt();
        Integer state=stateIndexByName.get(readString(in));mobjState[mobjs]=state==null?-1:state;
        mobjX[mobjs]=in.readDouble();mobjY[mobjs]=in.readDouble();mobjZ[mobjs]=in.readDouble();
        mobjAngle[mobjs]=in.readDouble();mobjs++;
      } else if(kind==3) {
        int ordinal=in.readInt();String asset=readString(in);
        require(asset.matches("[A-Z0-9_]+"),"invalid audio asset name");
        if(audioCount++!=0)audio.append(',');
        audio.append('[').append(liveTic).append(',').append(ordinal).append(",\"")
            .append(asset).append("\",").append(in.readInt()).append(',')
            .append(in.readInt()).append(']');
      } else throw new IllegalStateException("dynamic snapshot record invalid");
    }
    require(in.exhausted(),"dynamic snapshot trailing bytes");
    require(playerRows==1&&sectors==sectorFloor.length,"dynamic snapshot incomplete");
    mobjCount=mobjs;liveAudio=audio.append(']').toString();prepareExactSegmentRelatives();
    for(int id=0;id<segTotal;id++) {
      int left=leftSector[id],right=rightSector[id];
      segSolid[id]=(byte)(left<0||right<0||
          Math.min(sectorCeiling[left],sectorCeiling[right])<=
          Math.max(sectorFloor[left],sectorFloor[right])?1:0);
    }
  }

  private static int retainedMobjIndex(int id) {
    for(int index=0;index<mobjCount;index++)if(mobjId[index]==id)return index;
    return -1;
  }

  private static void recomputeSegSolidity(){
    for(int id=0;id<segTotal;id++){int left=leftSector[id],right=rightSector[id];
      segSolid[id]=(byte)(left<0||right<0||Math.min(sectorCeiling[left],sectorCeiling[right])<=
        Math.max(sectorFloor[left],sectorFloor[right])?1:0);}
  }

  private static void refreshLiveGeometry() {
    prepareExactSegmentRelatives();recomputeSegSolidity();
  }

  private static void decodeRetainedDelta(Blob delta,String expectedSession) throws Exception {
    byte[] encoded=snapshotBytes(delta);KernelInput in=new KernelInput(encoded);
    require(in.readInt()==0x44524431,"retained delta magic mismatch");
    String owner=readString(in);require(owner.equals(expectedSession),"retained delta session fence");
    int playerRows=0,audioCount=0;StringBuilder audio=new StringBuilder("[");
    while(!in.exhausted()){
      int kind=in.readInt();if(kind==4)break;
      if(kind==0){playerRows++;liveTic=in.readInt();liveMode=readString(in);
        String weapon=readString(in);liveComplete=in.readInt();livePaused=in.readInt();
        liveExactCameraX=new BigDecimal(readString(in));liveExactCameraY=new BigDecimal(readString(in));
        liveCameraX=liveExactCameraX.doubleValue();liveCameraY=liveExactCameraY.doubleValue();
        cameraEyeZ=in.readDouble();liveAngle=angleProfile(in.readDouble());
        liveHealth=in.readInt();liveArmor=in.readInt();liveBlueKey=in.readInt();
        liveYellowKey=in.readInt();liveRedKey=in.readInt();
        int bullets=in.readInt(),shells=in.readInt(),rockets=in.readInt(),cells=in.readInt();
        liveAmmo="SHOTGUN".equals(weapon)?shells:"ROCKET_LAUNCHER".equals(weapon)?rockets:
          "PLASMA_RIFLE".equals(weapon)?cells:bullets;
        Integer selected=spriteAssetByName.get(weaponPatch(weapon));
        require(selected!=null,"selected weapon patch missing");weaponAsset=selected;
      }else if(kind==1){int id=in.readInt();require(id>=0&&id<sectorFloor.length,
          "retained sector invalid");sectorFloor[id]=in.readDouble();
        sectorCeiling[id]=in.readDouble();sectorLight[id]=in.readInt();
        sectorLightBand[id]=Math.max(0,Math.min(31,(255-sectorLight[id])/8));
      }else if(kind==2){int id=in.readInt();int index=retainedMobjIndex(id);
        if(index<0){ensureMobjCapacity(mobjCount+1);index=mobjCount++;mobjId[index]=id;}
        Integer state=stateIndexByName.get(readString(in));mobjState[index]=state==null?-1:state;
        mobjX[index]=in.readDouble();mobjY[index]=in.readDouble();mobjZ[index]=in.readDouble();
        mobjAngle[index]=in.readDouble();
      }else if(kind==3){int ordinal=in.readInt();String asset=readString(in);
        require(asset.matches("[A-Z0-9_]+"),"invalid retained audio asset");
        if(audioCount++!=0)audio.append(',');audio.append('[').append(liveTic).append(',')
          .append(ordinal).append(",\"").append(asset).append("\",").append(in.readInt())
          .append(',').append(in.readInt()).append(']');
      }else if(kind==5){int id=in.readInt();int index=retainedMobjIndex(id);
        if(index>=0){int last=--mobjCount;mobjId[index]=mobjId[last];mobjState[index]=mobjState[last];
          mobjX[index]=mobjX[last];mobjY[index]=mobjY[last];mobjZ[index]=mobjZ[last];
          mobjAngle[index]=mobjAngle[last];}
      }else throw new IllegalStateException("retained delta record invalid");
    }
    require(in.exhausted()&&playerRows==1,"retained delta incomplete");
    liveAudio=audio.append(']').toString();refreshLiveGeometry();
  }

  private static void ensureDticScratch(int actors,int spawns){
    if(dticActorId.length<actors){int n=Math.max(actors,Math.max(64,dticActorId.length*2));
      dticActorId=new int[n];dticActorIndex=new int[n];dticActorState=new int[n];
      dticActorTarget=new int[n];
      dticActorX=new double[n];dticActorY=new double[n];dticOldState=new int[n];
      dticOldX=new double[n];dticOldY=new double[n];directOldZ=new double[n];}
    if(dticSpawnId.length<spawns){int n=Math.max(spawns,Math.max(16,dticSpawnId.length*2));
      dticSpawnId=new int[n];dticSpawnIndex=new int[n];dticSpawnState=new int[n];
      dticSpawnTarget=new int[n];dticSpawnTracer=new int[n];dticSpawnOwner=new int[n];
      dticSpawnX=new double[n];dticSpawnY=new double[n];dticSpawnZ=new double[n];}
  }

  private static double readDticNumber(KernelInput in)throws Exception{
    int length=in.readUnsignedByte();require(length>=1&&length<=22,"DTIC NUMBER length invalid");
    byte[] raw=in.readBytes(length);NUMBER number=new NUMBER(raw);
    require(Arrays.equals(raw,number.toBytes()),"DTIC NUMBER is not canonical");
    for(int pad=length;pad<22;pad++)require(in.readUnsignedByte()==0,"DTIC NUMBER padding invalid");
    double value=number.doubleValue();require(Double.isFinite(value),"DTIC NUMBER is not finite");return value;
  }

  private static String readDticString(KernelInput in)throws Exception{
    int length=in.readUnsignedShort();if(length==65535)return null;
    byte[] raw=in.readBytes(length);CharBuffer decoded=StandardCharsets.UTF_8.newDecoder()
        .onMalformedInput(CodingErrorAction.REPORT).onUnmappableCharacter(CodingErrorAction.REPORT)
        .decode(ByteBuffer.wrap(raw));String value=decoded.toString();
    require(Arrays.equals(raw,value.getBytes(StandardCharsets.UTF_8)),"DTIC text is not canonical UTF-8");
    return value;
  }

  private static boolean dticReference(int id,int actors,int spawns){
    if(id<0)return id==-1;for(int i=0;i<actors;i++)if(dticActorId[i]==id)return true;
    for(int i=0;i<spawns;i++)if(dticSpawnId[i]==id)return true;return retainedMobjIndex(id)>=0;
  }

  /** Apply the unified owner's actor-only DUOP/DTIC v1 result without a SQL read. */
  private static void decodeRetainedDtic(Blob delta)throws Exception{
    byte[] encoded=snapshotBytes(delta);KernelInput in=new KernelInput(encoded);
    require(in.readInt()==0x44554f50,"DTIC wrapper magic mismatch");
    require(in.readUnsignedByte()==1&&in.readUnsignedByte()==0&&in.readUnsignedByte()==4&&
        in.readUnsignedByte()==0,"DTIC wrapper header invalid");
    int childLength=in.readInt();require(childLength==in.remaining()&&childLength>=60,
        "DTIC wrapper length invalid");
    require(in.readInt()==0x44544943,"DTIC magic mismatch");
    require(in.readUnsignedByte()==1&&in.readUnsignedByte()==0,"DTIC version invalid");
    int actors=in.readUnsignedShort(),spawns=in.readUnsignedShort(),events=in.readUnsignedShort();
    int draws=in.readUnsignedShort();
    require(in.readUnsignedShort()==0,"DTIC claims unsupported player/sector extension");
    int rng=in.readInt();
    int playerHealth=in.readInt(),playerArmor=in.readInt(),playerAlive=in.readInt();
    int killCount=in.readInt(),nextMobj=in.readInt(),nextEvent=in.readInt();
    long nextTic=in.readLong(),nextSeq=in.readLong();
    require(actors<=4096&&spawns<=1024&&events<=8192&&draws<=65535&&rng>=0&&rng<=255&&
        killCount>=0&&nextMobj>=0&&nextEvent>=0&&nextTic<=Integer.MAX_VALUE&&
        nextTic==((long)liveTic)+1&&nextSeq>=0&&
        (retainedDticSeq<0||nextSeq==retainedDticSeq+1),"DTIC frontier/count invalid");
    require(playerHealth==liveHealth&&playerArmor==liveArmor&&
        playerAlive==(("dead".equals(liveMode)||liveHealth==0)?0:1),
        "DTIC claims unsupported player change");
    ensureDticScratch(actors,spawns);
    int priorActorId=-1;
    for(int actor=0;actor<actors;actor++){
      int id=in.readInt(),seen=in.readInt(),cooldown=in.readInt(),state=in.readInt();
      int tics=in.readInt(),death=in.readInt(),awake=in.readInt(),flags=in.readInt();
      int target=in.readInt(),direction=in.readInt();double x=readDticNumber(in),y=readDticNumber(in);
      int sector=in.readInt();
      require(id>priorActorId&&seen>=-1&&cooldown>=0&&state>=0&&state<catalogStateCount&&
          tics>=-1&&(death==0||death==1)&&(awake==0||awake==1)&&flags>=0&&target>=-1&&
          direction>=-1&&direction<=7&&sector>=0&&sector<sectorFloor.length,"DTIC actor invalid/order");
      priorActorId=id;
      int index=retainedMobjIndex(id);require(index>=0,"DTIC actor missing from retained scene");
      dticActorId[actor]=id;dticActorIndex[actor]=index;dticActorState[actor]=state;
      dticActorTarget[actor]=target;dticActorX[actor]=x;dticActorY[actor]=y;
    }
    int existingSpawns=0;
    int priorSpawnId=-1;
    for(int spawn=0;spawn<spawns;spawn++){
      int id=in.readInt(),thing=in.readInt(),state=in.readInt(),tics=in.readInt();
      double x=readDticNumber(in),y=readDticNumber(in),z=readDticNumber(in);
      readDticNumber(in);readDticNumber(in);readDticNumber(in);double radius=readDticNumber(in);
      double height=readDticNumber(in);int health=in.readInt(),flags=in.readInt(),target=in.readInt();
      int tracer=in.readInt(),reaction=in.readInt(),spawnThing=in.readInt(),owner=in.readInt();
      int exploded=in.readInt(),sector=in.readInt();String kind=readDticString(in);
      require(id==nextMobj-spawns+spawn&&id>priorSpawnId&&thing>=0&&state>=0&&
          state<catalogStateCount&&tics>=-1&&
          radius>=0&&height>=0&&health>=0&&flags>=0&&target>=-1&&tracer>=-1&&reaction>=0&&
          spawnThing>=-1&&owner>=-1&&(exploded==0||exploded==1)&&sector>=0&&sector<sectorFloor.length&&
          (kind==null||kind.matches("[A-Z0-9_]+")),"DTIC spawn invalid/order");
      priorSpawnId=id;
      int index=retainedMobjIndex(id);if(index>=0)existingSpawns++;
      dticSpawnId[spawn]=id;dticSpawnIndex[spawn]=index;dticSpawnState[spawn]=state;
      dticSpawnTarget[spawn]=target;dticSpawnTracer[spawn]=tracer;dticSpawnOwner[spawn]=owner;
      dticSpawnX[spawn]=x;dticSpawnY[spawn]=y;dticSpawnZ[spawn]=z;
    }
    for(int actor=0;actor<actors;actor++)require(dticReference(dticActorTarget[actor],actors,spawns),
        "DTIC actor target reference invalid");
    for(int spawn=0;spawn<spawns;spawn++)require(dticReference(dticSpawnTarget[spawn],actors,spawns)&&
        dticReference(dticSpawnTracer[spawn],actors,spawns)&&dticReference(dticSpawnOwner[spawn],actors,spawns),
        "DTIC spawn reference invalid");
    int priorOrdinal=-1;
    for(int event=0;event<events;event++){
      int ordinal=in.readInt();require((priorOrdinal<0||ordinal==priorOrdinal+1)&&ordinal<nextEvent,
          "DTIC event order/frontier");
      priorOrdinal=ordinal;int type=in.readInt(),actor=in.readInt(),target=in.readInt();
      require(type>=1&&type<=7&&actor>=0&&dticReference(actor,actors,spawns)&&
          dticReference(target,actors,spawns),"DTIC event domain/reference invalid");
      int present=in.readUnsignedByte();
      require(present==0||present==1,"DTIC event NUMBER presence invalid");
      if(present==1)readDticNumber(in);else for(int slot=0;slot<23;slot++)
        require(in.readUnsignedByte()==0,"DTIC null NUMBER padding invalid");
      readDticString(in);
    }
    require(events==0||nextEvent==priorOrdinal+1,"DTIC event frontier invalid");
    require(in.exhausted(),"DTIC trailing bytes");
    require(existingSpawns==0||existingSpawns==spawns,"DTIC partial spawn replay");
    if(existingSpawns==spawns)for(int spawn=0;spawn<spawns;spawn++){
      int index=dticSpawnIndex[spawn];require(mobjState[index]==dticSpawnState[spawn]&&
          Double.compare(mobjX[index],dticSpawnX[spawn])==0&&
          Double.compare(mobjY[index],dticSpawnY[spawn])==0&&
          Double.compare(mobjZ[index],dticSpawnZ[spawn])==0&&Double.compare(mobjAngle[index],0.0)==0,
          "DTIC conflicting spawn replay");
    }
    ensureMobjCapacity(mobjCount+(existingSpawns==0?spawns:0));
    dticPriorMobjCount=mobjCount;dticPriorLiveTic=liveTic;dticPriorSeq=retainedDticSeq;
    dticAppliedActors=actors;for(int actor=0;actor<actors;actor++){int index=dticActorIndex[actor];
      dticOldState[actor]=mobjState[index];dticOldX[actor]=mobjX[index];dticOldY[actor]=mobjY[index];}
    dticApplied=true;
    for(int actor=0;actor<actors;actor++){int index=dticActorIndex[actor];
      mobjState[index]=dticActorState[actor];mobjX[index]=dticActorX[actor];mobjY[index]=dticActorY[actor];}
    if(existingSpawns==0)for(int spawn=0;spawn<spawns;spawn++){
      int index=mobjCount++;mobjId[index]=dticSpawnId[spawn];mobjState[index]=dticSpawnState[spawn];
      mobjX[index]=dticSpawnX[spawn];mobjY[index]=dticSpawnY[spawn];mobjZ[index]=dticSpawnZ[spawn];
      mobjAngle[index]=0.0;
    }
    liveTic=(int)nextTic;retainedDticSeq=nextSeq;
  }

  private static void rollbackRetainedDtic(){if(!dticApplied)return;
    for(int actor=0;actor<dticAppliedActors;actor++){int index=dticActorIndex[actor];
      mobjState[index]=dticOldState[actor];mobjX[index]=dticOldX[actor];mobjY[index]=dticOldY[actor];}
    mobjCount=dticPriorMobjCount;liveTic=dticPriorLiveTic;retainedDticSeq=dticPriorSeq;dticApplied=false;
  }

  private static void rollbackDirectOwner(){if(!directApplied)return;
    for(int mobj=0;mobj<dticAppliedActors;mobj++){mobjId[mobj]=dticActorId[mobj];
      mobjState[mobj]=dticOldState[mobj];mobjX[mobj]=dticOldX[mobj];mobjY[mobj]=dticOldY[mobj];
      mobjZ[mobj]=directOldZ[mobj];mobjAngle[mobj]=dticActorX[mobj];}
    mobjCount=dticPriorMobjCount;liveTic=dticPriorLiveTic;retainedDticSeq=dticPriorSeq;
    liveCameraX=directOldCameraX;liveCameraY=directOldCameraY;cameraEyeZ=directOldEyeZ;
    liveExactCameraX=directOldExactX;liveExactCameraY=directOldExactY;liveAngle=directOldAngle;
    liveHealth=directOldHealth;liveArmor=directOldArmor;liveAmmo=directOldAmmo;
    weaponAsset=directOldWeaponAsset;liveComplete=directOldComplete;liveMode=directOldMode;
    for(int change=0;change<directSectorChangeCount;change++){int sector=directSectorId[change];
      sectorLight[sector]=directOldSectorLight[change];
      sectorLightBand[sector]=directOldSectorLightBand[change];}
    for(int change=0;change<directGeometryChangeCount;change++){int sector=directGeometryId[change];
      sectorFloor[sector]=directOldSectorFloor[change];sectorCeiling[sector]=directOldSectorCeiling[change];}
    for(int change=0;change<directSwitchChangeCount;change++){int line=directSwitchId[change];
      lineSwitchOn[line]=directOldSwitchOn[change];lineSwitchTimer[line]=directOldSwitchTimer[change];}
    anySwitchOn=directOldAnySwitchOn;
    if(directGeometryChangeCount>0)recomputeSegSolidity();
    directSectorChangeCount=0;directGeometryChangeCount=0;directSwitchChangeCount=0;
    prepareExactSegmentRelatives();directApplied=false;directRequest=null;
  }

  static String stageRetainedOwnerAndRender(String request,long nextTic,long nextSeq,
      NUMBER playerX,NUMBER playerY,NUMBER playerEyeZ,int playerAngleIndex,int playerHealth,
      int playerArmor,int playerAlive,String selectedWeapon,String weaponState,int selectedAmmo,
      int changeCount,int[] changeOp,int[] worldId,int[] worldState,
      NUMBER[] worldX,NUMBER[] worldY,NUMBER[] worldZ,NUMBER[] worldAngle,
      int sectorChangeCount,int[] sectorIds,int[] sectorLights,
      String stateSha,Blob payload)throws Exception{
    return stageRetainedOwnerAndRender(request,nextTic,nextSeq,playerX,playerY,playerEyeZ,
        playerAngleIndex,playerHealth,playerArmor,playerAlive,selectedWeapon,weaponState,
        selectedAmmo,
        changeCount,changeOp,worldId,worldState,worldX,worldY,worldZ,worldAngle,
        sectorChangeCount,sectorIds,sectorLights,null,stateSha,payload);
  }

  static String stageRetainedOwnerAndRender(String request,long nextTic,long nextSeq,
      NUMBER playerX,NUMBER playerY,NUMBER playerEyeZ,int playerAngleIndex,int playerHealth,
      int playerArmor,int playerAlive,String selectedWeapon,String weaponState,int selectedAmmo,
      int changeCount,int[] changeOp,int[] worldId,int[] worldState,
      NUMBER[] worldX,NUMBER[] worldY,NUMBER[] worldZ,NUMBER[] worldAngle,
      int sectorChangeCount,int[] sectorIds,int[] sectorLights,byte[] geometryPack,
      String stateSha,Blob payload)throws Exception{
    require(!directApplied&&!dticApplied&&request!=null&&request.matches("[0-9a-f]{32}")&&
        nextTic==((long)liveTic)+1&&nextTic<=Integer.MAX_VALUE&&nextSeq>=0&&
        (retainedDticSeq<0||nextSeq==retainedDticSeq+1)&&playerX!=null&&playerY!=null&&
        playerEyeZ!=null&&playerAngleIndex>=0&&playerAngleIndex<64&&playerHealth>=0&&
        playerArmor>=0&&(playerAlive==0||playerAlive==1)&&selectedWeapon!=null&&weaponState!=null&&selectedAmmo>=0&&
        spriteAssetByName.containsKey(weaponPatch(selectedWeapon))&&changeCount>=0&&changeCount<=4096&&
        changeOp!=null&&worldId!=null&&worldState!=null&&worldX!=null&&worldY!=null&&worldZ!=null&&
        changeOp.length>=changeCount&&worldId.length>=changeCount&&worldState.length>=changeCount&&
        worldX.length>=changeCount&&worldY.length>=changeCount&&worldZ.length>=changeCount&&
        worldAngle!=null&&worldAngle.length>=changeCount&&
        sectorChangeCount>=0&&sectorChangeCount<=sectorFloor.length&&sectorIds!=null&&
        sectorLights!=null&&sectorIds.length>=sectorChangeCount&&sectorLights.length>=sectorChangeCount&&
        stateSha!=null&&stateSha.matches("[0-9a-f]{64}")&&payload!=null,
        "direct retained owner input");
    long updateStarted=System.nanoTime();
    int priorWorld=-1;ensureDticScratch(mobjCount,0);
    for(int change=0;change<changeCount;change++){require(worldId[change]>priorWorld&&
          (changeOp[change]==0||changeOp[change]==1),"direct retained world order/op");priorWorld=worldId[change];
      if(changeOp[change]==1)require(worldState[change]>=0&&worldState[change]<catalogStateCount&&
          worldX[change]!=null&&worldY[change]!=null&&worldZ[change]!=null&&worldAngle[change]!=null,
          "direct retained world invalid");}
    int priorSector=-1;
    for(int change=0;change<sectorChangeCount;change++){
      require(sectorIds[change]>priorSector&&sectorIds[change]<sectorFloor.length&&
          sectorLights[change]>=0&&sectorLights[change]<=255,"direct retained sector order/range");
      priorSector=sectorIds[change];}
    int geometryCount=0,geometryComplete=-1;int[] geometryIds=null;int[] geometryFloors=null,geometryCeilings=null;
    int switchCount=0;int[] switchIds=null,switchTimers=null;byte[] switchValues=null;
    if(geometryPack!=null){KernelInput geometry=new KernelInput(geometryPack);
      require(geometry.readInt()==0x444d5747&&geometry.readUnsignedByte()==3&&
          geometry.readUnsignedByte()==0,"direct retained geometry header");
      geometryCount=geometry.readUnsignedShort();int geometryMobjs=geometry.readUnsignedShort();
      geometryComplete=geometry.readUnsignedByte();require(geometry.readUnsignedByte()==0&&
          (geometryComplete==0||geometryComplete==1)&&geometryCount<=sectorFloor.length,
          "direct retained geometry count/status");
      int playerZLength=geometry.readUnsignedByte();require(playerZLength>=1&&playerZLength<=22,
          "direct retained geometry player Z");for(int byteIndex=0;byteIndex<22;byteIndex++)geometry.readUnsignedByte();
      geometry.readInt();geometry.readInt();geometry.readInt();geometry.readInt();geometry.readInt();
      geometryIds=new int[geometryCount];geometryFloors=new int[geometryCount];geometryCeilings=new int[geometryCount];
      int prior=-1;for(int change=0;change<geometryCount;change++){int sector=geometry.readInt();
        int floor=geometry.readInt(),ceiling=geometry.readInt();geometry.readInt();geometry.readInt();
        require(sector>prior&&sector<sectorFloor.length&&
            ceiling>=floor,"direct retained geometry row");prior=sector;geometryIds[change]=sector;
        geometryFloors[change]=floor;geometryCeilings[change]=ceiling;}
      int priorMobj=-1;for(int change=0;change<geometryMobjs;change++){int id=geometry.readInt();
        int zLength=geometry.readUnsignedByte();require(zLength>=1&&zLength<=22,
          "direct retained geometry mobj Z");for(int byteIndex=0;byteIndex<22;byteIndex++)geometry.readUnsignedByte();
        require(id>priorMobj,"direct retained geometry mobj order");priorMobj=id;}
      // Optional DMSV/v1 complete switch image.  Keeping this as a strict
      // trailer preserves DMWG/v3 compatibility while the SQL owner rolls the
      // producer out.  Each row is line i32, on u8, timer i32, restore-name
      // u8+UTF-8.  The name is checked against immutable sidedef metadata so a
      // corrupt/mismatched SQL image cannot select an arbitrary asset.
      if(!geometry.exhausted()){
        require(geometry.readInt()==0x444d5356&&geometry.readUnsignedByte()==1&&
            geometry.readUnsignedByte()==1,"direct retained switch header");
        switchCount=geometry.readUnsignedShort();require(switchCount==mapLineCount,
            "direct retained switch completeness");
        switchIds=new int[switchCount];switchValues=new byte[switchCount];switchTimers=new int[switchCount];
        int priorLine=-1;for(int change=0;change<switchCount;change++){
          int line=geometry.readInt(),on=geometry.readUnsignedByte(),timer=geometry.readInt();
          int nameLength=geometry.readUnsignedByte();require(nameLength<=32,
              "direct retained switch texture length");
          String restore=new String(geometry.readBytes(nameLength),StandardCharsets.UTF_8);
          require(line>priorLine&&line>=0&&line<lineSwitchOn.length&&(on==0||on==1)&&
              ((on==1&&timer>=0)||(on==0&&timer==-1))&&switchRestoreMatches(line,restore),
              "direct retained switch row");
          priorLine=line;switchIds[change]=line;switchValues[change]=(byte)on;switchTimers[change]=timer;
        }
      }
      require(geometry.exhausted(),"direct retained geometry trailing bytes");}
    ensureMobjCapacity(mobjCount+changeCount);
    if(directSectorId.length<sectorChangeCount){directSectorId=new int[sectorChangeCount];
      directOldSectorLight=new int[sectorChangeCount];directOldSectorLightBand=new int[sectorChangeCount];}
    dticPriorMobjCount=mobjCount;dticPriorLiveTic=liveTic;dticPriorSeq=retainedDticSeq;
    directOldCameraX=liveCameraX;directOldCameraY=liveCameraY;directOldEyeZ=cameraEyeZ;
    directOldExactX=liveExactCameraX;directOldExactY=liveExactCameraY;directOldAngle=liveAngle;
    directOldHealth=liveHealth;directOldArmor=liveArmor;directOldAmmo=liveAmmo;
    directOldWeaponAsset=weaponAsset;directOldComplete=liveComplete;directOldMode=liveMode;dticAppliedActors=mobjCount;
    for(int mobj=0;mobj<mobjCount;mobj++){dticActorId[mobj]=mobjId[mobj];dticOldState[mobj]=mobjState[mobj];
      dticOldX[mobj]=mobjX[mobj];dticOldY[mobj]=mobjY[mobj];directOldZ[mobj]=mobjZ[mobj];
      dticActorX[mobj]=mobjAngle[mobj];}
    directSectorChangeCount=sectorChangeCount;
    for(int change=0;change<sectorChangeCount;change++){int sector=sectorIds[change];
      directSectorId[change]=sector;directOldSectorLight[change]=sectorLight[sector];
      directOldSectorLightBand[change]=sectorLightBand[sector];}
    if(directGeometryId.length<geometryCount){directGeometryId=new int[geometryCount];
      directOldSectorFloor=new double[geometryCount];directOldSectorCeiling=new double[geometryCount];}
    directGeometryChangeCount=geometryCount;
    for(int change=0;change<geometryCount;change++){int sector=geometryIds[change];directGeometryId[change]=sector;
      directOldSectorFloor[change]=sectorFloor[sector];directOldSectorCeiling[change]=sectorCeiling[sector];}
    if(directSwitchId.length<switchCount){directSwitchId=new int[switchCount];
      directOldSwitchOn=new byte[switchCount];directOldSwitchTimer=new int[switchCount];}
    directSwitchChangeCount=switchCount;
    directOldAnySwitchOn=anySwitchOn;
    for(int change=0;change<switchCount;change++){int line=switchIds[change];directSwitchId[change]=line;
      directOldSwitchOn[change]=lineSwitchOn[line];directOldSwitchTimer[change]=lineSwitchTimer[line];}
    directApplied=true;directRequest=request;
    try{liveExactCameraX=playerX.bigDecimalValue();liveExactCameraY=playerY.bigDecimalValue();
      liveCameraX=playerX.doubleValue();liveCameraY=playerY.doubleValue();cameraEyeZ=playerEyeZ.doubleValue();
      liveAngle=playerAngleIndex;liveHealth=playerHealth;liveArmor=playerArmor;liveMode=playerAlive==0?"dead":"game";
      liveAmmo=selectedAmmo;weaponAsset=weaponStateAsset(selectedWeapon,weaponState);
      if(geometryComplete>=0)liveComplete=geometryComplete;
      liveTic=(int)nextTic;retainedDticSeq=nextSeq;prepareExactSegmentRelatives();
      for(int change=0;change<changeCount;change++){int index=retainedMobjIndex(worldId[change]);
        if(changeOp[change]==0){require(index>=0,"direct retained remove missing");int last=--mobjCount;
          mobjId[index]=mobjId[last];mobjState[index]=mobjState[last];mobjX[index]=mobjX[last];
          mobjY[index]=mobjY[last];mobjZ[index]=mobjZ[last];mobjAngle[index]=mobjAngle[last];
        }else{if(index<0){index=mobjCount++;mobjId[index]=worldId[change];}
          mobjState[index]=worldState[change];mobjX[index]=worldX[change].doubleValue();
          mobjY[index]=worldY[change].doubleValue();mobjZ[index]=worldZ[change].doubleValue();
          mobjAngle[index]=worldAngle[change].doubleValue();}}
      for(int change=0;change<sectorChangeCount;change++){int sector=sectorIds[change];
        sectorLight[sector]=sectorLights[change];
        sectorLightBand[sector]=Math.max(0,Math.min(31,(255-sectorLights[change])/8));}
      for(int change=0;change<geometryCount;change++){int sector=geometryIds[change];
        sectorFloor[sector]=geometryFloors[change];sectorCeiling[sector]=geometryCeilings[change];}
      if(geometryCount>0)recomputeSegSolidity();
      boolean nextAnySwitchOn=false;
      for(int change=0;change<switchCount;change++){int line=switchIds[change];
        lineSwitchOn[line]=switchValues[change];lineSwitchTimer[line]=switchTimers[change];
        nextAnySwitchOn|=switchValues[change]!=0;}
      if(switchCount>0)anySwitchOn=nextAnySwitchOn;
      lastRetainedUpdateNanos=System.nanoTime()-updateStarted;
      long started=System.nanoTime();traverseAndProject(liveCameraX,liveCameraY,liveAngle,false);
      lastRenderNanos=System.nanoTime()-started;started=System.nanoTime();encodePackedTicZeroPayload(stateSha);
      lastCodecNanos=System.nanoTime()-started;started=System.nanoTime();payload.truncate(0);
      int first=Math.min(32767,codecGzipLength);int written=payload.setBytes(1,codecGzip,0,first);
      if(codecGzipLength>first)written+=payload.setBytes(first+1,codecGzip,first,codecGzipLength-first);
      require(written==codecGzipLength,"short direct retained BLOB write");lastBlobNanos=System.nanoTime()-started;
      StringBuilder sha=new StringBuilder(64);for(byte value:codecDigest){sha.append((char)HEX[(value>>>4)&15]);
        sha.append((char)HEX[value&15]);}return sha.toString();
    }catch(Throwable failure){rollbackDirectOwner();throw failure;}
  }

  static void acceptRetainedOwner(String request){require(directApplied&&request!=null&&request.equals(directRequest),
      "direct retained accept fence");directSectorChangeCount=0;directGeometryChangeCount=0;
      directSwitchChangeCount=0;
      directApplied=false;directRequest=null;}
  static void discardRetainedOwner(String request){require(directApplied&&request!=null&&request.equals(directRequest),
      "direct retained discard fence");rollbackDirectOwner();}
  static boolean retainedOwnerPending(){return directApplied;}
  static long retainedLiveTic(){return liveTic;}
  static long retainedSequence(){return retainedDticSeq;}

  static void invalidateRetainedForRecovery(){
    if(directApplied)rollbackDirectOwner();
    if(dticApplied)rollbackRetainedDtic();
    directApplied=false;directRequest=null;dticApplied=false;retainedDticSeq=-1;
  }

  private static void verifyRendererStateMap(Connection connection,String expected)throws Exception{
    require(expected!=null&&expected.matches("[0-9a-f]{64}"),"renderer state-map SHA invalid");
    try(Statement statement=connection.createStatement();ResultSet rows=statement.executeQuery(
        "select json_arrayagg(json_array(state_id,tics,next_state_id,action_name,"+
        "sprite_prefix,sprite_frame,rotations null on null returning varchar2) "+
        "order by state_id returning clob) from doom_state_def")){
      require(rows.next(),"renderer state map missing");Clob value=rows.getClob(1);
      String text=value.getSubString(1,(int)value.length());value.free();byte[] digest=
          MessageDigest.getInstance("SHA-256").digest(text.getBytes(StandardCharsets.UTF_8));
      StringBuilder actual=new StringBuilder(64);for(byte item:digest){actual.append((char)HEX[(item>>>4)&15]);
        actual.append((char)HEX[item&15]);}require(expected.equals(actual.toString()),"renderer state-map SHA mismatch");
    }
    try(Statement statement=connection.createStatement();ResultSet rows=statement.executeQuery(
        "select state_id from doom_state_def order by state_id")){int index=0;while(rows.next()){
      Integer packed=stateIndexByName.get(rows.getString(1));require(packed!=null&&packed.intValue()==index,
          "renderer packed state order mismatch");index++;}require(index==catalogStateCount&&
          stateIndexByName.size()==catalogStateCount,"renderer packed state count mismatch");}
  }

  static void loadRetainedScene(String session,Blob snapshot) throws Exception {
    require(session!=null&&session.matches("[0-9a-f]{32}"),"invalid retained session");
    if(!databaseCacheLoaded){Connection internal=DriverManager.getConnection(
        "jdbc:default:connection:");loadKernelPack(internal);databaseCacheLoaded=true;}
    decodeDynamicSnapshot(snapshot,session);retainedDticSeq=-1;
  }

  static void loadRetainedScene(String session,String stateMapSha,Blob snapshot)throws Exception{
    require(session!=null&&session.matches("[0-9a-f]{32}"),"invalid retained session");
    Connection internal=DriverManager.getConnection("jdbc:default:connection:");
    if(!databaseCacheLoaded){loadKernelPack(internal);databaseCacheLoaded=true;}
    verifyRendererStateMap(internal,stateMapSha);decodeDynamicSnapshot(snapshot,session);retainedDticSeq=-1;
  }

  static void forceLoadRetainedScene(String session,String stateMapSha,long expectedTic,
      long expectedSeq,Blob snapshot)throws Exception{
    invalidateRetainedForRecovery();
    require(expectedTic>=0&&expectedTic<=Integer.MAX_VALUE&&expectedSeq>=0,
        "renderer recovery frontier");
    loadRetainedScene(session,stateMapSha,snapshot);
    require(liveTic==(int)expectedTic,"renderer recovery tic mismatch");
    retainedDticSeq=expectedSeq;
  }

  static String updateRetainedSceneAndRender(String session,Blob delta,String stateSha,
      Blob payload) throws Exception {
    require(payload!=null&&stateSha!=null&&stateSha.matches("[0-9a-f]{64}"),
        "retained render input");
    long started=System.nanoTime();decodeRetainedDelta(delta,session);
    lastRetainedUpdateNanos=System.nanoTime()-started;
    require("game".equals(liveMode)||"dead".equals(liveMode),"retained renderer mode");
    started=System.nanoTime();traverseAndProject(liveCameraX,liveCameraY,liveAngle,false);
    lastRenderNanos=System.nanoTime()-started;
    started=System.nanoTime();encodePackedTicZeroPayload(stateSha);
    lastCodecNanos=System.nanoTime()-started;
    started=System.nanoTime();payload.truncate(0);int first=Math.min(32767,codecGzipLength);
    int written=payload.setBytes(1,codecGzip,0,first);
    if(codecGzipLength>first)written+=payload.setBytes(first+1,codecGzip,first,
        codecGzipLength-first);require(written==codecGzipLength,"short retained BLOB write");
    lastBlobNanos=System.nanoTime()-started;StringBuilder sha=new StringBuilder(64);
    for(byte value:codecDigest){sha.append((char)HEX[(value>>>4)&15]);
      sha.append((char)HEX[value&15]);}return sha.toString();
  }

  static String updateRetainedTicAndRender(String session,Blob delta,String stateSha,
      Blob payload)throws Exception{
    require(session!=null&&session.matches("[0-9a-f]{32}")&&payload!=null&&stateSha!=null&&
        stateSha.matches("[0-9a-f]{64}"),"retained DTIC render input");
    try{long started=System.nanoTime();decodeRetainedDtic(delta);
      lastRetainedUpdateNanos=System.nanoTime()-started;
      require("game".equals(liveMode)||"dead".equals(liveMode),"retained DTIC renderer mode");
      started=System.nanoTime();traverseAndProject(liveCameraX,liveCameraY,liveAngle,false);
      lastRenderNanos=System.nanoTime()-started;
      started=System.nanoTime();encodePackedTicZeroPayload(stateSha);
      lastCodecNanos=System.nanoTime()-started;
      started=System.nanoTime();payload.truncate(0);int first=Math.min(32767,codecGzipLength);
      int written=payload.setBytes(1,codecGzip,0,first);
      if(codecGzipLength>first)written+=payload.setBytes(first+1,codecGzip,first,codecGzipLength-first);
      require(written==codecGzipLength,"short retained DTIC BLOB write");lastBlobNanos=System.nanoTime()-started;
      StringBuilder sha=new StringBuilder(64);for(byte value:codecDigest){sha.append((char)HEX[(value>>>4)&15]);
        sha.append((char)HEX[value&15]);}dticApplied=false;return sha.toString();
    }catch(Throwable failure){rollbackRetainedDtic();throw failure;}
  }

  private static final class JsonInput {
    private final byte[] bytes;private int offset;
    JsonInput(byte[] bytes){this.bytes=bytes;}
    void whitespace(){while(offset<bytes.length&&(bytes[offset]==' '||bytes[offset]=='\n'||
        bytes[offset]=='\r'||bytes[offset]=='\t'))offset++;}
    void expect(char value){whitespace();require(offset<bytes.length&&bytes[offset]==value,
        "dynamic JSON syntax mismatch");offset++;}
    boolean take(char value){whitespace();if(offset<bytes.length&&bytes[offset]==value){offset++;return true;}return false;}
    String string(){expect('"');StringBuilder value=new StringBuilder();
      while(offset<bytes.length){int next=bytes[offset++]&255;if(next=='"')return value.toString();
        require(next!='\\',"escaped dynamic JSON string unsupported");value.append((char)next);}
      throw new IllegalStateException("unterminated dynamic JSON string");}
    String number(){whitespace();int start=offset;
      while(offset<bytes.length){int c=bytes[offset]&255;
        if((c>='0'&&c<='9')||c=='-'||c=='+'||c=='.'||c=='e'||c=='E')offset++;else break;}
      require(offset>start,"dynamic JSON number missing");
      return new String(bytes,start,offset-start,StandardCharsets.US_ASCII);}
    int integer(){whitespace();boolean negative=offset<bytes.length&&bytes[offset]=='-';
      if(negative)offset++;long value=0;int digits=0;
      while(offset<bytes.length&&bytes[offset]>='0'&&bytes[offset]<='9'){
        value=value*10+(bytes[offset++]-'0');digits++;}
      require(digits>0&&value<=Integer.MAX_VALUE+(negative?1L:0L),"dynamic JSON integer invalid");
      return (int)(negative?-value:value);}
    double decimal(){whitespace();int start=offset;boolean simple=true;
      if(offset<bytes.length&&(bytes[offset]=='-'||bytes[offset]=='+'))offset++;
      int digits=0;long value=0;
      while(offset<bytes.length){int c=bytes[offset]&255;
        if(c>='0'&&c<='9'){if(value<=900719925474099L)value=value*10+(c-'0');digits++;offset++;}
        else{if(c=='.'||c=='e'||c=='E'||c=='+')simple=false;break;}}
      require(digits>0,"dynamic JSON decimal missing");
      if(simple)return bytes[start]=='-'?-value:value;
      offset=start;return Double.parseDouble(number());}
    BigDecimal exact(){return new BigDecimal(number());}
    boolean nullValue(){whitespace();if(offset+4<=bytes.length&&bytes[offset]=='n'&&bytes[offset+1]=='u'
        &&bytes[offset+2]=='l'&&bytes[offset+3]=='l'){offset+=4;return true;}return false;}
    boolean exhausted(){whitespace();return offset==bytes.length;}
  }

  private static void decodeJsonSnapshot(JsonInput in) {
    in.expect('{');require("p".equals(in.string()),"dynamic JSON player key mismatch");in.expect(':');
    in.expect('[');liveTic=in.integer();in.expect(',');liveMode=in.string();in.expect(',');
    String weapon=in.string();in.expect(',');liveComplete=in.integer();in.expect(',');
    livePaused=in.integer();in.expect(',');liveExactCameraX=in.exact();in.expect(',');
    liveExactCameraY=in.exact();liveCameraX=liveExactCameraX.doubleValue();
    liveCameraY=liveExactCameraY.doubleValue();in.expect(',');cameraEyeZ=in.decimal();
    in.expect(',');liveAngle=angleProfile(in.decimal());in.expect(',');liveHealth=in.integer();
    in.expect(',');liveArmor=in.integer();in.expect(',');liveBlueKey=in.integer();
    in.expect(',');liveYellowKey=in.integer();in.expect(',');liveRedKey=in.integer();
    in.expect(',');int bullets=in.integer();in.expect(',');int shells=in.integer();
    in.expect(',');int rockets=in.integer();in.expect(',');int cells=in.integer();in.expect(']');
    liveAmmo="SHOTGUN".equals(weapon)?shells:"ROCKET_LAUNCHER".equals(weapon)?rockets:
        "PLASMA_RIFLE".equals(weapon)?cells:bullets;
    Integer selected=spriteAssetByName.get(weaponPatch(weapon));
    require(selected!=null,"selected weapon patch missing");weaponAsset=selected;

    in.expect(',');require("s".equals(in.string()),"dynamic JSON sector key mismatch");in.expect(':');
    in.expect('[');int sectors=0;
    if(!in.take(']'))do{in.expect('[');int id=in.integer();in.expect(',');
      require(id>=0&&id<sectorFloor.length,"dynamic JSON sector invalid");
      sectorFloor[id]=in.decimal();in.expect(',');sectorCeiling[id]=in.decimal();in.expect(',');
      sectorLight[id]=in.integer();sectorLightBand[id]=Math.max(0,Math.min(31,(255-sectorLight[id])/8));
      sectors++;in.expect(']');}while(in.take(','));
    if(sectors>0)in.take(']');require(sectors==sectorFloor.length,"dynamic JSON sectors incomplete");

    in.expect(',');require("m".equals(in.string()),"dynamic JSON mobj key mismatch");in.expect(':');
    in.expect('[');int mobjs=0;
    if(!in.take(']'))do{in.expect('[');ensureMobjCapacity(mobjs+1);mobjId[mobjs]=in.integer();
      in.expect(',');Integer state=stateIndexByName.get(in.string());mobjState[mobjs]=state==null?-1:state;
      in.expect(',');mobjX[mobjs]=in.decimal();in.expect(',');mobjY[mobjs]=in.decimal();
      in.expect(',');mobjZ[mobjs]=in.decimal();in.expect(',');mobjAngle[mobjs]=in.decimal();
      mobjs++;in.expect(']');}while(in.take(','));
    if(mobjs>0)in.take(']');mobjCount=mobjs;

    in.expect(',');require("a".equals(in.string()),"dynamic JSON audio key mismatch");in.expect(':');
    StringBuilder audio=new StringBuilder("[");int audioCount=0;
    if(!in.nullValue()){in.expect('[');if(!in.take(']'))do{in.expect('[');int ordinal=in.integer();
      in.expect(',');String asset=in.string();require(asset.matches("[A-Z0-9_]+"),"invalid audio asset");
      in.expect(',');int volume=in.integer();in.expect(',');int separation=in.integer();in.expect(']');
      if(audioCount++!=0)audio.append(',');audio.append('[').append(liveTic).append(',')
        .append(ordinal).append(",\"").append(asset).append("\",").append(volume).append(',')
        .append(separation).append(']');}while(in.take(','));if(audioCount>0)in.take(']');}
    in.expect('}');require(in.exhausted(),"dynamic JSON trailing bytes");
    liveAudio=audio.append(']').toString();prepareExactSegmentRelatives();
    for(int id=0;id<segTotal;id++){int left=leftSector[id],right=rightSector[id];
      segSolid[id]=(byte)(left<0||right<0||Math.min(sectorCeiling[left],sectorCeiling[right])<=
        Math.max(sectorFloor[left],sectorFloor[right])?1:0);}
  }

  private static void loadPackedTexels(Connection connection, String kind,
      short[][] texels, int[] widths, int[] heights, int expected) throws Exception {
    try (PreparedStatement statement = connection.prepareStatement(
        "select format_version,element_count,encoded_bytes " +
        "from doom_renderer_asset_pack where asset_kind=?")) {
      statement.setString(1, kind);
      try (ResultSet rows = statement.executeQuery()) {
        require(rows.next() && rows.getInt(1) == 1 && rows.getInt(2) == expected,
            kind + " renderer pack missing or invalid");
        Blob blob = rows.getBlob(3);
        require(blob.length() == expected * 2L, kind + " renderer pack byte mismatch");
        int count = 0;
        try (InputStream raw = blob.getBinaryStream(); DataInputStream input = new DataInputStream(raw)) {
          for (int asset = 0; asset < texels.length; asset++) {
            int width = widths == null ? 64 : widths[asset];
            int height = heights == null ? 64 : heights[asset];
            for (int y = 0; y < height; y++) {
              for (int x = 0; x < width; x++) {
                texels[asset][x * height + y] = (short) (input.readUnsignedShort() - 1);
                count++;
              }
            }
          }
          require(input.read() == -1, kind + " renderer pack trailing bytes");
        }
        blob.free();
        require(count == expected, kind + " renderer pack element mismatch");
        require(!rows.next(), kind + " renderer pack duplicate");
      }
    }
  }

  private static void writeInts(DataOutputStream out, int[] values) throws Exception {
    out.writeInt(values.length);
    for (int value : values) out.writeInt(value);
  }

  private static int[] readInts(KernelInput in) {
    int[] values = new int[in.readInt()];
    for (int index = 0; index < values.length; index++) values[index] = in.readInt();
    return values;
  }

  private static void writeBytes(DataOutputStream out, byte[] values) throws Exception {
    out.writeInt(values.length); out.write(values);
  }

  private static byte[] readBytes(KernelInput in) {
    return in.readBytes(in.readInt());
  }

  private static void writeDoubles(DataOutputStream out, double[] values) throws Exception {
    out.writeInt(values.length);
    for (double value : values) out.writeDouble(value);
  }

  private static double[] readDoubles(KernelInput in) {
    double[] values = new double[in.readInt()];
    for (int index = 0; index < values.length; index++) values[index] = in.readDouble();
    return values;
  }

  private static void writeShorts(DataOutputStream out, short[] values) throws Exception {
    out.writeInt(values.length);
    for (short value : values) out.writeShort(value);
  }

  private static short[] readShorts(KernelInput in) {
    short[] values = new short[in.readInt()];
    for (int index = 0; index < values.length; index++) values[index] = in.readShort();
    return values;
  }

  private static void writeShortMatrix(DataOutputStream out, short[][] values) throws Exception {
    out.writeInt(values.length);
    for (short[] value : values) writeShorts(out, value);
  }

  private static short[][] readShortMatrix(KernelInput in) {
    short[][] values = new short[in.readInt()][];
    for (int index = 0; index < values.length; index++) values[index] = readShorts(in);
    return values;
  }

  private static void writeString(DataOutputStream out, String value) throws Exception {
    if (value == null) { out.writeInt(-1); return; }
    byte[] bytes = value.getBytes(StandardCharsets.UTF_8);
    out.writeInt(bytes.length); out.write(bytes);
  }

  private static String readString(KernelInput in) {
    int length = in.readInt();
    if (length < 0) return null;
    byte[] bytes = in.readBytes(length);
    return new String(bytes, StandardCharsets.UTF_8);
  }

  private static void writeStrings(DataOutputStream out, String[] values) throws Exception {
    out.writeInt(values.length);
    for (String value : values) writeString(out, value);
  }

  private static String[] readStrings(KernelInput in) {
    String[] values = new String[in.readInt()];
    for (int index = 0; index < values.length; index++) values[index] = readString(in);
    return values;
  }

  private static void writeStringIntMap(DataOutputStream out, Map<String, Integer> values)
      throws Exception {
    String[] keys = values.keySet().toArray(new String[0]); Arrays.sort(keys);
    out.writeInt(keys.length);
    for (String key : keys) { writeString(out, key); out.writeInt(values.get(key)); }
  }

  private static Map<String, Integer> readStringIntMap(KernelInput in) {
    Map<String, Integer> values = new HashMap<>(); int count = in.readInt();
    for (int index = 0; index < count; index++) values.put(readString(in), in.readInt());
    return values;
  }

  private static void writeStringIntArrayMap(DataOutputStream out, Map<String, int[]> values)
      throws Exception {
    String[] keys = values.keySet().toArray(new String[0]); Arrays.sort(keys);
    out.writeInt(keys.length);
    for (String key : keys) { writeString(out, key); writeInts(out, values.get(key)); }
  }

  private static Map<String, int[]> readStringIntArrayMap(KernelInput in) {
    Map<String, int[]> values = new HashMap<>(); int count = in.readInt();
    for (int index = 0; index < count; index++) values.put(readString(in), readInts(in));
    return values;
  }

  private static byte[] encodeKernelPack() throws Exception {
    ByteArrayOutputStream bytes = new ByteArrayOutputStream(6_000_000);
    try (DataOutputStream out = new DataOutputStream(bytes)) {
      out.writeInt(KERNEL_PACK_MAGIC); out.writeInt(KERNEL_PACK_VERSION);
      out.writeInt(nodeCount); out.writeInt(ssectorCount); out.writeInt(segTotal);
      out.writeDouble(farDistance); out.writeDouble(projectionK); out.writeInt(skyAsset);
      out.writeInt(catalogStateCount); out.writeInt(mobjCount);
      out.writeInt(uiStatusBarAsset); out.writeInt(uiPauseAsset); out.writeInt(weaponAsset);
      int[][] ints = {nodeX,nodeY,nodeDx,nodeDy,bboxTop,bboxBottom,bboxLeft,bboxRight,childId,
          firstSeg,segCount,segStartX,segStartY,segEndX,segEndY,segLineId,lineStartX,lineStartY,
          lineEndX,lineEndY,rightSector,leftSector,lineFlags,segOffset,rightXOffset,rightYOffset,
          leftXOffset,leftYOffset,sectorLight,sectorCeilingAsset,sectorFloorAsset,sectorLightBand,
          wallAssetWidth,wallAssetHeight,spriteAssetWidth,spriteAssetHeight,catalogAsset,
          catalogLeft,catalogTop,mobjId,mobjState,uiAssetWidth,uiAssetHeight,uiKeyAsset,uiDigitAsset};
      out.writeInt(ints.length); for (int[] values : ints) writeInts(out, values);
      byte[][] byteArrays = {childLeaf,segSolid,sectorCeilingSky,catalogFlip,catalogPresent};
      out.writeInt(byteArrays.length); for (byte[] values : byteArrays) writeBytes(out, values);
      double[][] doubles = {sectorFloor,sectorCeiling,camX,angleDegrees,directionX,directionY,
          planeX,planeY,rayXProfile,rayYProfile,mobjX,mobjY,mobjZ,mobjAngle};
      out.writeInt(doubles.length); for (double[] values : doubles) writeDoubles(out, values);
      String[][] strings = {rightUpper,rightLower,rightMiddle,leftUpper,leftLower,leftMiddle,
          sectorCeilingFlat,sectorFloorFlat};
      out.writeInt(strings.length); for (String[] values : strings) writeStrings(out, values);
      writeShorts(out,colormap);writeShortMatrix(out,wallAssetTexels);
      writeShortMatrix(out,flatAssetTexels);writeShortMatrix(out,spriteAssetTexels);
      writeShortMatrix(out,uiAssetTexels);
      writeStringIntMap(out,wallAssetByName); writeStringIntMap(out,flatAssetByName);
      writeStringIntMap(out,spriteAssetByName); writeStringIntMap(out,stateIndexByName);
      writeStringIntArrayMap(out,animationByAsset);
    }
    return bytes.toByteArray();
  }

  private static void allocateWorkBuffers() {
    segRelativeStartX = new double[segTotal]; segRelativeStartY = new double[segTotal];
    segRelativeEndX = new double[segTotal]; segRelativeEndY = new double[segTotal];
    segExactTNumerator = new double[segTotal]; segExactEpoch = new int[segTotal];
    facingSectorCache=new int[segTotal];oppositeSectorCache=new int[segTotal];
    rightFacingCache=new byte[segTotal];
    planeCeilingDistance = new double[sectorFloor.length * 200];
    planeFloorDistance = new double[sectorFloor.length * 200];
    visiblePlaneSector = new boolean[sectorFloor.length];
    activeSectorCeilingAsset=new int[sectorFloor.length];
    activeSectorFloorAsset=new int[sectorFloor.length];
    stackId = new int[nodeCount * 2 + 4]; stackLeaf = new byte[stackId.length];
    rawCandidates = new byte[segTotal * WIDTH]; visibleCandidates = new byte[segTotal * WIDTH];
    acceptedDepthCache = new double[segTotal * WIDTH];
    acceptedUCache = new double[segTotal * WIDTH];
    portalCandidates = new byte[segTotal * WIDTH]; projectedFirst = new int[segTotal];
    projectedLast = new int[segTotal]; nearestSolidDepth = new double[WIDTH];
    columnVisibleCount = new int[WIDTH];
    columnVisibleSeg = new int[WIDTH * MAX_VISIBLE_PER_COLUMN];
    columnVisibleDepth = new double[WIDTH * MAX_VISIBLE_PER_COLUMN];
    orderedSegs = new int[segTotal]; orderedDepths = new double[segTotal];
    orderedSegScratch=new int[MAX_VISIBLE_PER_COLUMN];
    orderedDepthScratch=new double[MAX_VISIBLE_PER_COLUMN];
    portalClipTop = new double[WIDTH]; portalClipBottom = new double[WIDTH];
    wallFrame = new short[WIDTH * 200]; wallOwned = new byte[wallFrame.length];
    wallColored = new byte[wallFrame.length]; intervalOffset = new int[WIDTH];
    intervalCount = new int[WIDTH]; intervalSector = new int[MAX_INTERVALS];
    intervalStart = new double[MAX_INTERVALS]; intervalEnd = new double[MAX_INTERVALS];
    intervalClipTop = new double[MAX_INTERVALS]; intervalClipBottom = new double[MAX_INTERVALS];
    presentationFrame = new short[wallFrame.length]; overlayPalette = new short[wallFrame.length];
    overlayDepth = new double[wallFrame.length]; overlayKind = new byte[wallFrame.length];
    overlaySource = new int[wallFrame.length]; overlayAssetX = new int[wallFrame.length];
    overlayAssetY = new int[wallFrame.length]; finalFrame = new short[wallFrame.length];
    buildExactGeometryCache();
  }

  private static final class KernelInput {
    private final byte[] bytes; private int offset;
    KernelInput(byte[] bytes) { this.bytes=bytes; }
    int readInt() {
      require(offset+4<=bytes.length,"renderer kernel pack truncated");
      int value=((bytes[offset]&255)<<24)|((bytes[offset+1]&255)<<16)|
          ((bytes[offset+2]&255)<<8)|(bytes[offset+3]&255); offset+=4; return value;
    }
    int readUnsignedByte(){require(offset<bytes.length,"renderer kernel pack truncated");return bytes[offset++]&255;}
    int readUnsignedShort(){require(offset+2<=bytes.length,"renderer kernel pack truncated");
      int value=((bytes[offset]&255)<<8)|(bytes[offset+1]&255);offset+=2;return value;}
    void skip(int length){require(length>=0&&offset+length<=bytes.length,"renderer kernel skip invalid");offset+=length;}
    int remaining(){return bytes.length-offset;}
    long readLong() { return ((long)readInt()<<32)|(readInt()&0xffffffffL); }
    double readDouble() { return Double.longBitsToDouble(readLong()); }
    short readShort() {
      require(offset+2<=bytes.length,"renderer kernel pack truncated");
      short value=(short)(((bytes[offset]&255)<<8)|(bytes[offset+1]&255)); offset+=2; return value;
    }
    byte[] readBytes(int length) {
      require(length>=0&&offset+length<=bytes.length,"renderer kernel byte length invalid");
      byte[] value=Arrays.copyOfRange(bytes,offset,offset+length); offset+=length; return value;
    }
    boolean exhausted() { return offset==bytes.length; }
  }

  private static void decodeKernelPack(KernelInput in) throws Exception {
    require(in.readInt() == KERNEL_PACK_MAGIC, "renderer kernel pack magic mismatch");
    require(in.readInt() == KERNEL_PACK_VERSION, "renderer kernel pack version mismatch");
    nodeCount=in.readInt(); ssectorCount=in.readInt(); segTotal=in.readInt();
    farDistance=in.readDouble(); projectionK=in.readDouble(); skyAsset=in.readInt();
    catalogStateCount=in.readInt(); mobjCount=in.readInt();
    uiStatusBarAsset=in.readInt(); uiPauseAsset=in.readInt(); weaponAsset=in.readInt();
    require(in.readInt()==45,"renderer kernel int-array count mismatch");
    nodeX=readInts(in);nodeY=readInts(in);nodeDx=readInts(in);nodeDy=readInts(in);
    bboxTop=readInts(in);bboxBottom=readInts(in);bboxLeft=readInts(in);bboxRight=readInts(in);
    childId=readInts(in);firstSeg=readInts(in);segCount=readInts(in);segStartX=readInts(in);
    segStartY=readInts(in);segEndX=readInts(in);segEndY=readInts(in);segLineId=readInts(in);
    lineStartX=readInts(in);lineStartY=readInts(in);lineEndX=readInts(in);lineEndY=readInts(in);
    rightSector=readInts(in);leftSector=readInts(in);lineFlags=readInts(in);segOffset=readInts(in);
    rightXOffset=readInts(in);rightYOffset=readInts(in);leftXOffset=readInts(in);
    leftYOffset=readInts(in);sectorLight=readInts(in);sectorCeilingAsset=readInts(in);
    sectorFloorAsset=readInts(in);sectorLightBand=readInts(in);wallAssetWidth=readInts(in);
    wallAssetHeight=readInts(in);spriteAssetWidth=readInts(in);spriteAssetHeight=readInts(in);
    catalogAsset=readInts(in);catalogLeft=readInts(in);catalogTop=readInts(in);
    mobjId=readInts(in);mobjState=readInts(in);uiAssetWidth=readInts(in);uiAssetHeight=readInts(in);
    int[] keys=readInts(in),digits=readInts(in);System.arraycopy(keys,0,uiKeyAsset,0,3);
    System.arraycopy(digits,0,uiDigitAsset,0,10);
    require(in.readInt()==5,"renderer kernel byte-array count mismatch");
    childLeaf=readBytes(in);segSolid=readBytes(in);sectorCeilingSky=readBytes(in);
    catalogFlip=readBytes(in);catalogPresent=readBytes(in);
    require(in.readInt()==14,"renderer kernel double-array count mismatch");
    sectorFloor=readDoubles(in);sectorCeiling=readDoubles(in);camX=readDoubles(in);
    angleDegrees=readDoubles(in);directionX=readDoubles(in);directionY=readDoubles(in);
    planeX=readDoubles(in);planeY=readDoubles(in);rayXProfile=readDoubles(in);
    rayYProfile=readDoubles(in);mobjX=readDoubles(in);mobjY=readDoubles(in);
    mobjZ=readDoubles(in);mobjAngle=readDoubles(in);
    require(in.readInt()==8,"renderer kernel string-array count mismatch");
    rightUpper=readStrings(in);rightLower=readStrings(in);rightMiddle=readStrings(in);
    leftUpper=readStrings(in);leftLower=readStrings(in);leftMiddle=readStrings(in);
    sectorCeilingFlat=readStrings(in);sectorFloorFlat=readStrings(in);
    colormap=readShorts(in);wallAssetTexels=readShortMatrix(in);flatAssetTexels=readShortMatrix(in);
    spriteAssetTexels=readShortMatrix(in);uiAssetTexels=readShortMatrix(in);
    wallAssetByName=readStringIntMap(in);flatAssetByName=readStringIntMap(in);
    spriteAssetByName=readStringIntMap(in);stateIndexByName=readStringIntMap(in);
    animationByAsset=readStringIntArrayMap(in);buildWallHotCaches();
    require(in.exhausted(),"renderer kernel pack trailing bytes");
    allocateWorkBuffers(); prepareExactSegmentRelatives();
  }

  private static void loadKernelPack(Connection connection) throws Exception {
    long started=System.nanoTime();
    if(codecSha256==null) codecSha256=MessageDigest.getInstance("SHA-256");
    try (Statement statement=connection.createStatement(); ResultSet rows=statement.executeQuery(
        "select encoded_bytes from doom_renderer_asset_pack where asset_kind='renderer_kernel' " +
        "and payload_sha256<>rpad('0',64,'0')")) {
      require(rows.next(),"renderer kernel pack missing"); Blob blob=rows.getBlob(1);
      require(blob.length()<=Integer.MAX_VALUE,"renderer kernel pack too large");
      byte[] bytes=new byte[(int)blob.length()]; int offset=0;
      try (InputStream in=blob.getBinaryStream()) {
        while(offset<bytes.length){int count=in.read(bytes,offset,bytes.length-offset);
          require(count>0,"renderer kernel pack short read");offset+=count;}
      }
      decodeKernelPack(new KernelInput(bytes));
      blob.free(); require(!rows.next(),"renderer kernel pack duplicate");
    }
    lastKernelLoadNanos=System.nanoTime()-started;
  }

  private static void buildKernelPackUnsafe() throws Exception {
    Connection connection=DriverManager.getConnection("jdbc:default:connection:");
    codecSha256=MessageDigest.getInstance("SHA-256"); load(connection);
    byte[] bytes=encodeKernelPack(); byte[] digest=codecSha256.digest(bytes);
    StringBuilder sha=new StringBuilder(64);
    for(byte value:digest){sha.append((char)HEX[(value>>>4)&15]);sha.append((char)HEX[value&15]);}
    try (Statement statement=connection.createStatement(); ResultSet rows=statement.executeQuery(
        "select encoded_bytes from doom_renderer_asset_pack where asset_kind='renderer_kernel' for update")) {
      require(rows.next(),"renderer kernel placeholder missing"); Blob blob=rows.getBlob(1); blob.truncate(0);
      for(int offset=0;offset<bytes.length;offset+=32767)
        blob.setBytes(offset+1,bytes,offset,Math.min(32767,bytes.length-offset));
      blob.free(); require(!rows.next(),"renderer kernel placeholder duplicate");
    }
    try (PreparedStatement statement=connection.prepareStatement(
        "update doom_renderer_asset_pack set element_count=?,payload_sha256=? where asset_kind='renderer_kernel'")) {
      statement.setInt(1,bytes.length); statement.setString(2,sha.toString());
      require(statement.executeUpdate()==1,"renderer kernel metadata update failed");
    }
    databaseCacheLoaded=true;
  }

  /** Catch-all OJVM entry point: no Java Throwable may escape into the session. */
  public static String buildKernelPack() {
    try {
      buildKernelPackUnsafe();
      lastDynamicFailure="";
      return "OK";
    } catch(Throwable failure) {
      databaseCacheLoaded=false;
      lastDynamicFailure=failure.getClass().getName()+":"+failure.getMessage();
      return "ERROR:"+failure.getClass().getName();
    }
  }

  public static String warmKernelPack(int iterations) {
    try {
      require(iterations >= 1 && iterations <= 200, "kernel warmup iterations out of range");
      Connection connection=DriverManager.getConnection("jdbc:default:connection:");
      long minimum=Long.MAX_VALUE,started=System.nanoTime();
      for(int iteration=0;iteration<iterations;iteration++) {
        loadKernelPack(connection); minimum=Math.min(minimum,lastKernelLoadNanos);
      }
      databaseCacheLoaded=true;
      return "OK iterations="+iterations+" total_ms="+
          ((System.nanoTime()-started)/1_000_000L)+" min_ms="+(minimum/1_000_000.0);
    } catch(Throwable failure) {
      databaseCacheLoaded=false;
      return "ERROR:"+failure.getClass().getName();
    }
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
    segRelativeStartX = new double[segTotal]; segRelativeStartY = new double[segTotal];
    segRelativeEndX = new double[segTotal]; segRelativeEndY = new double[segTotal];
    segExactTNumerator = new double[segTotal]; segExactEpoch = new int[segTotal];
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
    sectorFloor = new double[sectorCount]; sectorCeiling = new double[sectorCount];
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
        sectorFloor[id] = rows.getDouble(2); sectorCeiling[id] = rows.getDouble(3);
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
    loadPackedTexels(connection, "wall_texture", wallAssetTexels,
        wallAssetWidth, wallAssetHeight, 1_272_576);
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
    loadPackedTexels(connection, "flat", flatAssetTexels, null, null, 200_704);
    animationByAsset = new HashMap<>(); animationByGroup = new HashMap<>();
    Map<String, Integer> animationOrdinal = new HashMap<>();
    try (Statement statement = connection.createStatement();
         ResultSet rows = statement.executeQuery(
             "select asset_kind,group_name,frame_name,frame_ordinal,tic_period,frame_count " +
             "from doom_r2_animation_frames order by asset_kind,group_name,frame_ordinal")) {
      while (rows.next()) {
        String kind = rows.getString(1), group = kind + ":" + rows.getString(2);
        String name = rows.getString(3); int ordinal = rows.getInt(4);
        int[] packed = animationByGroup.get(group);
        if (packed == null) {
          packed = new int[2 + rows.getInt(6)]; packed[0] = rows.getInt(5);
          packed[1] = rows.getInt(6); animationByGroup.put(group, packed);
        }
        Integer asset = "flat".equals(kind) ? flatAssetByName.get(name) : wallAssetByName.get(name);
        require(asset != null && ordinal >= 0 && ordinal < packed[1], "animation asset invalid");
        packed[2 + ordinal] = asset;
        animationByAsset.put(kind + ":" + name, packed);
        animationOrdinal.put(kind + ":" + name, ordinal);
      }
    }
    for (Map.Entry<String, int[]> entry : animationByAsset.entrySet()) {
      int[] group = entry.getValue();
      int[] base = Arrays.copyOf(group, group.length + 1);
      base[group.length] = animationOrdinal.get(entry.getKey());
      entry.setValue(base);
    }
    buildWallHotCaches();
    Integer sky = wallAssetByName.get("SKY1");
    require(sky != null, "SKY1 asset missing");
    skyAsset = sky;
    sectorCeilingAsset = new int[sectorFloor.length];
    sectorFloorAsset = new int[sectorFloor.length];
    sectorLightBand = new int[sectorFloor.length];
    sectorCeilingSky = new byte[sectorFloor.length];
    for (int sector = 0; sector < sectorFloor.length; sector++) {
      Integer floorAsset = flatAssetByName.get(sectorFloorFlat[sector]);
      require(floorAsset != null, "floor flat missing");
      sectorFloorAsset[sector] = floorAsset;
      if ("F_SKY1".equals(sectorCeilingFlat[sector])) {
        sectorCeilingSky[sector] = 1;
        sectorCeilingAsset[sector] = -1;
      } else {
        Integer ceilingAsset = flatAssetByName.get(sectorCeilingFlat[sector]);
        require(ceilingAsset != null, "ceiling flat missing");
        sectorCeilingAsset[sector] = ceilingAsset;
      }
      sectorLightBand[sector] = Math.max(0, Math.min(31, (255 - sectorLight[sector]) / 8));
    }
    planeCeilingDistance = new double[sectorFloor.length * 200];
    planeFloorDistance = new double[sectorFloor.length * 200];
    visiblePlaneSector = new boolean[sectorFloor.length];
    int spriteAssetCount;
    try (Statement statement = connection.createStatement();
         ResultSet rows = statement.executeQuery(
             "select count(*) from doom_asset where asset_kind='sprite_patch'")) {
      rows.next(); spriteAssetCount = rows.getInt(1);
    }
    spriteAssetById = new HashMap<>(); spriteAssetByName = new HashMap<>();
    spriteAssetWidth = new int[spriteAssetCount]; spriteAssetHeight = new int[spriteAssetCount];
    spriteAssetTexels = new short[spriteAssetCount][];
    try (Statement statement = connection.createStatement();
         ResultSet rows = statement.executeQuery(
             "select asset_id,asset_name,width,height from doom_asset where asset_kind='sprite_patch' " +
             "order by asset_id")) {
      int index = 0;
      while (rows.next()) {
        spriteAssetById.put(rows.getInt(1), index);
        spriteAssetByName.put(rows.getString(2), index);
        spriteAssetWidth[index] = rows.getInt(3); spriteAssetHeight[index] = rows.getInt(4);
        spriteAssetTexels[index] = new short[spriteAssetWidth[index] * spriteAssetHeight[index]];
        index++;
      }
      require(index == spriteAssetCount, "sprite asset count mismatch");
    }
    loadPackedTexels(connection, "sprite_patch", spriteAssetTexels,
        spriteAssetWidth, spriteAssetHeight, 331_699);
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
    mobjId = new int[mobjCount]; mobjX = new double[mobjCount]; mobjY = new double[mobjCount];
    mobjZ = new double[mobjCount]; mobjAngle = new double[mobjCount]; mobjState = new int[mobjCount];
    try (Statement statement = connection.createStatement();
         ResultSet rows = statement.executeQuery(
             "select t.thing_id,t.x,t.y,0,t.angle,d.spawn_state_id from doom_map_thing t " +
             "join doom_thing_type_def d on d.thing_type=t.thing_type " +
             "where t.thing_type<>1 and d.spawn_state_id is not null order by t.thing_id")) {
      int index = 0;
      while (rows.next()) {
        mobjId[index] = rows.getInt(1); mobjX[index] = rows.getDouble(2);
        mobjY[index] = rows.getDouble(3); mobjZ[index] = rows.getDouble(4);
        mobjAngle[index] = rows.getDouble(5);
        mobjState[index] = stateIndexByName.get(rows.getString(6)); index++;
      }
      require(index == mobjCount, "mobj count mismatch");
    }
    int uiAssetCount;
    try (Statement statement = connection.createStatement();
         ResultSet rows = statement.executeQuery(
             "select count(*) from doom_asset where asset_kind='ui_patch'")) {
      rows.next(); uiAssetCount = rows.getInt(1);
    }
    uiAssetByName = new HashMap<>(); uiAssetWidth = new int[uiAssetCount];
    uiAssetHeight = new int[uiAssetCount]; uiAssetTexels = new short[uiAssetCount][];
    Map<Integer, Integer> uiAssetById = new HashMap<>();
    try (Statement statement = connection.createStatement();
         ResultSet rows = statement.executeQuery(
             "select asset_id,asset_name,width,height from doom_asset " +
             "where asset_kind='ui_patch' order by asset_id")) {
      int index = 0;
      while (rows.next()) {
        uiAssetById.put(rows.getInt(1), index); uiAssetByName.put(rows.getString(2), index);
        uiAssetWidth[index] = rows.getInt(3); uiAssetHeight[index] = rows.getInt(4);
        uiAssetTexels[index] = new short[uiAssetWidth[index] * uiAssetHeight[index]]; index++;
      }
      require(index == uiAssetCount, "UI asset count mismatch");
    }
    loadPackedTexels(connection, "ui_patch", uiAssetTexels,
        uiAssetWidth, uiAssetHeight, 173_170);
    Integer statusBar = uiAssetByName.get("STBAR");
    Integer pistol = spriteAssetByName.get("PISGA0");
    require(statusBar != null, "STBAR asset missing");
    require(pistol != null, "PISGA0 asset missing");
    uiStatusBarAsset = statusBar;
    weaponAsset = pistol;
    Integer pause = uiAssetByName.get("M_PAUSE");
    require(pause != null, "M_PAUSE asset missing");
    uiPauseAsset = pause;
    for (int key = 0; key < uiKeyAsset.length; key++) {
      Integer asset = uiAssetByName.get("STKEYS" + key);
      require(asset != null, "HUD key asset missing");
      uiKeyAsset[key] = asset;
    }
    for (int digit = 0; digit < uiDigitAsset.length; digit++) {
      Integer asset = uiAssetByName.get("STTNUM" + digit);
      require(asset != null, "HUD digit asset missing");
      uiDigitAsset[digit] = asset;
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
    allocateWorkBuffers();
    prepareExactSegmentRelatives();
  }

  private static int side(double px, double py, int id) {
    int dx = nodeDx[id], dy = nodeDy[id];
    if (dx == 0) return px <= nodeX[id] ? (dy > 0 ? 1 : 0) : (dy < 0 ? 1 : 0);
    if (dy == 0) return py <= nodeY[id] ? (dx < 0 ? 1 : 0) : (dx > 0 ? 1 : 0);
    double cross = (px - nodeX[id]) * dy - (py - nodeY[id]) * dx;
    return cross > 0 ? 0 : 1;
  }

  private static boolean bboxVisible(int offset, double px, double py,
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

  /**
   * Conservative front-to-back rejection.  A child is skipped only when every
   * screen column touched by its complete AABB already has a strictly nearer
   * dynamically-solid hit.  Near-plane crossings always fail open.
   */
  private static boolean bboxOccluded(int offset,double px,double py,double dirX,double dirY,
      double plnX,double plnY,double planeSquared){
    int left=bboxLeft[offset],right=bboxRight[offset],bottom=bboxBottom[offset],top=bboxTop[offset];
    double minProjection=Double.POSITIVE_INFINITY,maxProjection=Double.NEGATIVE_INFINITY;
    double minDepth=Double.POSITIVE_INFINITY;
    for(int i=0;i<4;i++){
      double relX=((i==0||i==3)?left:right)-px,relY=(i<2?bottom:top)-py;
      double depth=relX*dirX+relY*dirY;if(depth<=NEAR)return false;
      minDepth=Math.min(minDepth,depth);
      double projected=(relX*plnX+relY*plnY)/(depth*planeSquared);
      minProjection=Math.min(minProjection,projected);maxProjection=Math.max(maxProjection,projected);
    }
    int first=Arrays.binarySearch(camX,minProjection-PAD);
    first=first>=0?first:-first-1;
    int last=Arrays.binarySearch(camX,maxProjection+PAD);
    last=last>=0?last:-last-2;
    if(first<0)first=0;if(last>=WIDTH)last=WIDTH-1;if(first>last)return false;
    double strictLimit=minDepth-1e-9;
    for(int column=first;column<=last;column++)
      if(nearestSolidDepth[column]>strictLimit)return false;
    return true;
  }

  private static void projectSeg(int id, double px, double py, double dirX, double dirY,
      double plnX, double plnY, double planeSquared, boolean retainCandidates) {
    double ax = segRelativeStartX[id], ay = segRelativeStartY[id];
    double bx = segRelativeEndX[id], by = segRelativeEndY[id];
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
    if (retainCandidates) {
      int base = id * WIDTH;
      Arrays.fill(rawCandidates, base + first, base + last + 1, (byte) 1);
    }
  }

  private static int facingSector(int id, double px, double py) {
    return facingSectorCache[id];
  }

  private static int oppositeSector(int id, double px, double py) {
    return oppositeSectorCache[id];
  }

  private static boolean hitBefore(double leftDepth,int leftSeg,double rightDepth,int rightSeg){
    return leftDepth<rightDepth||(leftDepth==rightDepth&&
      (segLineId[leftSeg]<segLineId[rightSeg]||
       (segLineId[leftSeg]==segLineId[rightSeg]&&leftSeg<rightSeg)));
  }

  private static void sortVisibleHits(int count){
    orderedHitTotal+=count;if(count>12)largeSortColumns++;
    if(count<=12){
      for(int i=1;i<count;i++){int seg=orderedSegs[i];double depth=orderedDepths[i];int at=i;
        while(at>0&&hitBefore(depth,seg,orderedDepths[at-1],orderedSegs[at-1])){
          orderedDepths[at]=orderedDepths[at-1];orderedSegs[at]=orderedSegs[at-1];at--;}
        orderedDepths[at]=depth;orderedSegs[at]=seg;}
      return;
    }
    int[] sourceSeg=orderedSegs,targetSeg=orderedSegScratch;
    double[] sourceDepth=orderedDepths,targetDepth=orderedDepthScratch;
    for(int width=1;width<count;width<<=1){
      for(int left=0;left<count;left+=width<<1){int middle=Math.min(left+width,count);
        int end=Math.min(left+(width<<1),count),a=left,b=middle,out=left;
        while(a<middle&&b<end){boolean takeLeft=!hitBefore(sourceDepth[b],sourceSeg[b],
            sourceDepth[a],sourceSeg[a]);int from=takeLeft?a++:b++;
          targetDepth[out]=sourceDepth[from];targetSeg[out++]=sourceSeg[from];}
        while(a<middle){targetDepth[out]=sourceDepth[a];targetSeg[out++]=sourceSeg[a++];}
        while(b<end){targetDepth[out]=sourceDepth[b];targetSeg[out++]=sourceSeg[b++];}
      }
      int[] swapSeg=sourceSeg;sourceSeg=targetSeg;targetSeg=swapSeg;
      double[] swapDepth=sourceDepth;sourceDepth=targetDepth;targetDepth=swapDepth;
    }
    if(sourceSeg!=orderedSegs){System.arraycopy(sourceSeg,0,orderedSegs,0,count);
      System.arraycopy(sourceDepth,0,orderedDepths,0,count);}
  }

  private static void applyPortalWalk(double px, double py, double dirX, double dirY,
      double plnX, double plnY, boolean retainCandidates) {
    long stageStarted = System.nanoTime();
    resolveActiveWallAssets();
    activePortalPairs=0;largeSortColumns=orderedHitTotal=wallRowAttempts=planeRowAttempts=0;
    intervalTotal = 0;
    Arrays.fill(wallFrame, (short) -1); Arrays.fill(wallOwned, (byte) 0);
    Arrays.fill(wallColored, (byte) 0); Arrays.fill(intervalCount, 0);
    Arrays.fill(overlayDepth, Double.POSITIVE_INFINITY);
    Arrays.fill(overlayKind, (byte) 0);
    if (retainCandidates) Arrays.fill(portalCandidates, (byte) 0);
    lastPortalResetNanos=System.nanoTime()-stageStarted;
    lastPortalSortNanos=lastPortalWalkNanos=0;
    for (int column = 0; column < WIDTH; column++) {
      intervalOffset[column] = intervalTotal;
      portalClipTop[column] = 0.0; portalClipBottom[column] = 200.0;
      int orderedCount = 0;
      int base = column * MAX_VISIBLE_PER_COLUMN;
      for (int i = 0; i < columnVisibleCount[column]; i++) {
        int id = columnVisibleSeg[base + i];
        double depth = columnVisibleDepth[base + i];
        orderedDepths[orderedCount]=depth;orderedSegs[orderedCount++]=id;
      }
      long sortStarted=System.nanoTime();sortVisibleHits(orderedCount);
      lastPortalSortNanos+=System.nanoTime()-sortStarted;
      if (orderedCount == 0) continue;
      int currentSector = facingSector(orderedSegs[0], px, py);
      // SQL retains back-facing one-sided hits as solid diagnostics, but their
      // null facing sidedef makes the complete R2 ACTIVE walk empty. Preserve
      // that empty column instead of trying to sample a nonexistent texture.
      if (currentSector < 0) continue;
      double eyeZ = cameraEyeZ;
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
          double openingTop = Math.min(sectorCeiling[from], sectorCeiling[to]);
          double openingBottom = Math.max(sectorFloor[from], sectorFloor[to]);
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
    lastPortalNanos = System.nanoTime() - stageStarted;
    lastPortalWalkNanos=Math.max(0,lastPortalNanos-lastPortalResetNanos-lastPortalSortNanos);
    stageStarted = System.nanoTime();
    drawPlanes(px, py, dirX, dirY, plnX, plnY);
    lastPlaneNanos = System.nanoTime() - stageStarted;
    stageStarted = System.nanoTime();
    drawSprites(px, py, dirX, dirY);
    lastSpriteNanos = System.nanoTime() - stageStarted;
    stageStarted = System.nanoTime();
    System.arraycopy(wallFrame, 0, presentationFrame, 0, wallFrame.length);
    for (int index = 0; index < presentationFrame.length; index++)
      if (overlayKind[index] != 0) presentationFrame[index] = overlayPalette[index];
    composeLivePresentation();
    lastPresentationNanos = System.nanoTime() - stageStarted;
  }

  private static void blit(short[] texels,int width,int height,int left,int top) {
    for (int x = 0; x < width; x++) {
      int screenX = left + x;
      if (screenX < 0 || screenX >= WIDTH) continue;
      for (int y = 0; y < height; y++) {
        int screenY = top + y;
        if (screenY < 0 || screenY >= 200) continue;
        int raw = texels[x * height + y];
        if (raw >= 0) finalFrame[screenX * 200 + screenY] = (short) raw;
      }
    }
  }

  private static void blitUi(int asset, int left, int top) {
    blit(uiAssetTexels[asset],uiAssetWidth[asset],uiAssetHeight[asset],left,top);
  }

  private static void drawHudNumber(int value, int rightEdge) {
    blitUi(uiDigitAsset[(value / 100) % 10], rightEdge - 39, 171);
    blitUi(uiDigitAsset[(value / 10) % 10], rightEdge - 26, 171);
    blitUi(uiDigitAsset[value % 10], rightEdge - 13, 171);
  }

  private static void composeLivePresentation() {
    Arrays.fill(finalFrame, (short) 0);
    for (int column = 0; column < WIDTH; column++)
      System.arraycopy(presentationFrame, column * 200, finalFrame, column * 200, 168);
    blit(spriteAssetTexels[weaponAsset],spriteAssetWidth[weaponAsset],
        spriteAssetHeight[weaponAsset],(WIDTH-spriteAssetWidth[weaponAsset])/2,
        200-spriteAssetHeight[weaponAsset]);
    blitUi(uiStatusBarAsset, 0, 168);
    drawHudNumber(liveAmmo, 44);
    drawHudNumber(liveHealth, 90);
    drawHudNumber(liveArmor, 221);
    if (liveBlueKey != 0) blitUi(uiKeyAsset[0], 239, 171);
    if (liveYellowKey != 0) blitUi(uiKeyAsset[1], 249, 171);
    if (liveRedKey != 0) blitUi(uiKeyAsset[2], 259, 171);
    if (livePaused != 0)
      blitUi(uiPauseAsset, (WIDTH - uiAssetWidth[uiPauseAsset]) / 2, 4);
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

  private static int firstAtLeast(double[] values,int base,int first,int end,double target){
    int low=first,high=end;while(low<high){int middle=(low+high)>>>1;
      if(values[base+middle]>=target)high=middle;else low=middle+1;}return low;
  }

  private static int firstLess(double[] values,int base,int first,int end,double target){
    int low=first,high=end;while(low<high){int middle=(low+high)>>>1;
      if(values[base+middle]<target)high=middle;else low=middle+1;}return low;
  }

  private static void rasterPlaneRange(int column,int sector,int firstRow,int endRow,
      boolean ceiling,double px,double py,double rayX,double rayY,int interval){
    int planeBase=sector*200;
    planeRowAttempts+=endRow-firstRow;
    if(ceiling&&sectorCeiling[sector]<=cameraEyeZ)return;
    if(!ceiling&&sectorFloor[sector]>=cameraEyeZ)return;
    boolean sky=ceiling&&sectorCeilingSky[sector]!=0;
    int asset=sky?skyAsset:(ceiling?activeSectorCeilingAsset[sector]:activeSectorFloorAsset[sector]);
    short[] texels=sky?wallAssetTexels[asset]:flatAssetTexels[asset];
    int colormapBase=sky?0:sectorLightBand[sector]*256;
    int skyHeight=sky?wallAssetHeight[asset]:0;
    int skyBase=sky?wrap(sqlFloor(column/2.0),wallAssetWidth[asset])*skyHeight:0;
    for(int row=firstRow;row<endRow;row++){
      int frameOffset=column*200+row;
      if(wallOwned[frameOffset]!=0||wallFrame[frameOffset]>=0)continue;
      double distance=ceiling?planeCeilingDistance[planeBase+row]:planeFloorDistance[planeBase+row];
      if(distance<intervalStart[interval]||distance>=intervalEnd[interval])continue;
      int raw;if(sky)raw=texels[skyBase+wrap(row,skyHeight)];
      else{int x=fastFloor(px+rayX*distance)&63;
        int y=fastFloor(py+rayY*distance)&63;raw=texels[x*64+y];}
      if(raw<0)continue;
      wallFrame[frameOffset]=colormap[colormapBase+raw];
    }
  }

  private static void prepareVisiblePlanes(double eyeZ){
    Arrays.fill(visiblePlaneSector,false);
    for(int interval=0;interval<intervalTotal;interval++)
      visiblePlaneSector[intervalSector[interval]]=true;
    for (int sector = 0; sector < sectorFloor.length; sector++) {
      if(!visiblePlaneSector[sector])continue;
      activeSectorCeilingAsset[sector]=sectorCeilingSky[sector]!=0 ? -1 :
          animatedAsset("flat",sectorCeilingFlat[sector],sectorCeilingAsset[sector]);
      activeSectorFloorAsset[sector]=
          animatedAsset("flat",sectorFloorFlat[sector],sectorFloorAsset[sector]);
      int base = sector * 200;
      for (int row = 0; row < 100; row++)
        planeCeilingDistance[base + row] =
            (sectorCeiling[sector] - eyeZ) * projectionK / (99.5 - row);
      for (int row = 100; row < 200; row++)
        planeFloorDistance[base + row] =
            (eyeZ - sectorFloor[sector]) * projectionK / (row - 99.5);
    }
  }

  private static void rasterVisiblePlanes(double px,double py){
    for (int column = 0; column < WIDTH; column++) {
      double rayX = rayXProfile[activeAngle * WIDTH + column];
      double rayY = rayYProfile[activeAngle * WIDTH + column];
      int firstInterval = intervalOffset[column];
      int endInterval = firstInterval + intervalCount[column];
      for (int interval = firstInterval; interval < endInterval; interval++) {
        int sector = intervalSector[interval];
        int firstRow = Math.max(0, (int) Math.ceil(intervalClipTop[interval] - .5));
        int endRow = Math.min(200, (int) Math.ceil(intervalClipBottom[interval] - .5));
        int planeBase=sector*200;
        int ceilingFirst=Math.min(100,firstRow),ceilingEnd=Math.min(100,endRow);
        if(ceilingFirst<ceilingEnd){
          ceilingFirst=firstAtLeast(planeCeilingDistance,planeBase,ceilingFirst,ceilingEnd,
            intervalStart[interval]);
          ceilingEnd=firstAtLeast(planeCeilingDistance,planeBase,ceilingFirst,ceilingEnd,
            intervalEnd[interval]);
          rasterPlaneRange(column,sector,ceilingFirst,ceilingEnd,true,px,py,rayX,rayY,interval);
        }
        int floorFirst=Math.max(100,firstRow),floorEnd=Math.max(100,endRow);
        if(floorFirst<floorEnd){
          floorFirst=firstLess(planeFloorDistance,planeBase,floorFirst,floorEnd,
            intervalEnd[interval]);
          floorEnd=firstLess(planeFloorDistance,planeBase,floorFirst,floorEnd,
            intervalStart[interval]);
          rasterPlaneRange(column,sector,floorFirst,floorEnd,false,px,py,rayX,rayY,interval);
        }
      }
    }
  }

  private static void drawPlanes(double px, double py, double dirX, double dirY,
      double plnX, double plnY) {
    prepareVisiblePlanes(cameraEyeZ);rasterVisiblePlanes(px,py);
  }

  private static void drawSprites(double px, double py, double forwardX, double forwardY) {
    int centerColumn = WIDTH / 2;
    if (intervalCount[centerColumn] == 0) return;
    double eyeZ = cameraEyeZ;
    for (int mobj = 0; mobj < mobjCount; mobj++)
      projectSprite(mobj, px, py, forwardX, forwardY, eyeZ);
  }

  private static void projectSprite(int mobj, double px, double py, double forwardX,
      double forwardY, double eyeZ) {
    double relX = mobjX[mobj] - px, relY = mobjY[mobj] - py;
    double depth = relX * forwardX + relY * forwardY;
    if (depth <= 1.0) return;
    double lateral = -relX * forwardY + relY * forwardX;
    double bearing = Math.atan2(py - mobjY[mobj], px - mobjX[mobj]) * 180.0 / Math.PI;
    double normalized = (bearing - mobjAngle[mobj] + 720.0) % 360.0;
    int rotation = ((int) Math.floor((normalized + 22.5) / 45.0)) % 8 + 1;
    int state = mobjState[mobj];
    if (state < 0 || state >= catalogStateCount) return;
    int catalog = state * 9 + (catalogPresent[state * 9] != 0 ? 0 : rotation);
    if (catalogPresent[catalog] == 0) return;
    int asset = catalogAsset[catalog];
    int width = spriteAssetWidth[asset], height = spriteAssetHeight[asset];
    double screenCenter = 160.0 + lateral * 160.0 / depth;
    double scale = 160.0 / depth;
    int left = (int) Math.floor(screenCenter - catalogLeft[catalog] * scale);
    int right = (int) Math.ceil(screenCenter + (width - catalogLeft[catalog]) * scale) - 1;
    int top = (int) Math.floor(100.0 - (mobjZ[mobj] + catalogTop[catalog] - eyeZ) * scale);
    int bottom = (int) Math.ceil(100.0 -
        (mobjZ[mobj] + catalogTop[catalog] - height - eyeZ) * scale) - 1;
    rasterSprite(mobj, depth, catalog, asset, left, right, top, bottom);
  }

  private static void rasterSprite(int mobj, double depth, int catalog, int asset,
      int left, int right, int top, int bottom) {
    int width = spriteAssetWidth[asset], height = spriteAssetHeight[asset];
    int firstColumn = Math.max(0, left), endColumn = Math.min(WIDTH, right + 1);
    int screenWidth = right - left + 1, screenHeight = bottom - top + 1;
    if (firstColumn >= endColumn || screenWidth <= 0 || screenHeight <= 0) return;
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

  private static double acceptedDepth(int id, int column, double px, double py,
      double dirX, double dirY, double plnX, double plnY) {
    double rayX = rayXProfile[activeAngle * WIDTH + column];
    double rayY = rayYProfile[activeAngle * WIDTH + column];
    double segX = segEndX[id] - segStartX[id];
    double segY = segEndY[id] - segStartY[id];
    double determinant = rayX * segY - rayY * segX;
    if (Math.abs(determinant) < 1e-12) return Double.NaN;
    double relX = segRelativeStartX[id], relY = segRelativeStartY[id];
    double hitT = exactTNumerator(id) / determinant;
    if (hitT <= NEAR) return Double.NaN;
    double hitU = (relX * rayY - relY * rayX) / determinant;
    acceptedUCache[id*WIDTH+column]=hitU;
    return hitU >= 0.0 && hitU <= 1.0 ? hitT : Double.NaN;
  }

  private static double acceptedU(int id, int column, double px, double py,
      double dirX, double dirY, double plnX, double plnY) {
    double rayX = rayXProfile[activeAngle * WIDTH + column];
    double rayY = rayYProfile[activeAngle * WIDTH + column];
    double segX = segEndX[id] - segStartX[id];
    double segY = segEndY[id] - segStartY[id];
    double determinant = rayX * segY - rayY * segX;
    double relX = segRelativeStartX[id], relY = segRelativeStartY[id];
    return (relX * rayY - relY * rayX) / determinant;
  }

  private static int wrap(int value, int modulus) {
    int result = value % modulus;
    return result < 0 ? result + modulus : result;
  }

  private static int animatedAsset(String kind, String baseName, int fallback) {
    int[] animation = animationByAsset.get(kind + ":" + baseName);
    if (animation == null) return fallback;
    int count = animation[1];
    int ordinal = (animation[animation.length - 1] + liveTic / animation[0]) % count;
    return animation[2 + ordinal];
  }

  private static int wallAsset(String name){
    if(name==null||"-".equals(name))return -1;
    Integer asset=wallAssetByName.get(name);return asset==null?-1:asset.intValue();
  }

  private static String rightRestoreTexture(int id){
    if(!"-".equals(rightMiddle[id]))return rightMiddle[id];
    if(!"-".equals(rightUpper[id]))return rightUpper[id];
    if(!"-".equals(rightLower[id]))return rightLower[id];
    return "NONE";
  }

  private static boolean switchRestoreMatches(int line,String restore){
    boolean found=false;String expected=null;
    for(int id=0;id<segTotal;id++)if(segLineId[id]==line){String candidate=rightRestoreTexture(id);
      if(!found){expected=candidate;found=true;}else require(expected.equals(candidate),
          "linedef sidedef restore mismatch");}
    return found&&expected.startsWith("SW1")&&expected.equals(restore);
  }

  private static int presentedWallAsset(int seg,int asset){
    if(asset<0||!anySwitchOn)return asset;
    int line=segLineId[seg];return line>=0&&line<lineSwitchOn.length&&lineSwitchOn[line]!=0?
        switchOnWallAsset[asset]:asset;
  }

  private static void buildWallHotCaches(){
    rightUpperAsset=new int[segTotal];rightLowerAsset=new int[segTotal];
    rightMiddleAsset=new int[segTotal];leftUpperAsset=new int[segTotal];
    leftLowerAsset=new int[segTotal];leftMiddleAsset=new int[segTotal];
    segLength=new double[segTotal];
    for(int id=0;id<segTotal;id++){
      rightUpperAsset[id]=wallAsset(rightUpper[id]);rightLowerAsset[id]=wallAsset(rightLower[id]);
      rightMiddleAsset[id]=wallAsset(rightMiddle[id]);leftUpperAsset[id]=wallAsset(leftUpper[id]);
      leftLowerAsset[id]=wallAsset(leftLower[id]);leftMiddleAsset[id]=wallAsset(leftMiddle[id]);
      double dx=segEndX[id]-segStartX[id],dy=segEndY[id]-segStartY[id];
      segLength[id]=Math.sqrt(dx*dx+dy*dy);
    }
    int maxLine=-1;for(int id=0;id<segTotal;id++)maxLine=Math.max(maxLine,segLineId[id]);
    lineSwitchOn=new byte[maxLine+1];lineSwitchTimer=new int[maxLine+1];
    Arrays.fill(lineSwitchTimer,-1);boolean[] seenLine=new boolean[maxLine+1];mapLineCount=0;
    for(int id=0;id<segTotal;id++)if(rightRestoreTexture(id).startsWith("SW1")&&
        !seenLine[segLineId[id]]){seenLine[segLineId[id]]=true;mapLineCount++;}
    switchOnWallAsset=new int[wallAssetWidth.length];
    for(Map.Entry<String,Integer> entry:wallAssetByName.entrySet()){
      int base=entry.getValue();String name=entry.getKey();int selected=base;
      if(name.startsWith("SW1")){Integer alternate=wallAssetByName.get("SW2"+name.substring(3));
        require(alternate!=null,"switch wall mate missing "+name);selected=alternate.intValue();}
      switchOnWallAsset[base]=selected;
    }
    wallAnimationByAsset=new int[wallAssetWidth.length][];
    for(Map.Entry<String,int[]> entry:animationByAsset.entrySet()){
      String key=entry.getKey();if(!key.startsWith("wall_texture:"))continue;
      Integer asset=wallAssetByName.get(key.substring(13));
      if(asset!=null)wallAnimationByAsset[asset.intValue()]=entry.getValue();
    }
    activeWallAsset=new int[wallAssetWidth.length];
  }

  private static void resolveActiveWallAssets(){
    for(int asset=0;asset<activeWallAsset.length;asset++){
      int[] animation=wallAnimationByAsset[asset];
      if(animation==null){activeWallAsset[asset]=asset;continue;}
      int count=animation[1];
      int ordinal=(animation[animation.length-1]+liveTic/animation[0])%count;
      activeWallAsset[asset]=animation[2+ordinal];
    }
  }

  private static int sqlFloor(double value) {
    if (!Double.isFinite(value) || value <= Integer.MIN_VALUE + 1.0 ||
        value >= Integer.MAX_VALUE - 1.0) return (int) Math.floor(value);
    int floor = fastFloor(value);
    if (value - floor <= 1e-12) return floor;
    return floor + 1.0 - value <= 1e-12 ? floor + 1 : floor;
  }

  private static int fastFloor(double value) {
    int truncated = (int) value;
    return value < truncated ? truncated - 1 : truncated;
  }

  private static void drawWallPiece(int id, int column, double depth, double hitU,
      double clipTop, double clipBottom, double worldTop, double worldBottom,
      int baseAsset, double anchor, int xOffset, int yOffset, int light,
      double eyeZ) {
    double screenTop = 100.0 - (worldTop - eyeZ) * projectionK / depth;
    double screenBottom = 100.0 - (worldBottom - eyeZ) * projectionK / depth;
    int first = Math.max(0, (int) Math.ceil(Math.max(clipTop, screenTop) - .5));
    int end = Math.min(200, (int) Math.ceil(Math.min(clipBottom, screenBottom) - .5));
    if (first >= end) return;
    // SQL's asset join emits no candidate pixels for null/"-" termination
    // textures while the hit still terminates the portal walk.
    if (baseAsset < 0) return;
    int asset=activeWallAsset[presentedWallAsset(id,baseAsset)];
    double sampleX=segOffset[id]+xOffset+hitU*segLength[id];
    int assetHeight=wallAssetHeight[asset];
    int sampleColumn=wrap(sqlFloor(sampleX),wallAssetWidth[asset]);
    int texelBase=sampleColumn*assetHeight;
    int colormapBase=Math.max(0,Math.min(31,(255-light)/8))*256;
    int base = column * 200;
    wallRowAttempts+=end-first;
    double sampleStep=depth/projectionK;
    double sampleY=anchor-(eyeZ+(100.0-(first+.5))*depth/projectionK)+yOffset;
    for (int row = first; row < end; row++) {
      int frameOffset = base + row;
      if (wallOwned[frameOffset] != 0){sampleY+=sampleStep;continue;}
      wallOwned[frameOffset] = 1;
      int sampleRow=wrap(sqlFloor(sampleY),assetHeight);
      int raw=wallAssetTexels[asset][texelBase+sampleRow];
      if(raw>=0){wallFrame[frameOffset]=colormap[colormapBase+raw];
        wallColored[frameOffset]=1;}
      sampleY+=sampleStep;
    }
  }

  private static void drawActiveWall(int id, int column, double px, double py,
      double depth, double dirX, double dirY, double plnX, double plnY,
      int from, int to, double clipTop, double clipBottom, double eyeZ) {
    boolean right=rightFacingCache[id]!=0;
    String upper = right ? rightUpper[id] : leftUpper[id];
    String lower = right ? rightLower[id] : leftLower[id];
    String middle = right ? rightMiddle[id] : leftMiddle[id];
    int upperAsset=right?rightUpperAsset[id]:leftUpperAsset[id];
    int lowerAsset=right?rightLowerAsset[id]:leftLowerAsset[id];
    int middleAsset=right?rightMiddleAsset[id]:leftMiddleAsset[id];
    int xOffset = right ? rightXOffset[id] : leftXOffset[id];
    int yOffset = right ? rightYOffset[id] : leftYOffset[id];
    double hitU=acceptedUCache[id*WIDTH+column];
    boolean termination = to < 0 || Math.min(sectorCeiling[from], sectorCeiling[to]) <=
        Math.max(sectorFloor[from], sectorFloor[to]);
    if (termination) {
      int asset=!"-".equals(middle)?middleAsset:(!"-".equals(upper)?upperAsset:lowerAsset);
      double anchor = (lineFlags[id] & 16) != 0 ? sectorFloor[from] + 128.0 :
          sectorCeiling[from];
      drawWallPiece(id, column, depth, hitU, clipTop, clipBottom,
          sectorCeiling[from], sectorFloor[from], asset, anchor,
          xOffset, yOffset, sectorLight[from], eyeZ);
      return;
    }
    if (sectorFloor[to] > sectorFloor[from] && !"-".equals(lower)) {
      double anchor = (lineFlags[id] & 16) != 0 ? sectorCeiling[from] : sectorFloor[to];
      drawWallPiece(id, column, depth, hitU, clipTop, clipBottom,
          sectorFloor[to], sectorFloor[from], lowerAsset, anchor,
          xOffset, yOffset, sectorLight[from], eyeZ);
    }
    if (sectorCeiling[to] < sectorCeiling[from] && !"-".equals(upper) &&
        !("F_SKY1".equals(sectorCeilingFlat[from]) &&
          "F_SKY1".equals(sectorCeilingFlat[to]))) {
      double anchor = (lineFlags[id] & 8) != 0 ? sectorCeiling[to] + 128.0 :
          sectorCeiling[from];
      drawWallPiece(id, column, depth, hitU, clipTop, clipBottom,
          sectorCeiling[from], sectorCeiling[to], upperAsset, anchor,
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

  private static void drawMaskedWall(int id, int column, double px, double py,
      double depth, double dirX, double dirY, double plnX, double plnY,
      int from, double clipTop, double clipBottom, double eyeZ) {
    boolean right=rightFacingCache[id]!=0;
    int asset=right?rightMiddleAsset[id]:leftMiddleAsset[id];
    if(asset<0)return;
    int xOffset = right ? rightXOffset[id] : leftXOffset[id];
    int yOffset = right ? rightYOffset[id] : leftYOffset[id];
    double hitU=acceptedUCache[id*WIDTH+column];
    int assetX = wrap(sqlFloor(segOffset[id] + xOffset + hitU * segLength[id]),
        wallAssetWidth[asset]);
    int first = Math.max(0, (int) Math.ceil(Math.max(0.0, clipTop) - .5));
    int end = Math.min(200, (int) Math.ceil(Math.min(200.0, clipBottom) - .5));
    wallRowAttempts+=end-first;
    double sampleStep=depth/160.0;
    double sampleY=sectorCeiling[from]-(eyeZ+(100.0-(first+.5))*depth/160.0)+yOffset;
    for (int row = first; row < end; row++) {
      int assetY = wrap(sqlFloor(sampleY), wallAssetHeight[asset]);
      int raw = wallAssetTexels[asset][assetX * wallAssetHeight[asset] + assetY];
      int index=column*200+row;
      if(raw>=0&&overlayWins(index,depth,(byte)1,segLineId[id],assetY,assetX)){
        overlayDepth[index] = depth; overlayKind[index] = 1;
        overlaySource[index] = segLineId[id]; overlayAssetX[index] = assetX;
        overlayAssetY[index] = assetY; overlayPalette[index] = (short) raw;
      }
      sampleY+=sampleStep;
    }
  }

  private static void applySolidCoverage(double px, double py, double dirX, double dirY,
      double plnX, double plnY, boolean retainCandidates) {
    visiblePairs = 0;
    for(int id=0;id<segTotal;id++){
      int last=projectedLast[id];if(last<0)continue;
      for(int column=projectedFirst[id];column<=last;column++){
        double depth=acceptedDepthCache[id*WIDTH+column];
        if (!Double.isNaN(depth) && depth <= nearestSolidDepth[column] + 1e-9) {
          visiblePairs++;
          int count = columnVisibleCount[column];
          require(count < MAX_VISIBLE_PER_COLUMN, "visible seg capacity exceeded");
          int visibleIndex = column * MAX_VISIBLE_PER_COLUMN + count;
          columnVisibleSeg[visibleIndex] = id;
          columnVisibleDepth[visibleIndex] = depth;
          columnVisibleCount[column] = count + 1;
          if (retainCandidates) visibleCandidates[id * WIDTH + column] = 1;
        }
      }
    }
  }

  private static void projectLeafSeg(int id,double px,double py,double dirX,double dirY,
      double plnX,double plnY,double planeSquared,boolean retainCandidates){
    projectSeg(id,px,py,dirX,dirY,plnX,plnY,planeSquared,retainCandidates);
    int last=projectedLast[id];if(last<0)return;
    for(int column=projectedFirst[id];column<=last;column++){
      double depth=acceptedDepth(id,column,px,py,dirX,dirY,plnX,plnY);
      acceptedDepthCache[id*WIDTH+column]=depth;
      if(!Double.isNaN(depth)){acceptedPairs++;
        if(segSolid[id]!=0&&depth<nearestSolidDepth[column])nearestSolidDepth[column]=depth;}
    }
  }

  private static void traverseBsp(int id,boolean leaf,double px,double py,double dirX,double dirY,
      double plnX,double plnY,double planeSquared,boolean retainCandidates){
    if(leaf){visitedSubsectors++;int end=firstSeg[id]+segCount[id];
      for(int seg=firstSeg[id];seg<end;seg++)
        projectLeafSeg(seg,px,py,dirX,dirY,plnX,plnY,planeSquared,retainCandidates);
      return;
    }
    visitedNodes++;int near=side(px,py,id),far=near^1;
    int nearOffset=id*2+near;
    if(bboxVisible(nearOffset,px,py,dirX,dirY,plnX,plnY,planeSquared))
      traverseBsp(childId[nearOffset],childLeaf[nearOffset]!=0,px,py,dirX,dirY,
          plnX,plnY,planeSquared,retainCandidates);
    int farOffset=id*2+far;
    if(bboxVisible(farOffset,px,py,dirX,dirY,plnX,plnY,planeSquared)){
      if(!retainCandidates&&bboxOccluded(farOffset,px,py,dirX,dirY,plnX,plnY,planeSquared))
        occludedBboxes++;
      else traverseBsp(childId[farOffset],childLeaf[farOffset]!=0,px,py,dirX,dirY,
          plnX,plnY,planeSquared,retainCandidates);
    }
  }

  private static int traverseAndProject(double px, double py, int angle, boolean retainCandidates) {
    if (Double.doubleToLongBits(px) != Double.doubleToLongBits(liveCameraX) ||
        Double.doubleToLongBits(py) != Double.doubleToLongBits(liveCameraY)) {
      liveCameraX = px; liveCameraY = py;
      liveExactCameraX = BigDecimal.valueOf(px); liveExactCameraY = BigDecimal.valueOf(py);
      prepareExactSegmentRelatives();
    }
    long stageStarted = System.nanoTime();
    activeAngle = angle;
    visitedNodes = 0; visitedSubsectors = 0; projectedSegs = 0; candidatePairs = 0;
    acceptedPairs=0;occludedBboxes=0;
    Arrays.fill(projectedLast, -1);
    Arrays.fill(nearestSolidDepth,Double.POSITIVE_INFINITY);
    Arrays.fill(columnVisibleCount,0);
    if (retainCandidates) Arrays.fill(rawCandidates, (byte) 0);
    if (retainCandidates) Arrays.fill(visibleCandidates, (byte) 0);
    double dirX = directionX[angle], dirY = directionY[angle];
    double plnX = planeX[angle], plnY = planeY[angle];
    double planeSquared = plnX * plnX + plnY * plnY;
    traverseBsp(nodeCount-1,false,px,py,dirX,dirY,plnX,plnY,planeSquared,retainCandidates);
    lastBspNanos = System.nanoTime() - stageStarted;
    stageStarted = System.nanoTime();
    applySolidCoverage(px, py, dirX, dirY, plnX, plnY, retainCandidates);
    lastSolidNanos = System.nanoTime() - stageStarted;
    applyPortalWalk(px, py, dirX, dirY, plnX, plnY, retainCandidates);
    sink += activePortalPairs + visiblePairs + candidatePairs + visitedNodes;
    return activePortalPairs;
  }

  private static int[] sqlOracle(Connection connection, double px, double py, int angleProfile) throws Exception {
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
      statement.setDouble(2, px); statement.setDouble(3, py);
      statement.setDouble(4, px); statement.setDouble(5, py);
      statement.setDouble(6, px); statement.setDouble(7, py);
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

  private static int[] productionPortalOracle(Connection connection, double px, double py)
      throws Exception {
    String session = null;
    byte[] oracleDocument = null;
    String oracleStateSha = null;
    byte[] oracleActive = new byte[segTotal * WIDTH];
    int sqlActive = 0, missing = 0, extra = 0, clipMismatch = 0;
    int sqlWallPixels = 0, wallMissing = 0, wallColorMismatch = 0, wallExtra = 0;
    int sqlWorldPixels = 0, worldMissing = 0, worldColorMismatch = 0, worldExtra = 0;
    int sqlMaskedWall = 0, maskedWallMissing = 0, maskedWallColor = 0, maskedWallExtra = 0;
    int sqlMaskedTotal = 0, maskedMissing = 0, maskedColor = 0, maskedExtra = 0;
    int sqlPresentation = 0, presentationMissing = 0, presentationColor = 0,
        presentationExtra = 0;
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
        require(payload != null && payload.length() <= Integer.MAX_VALUE,
            "NEW_GAME payload missing or too large");
        byte[] compressed = payload.getBytes(1, (int) payload.length());
        payload.free();
        oracleDocument = gunzip(compressed, compressed.length);
        String oracleJson = new String(oracleDocument, StandardCharsets.UTF_8);
        String marker = "\"state_sha\":\"";
        int stateStart = oracleJson.indexOf(marker);
        require(stateStart >= 0, "NEW_GAME state_sha missing");
        stateStart += marker.length();
        int stateEnd = oracleJson.indexOf('"', stateStart);
        require(stateEnd - stateStart == 64, "NEW_GAME state_sha malformed");
        oracleStateSha = oracleJson.substring(stateStart, stateEnd);
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
               "and is_selected=1");
           PreparedStatement presentationOracle = connection.prepareStatement(
               "select column_no,row_no,palette_index from doom_api_presentation_rows " +
               "where session_token=?")) {
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
            staging.executeUpdate("delete from frame_world_pixel");
            staging.executeUpdate("insert into frame_world_pixel select * " +
                "from doom_r2_staged_pixel_rows where session_token='" + session + "'");
            staging.executeUpdate("delete from frame_masked_pixel");
            staging.executeUpdate("insert into frame_masked_pixel(session_token,column_no," +
                "row_no,palette_index,source_kind,source_id) select session_token,column_no," +
                "row_no,palette_index,source_kind,source_id from " +
                "doom_r2_staged_masked_candidate_rows where session_token='" + session +
                "' and is_selected=1");
            staging.executeUpdate("delete from frame_column");
            staging.executeUpdate("insert into frame_column(session_token,column_no) select '" +
                session + "',level-1 from dual connect by level<=320");
            presentationOracle.setString(1, session);
            byte[] seenPresentation = new byte[finalFrame.length];
            try (ResultSet rows = presentationOracle.executeQuery()) {
              while (rows.next()) {
                sqlPresentation++;
                int index = rows.getInt(1) * 200 + rows.getInt(2);
                seenPresentation[index] = 1;
                if (finalFrame[index] < 0) presentationMissing++;
                else if (finalFrame[index] != rows.getInt(3)) presentationColor++;
              }
            }
            for (int index = 0; index < finalFrame.length; index++)
              if (finalFrame[index] >= 0 && seenPresentation[index] == 0) presentationExtra++;
            encodeTicZeroPayload(oracleStateSha);
            require(equalPrefix(codecJson, codecJsonLength, oracleDocument),
                "Java canonical payload differs from NEW_GAME SQL payload");
            byte[] javaRoundTrip = gunzip(codecGzip, codecGzipLength);
            require(equalPrefix(codecJson, codecJsonLength, javaRoundTrip),
                "Java gzip round trip differs from canonical payload");
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
        maskedColor, maskedExtra, sqlPresentation, presentationMissing,
        presentationColor, presentationExtra};
  }

  private static double percentile(long[] sorted, double quantile) {
    int index = (int) Math.ceil(sorted.length * quantile) - 1;
    return sorted[Math.max(0, index)] / 1_000_000.0;
  }

  private static int appendAscii(int offset, String value) {
    for (int index = 0; index < value.length(); index++)
      codecJson[offset++] = (byte) value.charAt(index);
    return offset;
  }

  private static int appendNumber(int offset, int value) {
    if (value == 0) { codecJson[offset] = '0'; return offset + 1; }
    int divisor = 1;
    while (value / divisor >= 10) divisor *= 10;
    while (divisor != 0) {
      codecJson[offset++] = (byte) ('0' + value / divisor);
      value %= divisor;
      divisor /= 10;
    }
    return offset;
  }

  private static int appendHexDigest(int offset) {
    for (int index = 0; index < codecDigest.length; index++) {
      int value = codecDigest[index] & 255;
      codecJson[offset++] = HEX[value >>> 4];
      codecJson[offset++] = HEX[value & 15];
    }
    return offset;
  }

  private static void writeLittleEndian(int offset, long value) {
    for (int index = 0; index < 4; index++) {
      codecGzip[offset + index] = (byte) value;
      value >>>= 8;
    }
  }

  private static void prepareFrameSha() throws Exception {
    for (int index = 0; index < finalFrame.length; index++)
      codecFrame[index] = (byte) finalFrame[index];
    codecSha256.reset();
    codecSha256.update(codecFrame);
    require(codecSha256.digest(codecDigest, 0, codecDigest.length) == codecDigest.length,
        "SHA-256 output length mismatch");
  }

  private static void buildTicZeroJson(String stateSha) {
    int offset = appendAscii(0, "{\"v\":1,\"tic\":0,\"w\":320,\"h\":200,\"mode\":\"game\"," +
        "\"state_sha\":\"");
    offset = appendAscii(offset, stateSha);
    offset = appendAscii(offset, "\",\"frame_sha\":\"");
    offset = appendHexDigest(offset);
    offset = appendAscii(offset, "\",\"cols\":[");
    codecRunCount = 0;
    for (int column = 0; column < WIDTH; column++) {
      if (column != 0) codecJson[offset++] = ',';
      codecJson[offset++] = '[';
      int row = 0;
      boolean firstRun = true;
      while (row < 200) {
        int palette = codecFrame[column * 200 + row] & 255;
        int start = row++;
        while (row < 200 && (codecFrame[column * 200 + row] & 255) == palette) row++;
        if (!firstRun) codecJson[offset++] = ',';
        firstRun = false;
        codecJson[offset++] = '[';
        offset = appendNumber(offset, start); codecJson[offset++] = ',';
        offset = appendNumber(offset, row - start); codecJson[offset++] = ',';
        offset = appendNumber(offset, palette); codecJson[offset++] = ']';
        codecRunCount++;
      }
      codecJson[offset++] = ']';
    }
    offset = appendAscii(offset, "],\"audio\":[],\"complete\":0}");
    codecJsonLength = offset;
  }

  private static void compressJson() {
    codecGzip[0] = 0x1f; codecGzip[1] = (byte) 0x8b; codecGzip[2] = 8;
    codecGzip[3] = 0; codecGzip[4] = 0; codecGzip[5] = 0; codecGzip[6] = 0;
    codecGzip[7] = 0; codecGzip[8] = 0; codecGzip[9] = 3;
    codecDeflater.reset();
    codecDeflater.setInput(codecJson, 0, codecJsonLength);
    codecDeflater.finish();
    int compressed = 10;
    int stalls = 0;
    while (!codecDeflater.finished()) {
      require(compressed < codecGzip.length - 8, "gzip output capacity exhausted");
      int written = codecDeflater.deflate(codecGzip, compressed,
          codecGzip.length - compressed - 8);
      if (written == 0) {
        require(++stalls < 4, "gzip deflater stalled");
        continue;
      }
      stalls = 0;
      compressed += written;
    }
    codecCrc.reset();
    codecCrc.update(codecJson, 0, codecJsonLength);
    writeLittleEndian(compressed, codecCrc.getValue());
    writeLittleEndian(compressed + 4, codecJsonLength);
    codecGzipLength = compressed + 8;
  }

  private static void buildPackedLiveJson(String stateSha) {
    int offset = appendAscii(0, "{\"v\":2,\"tic\":");
    offset = appendNumber(offset, liveTic);
    offset = appendAscii(offset, ",\"w\":320,\"h\":200,\"mode\":\"");
    offset = appendAscii(offset, liveMode);
    offset = appendAscii(offset, "\",\"state_sha\":\"");
    offset = appendAscii(offset, stateSha);
    offset = appendAscii(offset, "\",\"frame_sha\":\"");
    offset = appendHexDigest(offset);
    offset = appendAscii(offset, "\",\"frame_b64\":\"");
    int index = 0;
    while (index + 2 < codecFrame.length) {
      int bits = ((codecFrame[index] & 255) << 16) |
          ((codecFrame[index + 1] & 255) << 8) | (codecFrame[index + 2] & 255);
      codecJson[offset++] = BASE64[(bits >>> 18) & 63];
      codecJson[offset++] = BASE64[(bits >>> 12) & 63];
      codecJson[offset++] = BASE64[(bits >>> 6) & 63];
      codecJson[offset++] = BASE64[bits & 63];
      index += 3;
    }
    if (index < codecFrame.length) {
      int bits = (codecFrame[index] & 255) << 16;
      codecJson[offset++] = BASE64[(bits >>> 18) & 63];
      if (index + 1 < codecFrame.length) {
        bits |= (codecFrame[index + 1] & 255) << 8;
        codecJson[offset++] = BASE64[(bits >>> 12) & 63];
        codecJson[offset++] = BASE64[(bits >>> 6) & 63];
      } else {
        codecJson[offset++] = BASE64[(bits >>> 12) & 63];
        codecJson[offset++] = '=';
      }
      codecJson[offset++] = '=';
    }
    offset = appendAscii(offset, "\",\"audio\":");
    offset = appendAscii(offset, liveAudio);
    offset = appendAscii(offset, ",\"complete\":");
    offset = appendNumber(offset, liveComplete);
    codecJson[offset++] = '}';
    codecJsonLength = offset;
  }

  private static void encodePackedTicZeroPayload(String stateSha) throws Exception {
    prepareFrameSha();
    buildPackedLiveJson(stateSha);
    compressJson();
  }

  private static void encodeTicZeroPayload(String stateSha) throws Exception {
    prepareFrameSha();
    buildTicZeroJson(stateSha);
    compressJson();
  }

  public static void renderTicZero(Blob payload) throws Exception {
    require(payload != null, "caller-owned BLOB is required");
    if (!databaseCacheLoaded) {
      codecSha256 = MessageDigest.getInstance("SHA-256");
      Connection internal = DriverManager.getConnection("jdbc:default:connection:");
      loadKernelPack(internal);
      databaseCacheLoaded = true;
    }
    liveTic = 0; liveMode = "game"; liveComplete = 0; livePaused = 0;
    liveCameraX = -416.0; liveCameraY = 256.0; cameraEyeZ = 41.0; liveAngle = 0;
    liveExactCameraX = BigDecimal.valueOf(-416); liveExactCameraY = BigDecimal.valueOf(256);
    prepareExactSegmentRelatives();
    liveAmmo = 50; liveHealth = 100; liveArmor = 0;
    liveBlueKey = 0; liveYellowKey = 0; liveRedKey = 0; liveAudio = "[]";
    weaponAsset = spriteAssetByName.get("PISGA0");
    long started = System.nanoTime();
    traverseAndProject(liveCameraX, liveCameraY, liveAngle, false);
    lastRenderNanos = System.nanoTime() - started;
    started = System.nanoTime();
    encodePackedTicZeroPayload(ZERO_SHA);
    lastCodecNanos = System.nanoTime() - started;
    started = System.nanoTime();
    payload.truncate(0);
    int firstLength = Math.min(32767, codecGzipLength);
    int written = payload.setBytes(1, codecGzip, 0, firstLength);
    if (codecGzipLength > firstLength)
      written += payload.setBytes(firstLength + 1, codecGzip, firstLength,
          codecGzipLength - firstLength);
    require(written == codecGzipLength, "short packed BLOB write");
    lastBlobNanos = System.nanoTime() - started;
  }

  private static String renderSessionUnsafe(String session, String stateSha, Blob payload)
      throws Exception {
    require(payload != null, "caller-owned BLOB is required");
    require(stateSha != null && stateSha.matches("[0-9a-f]{64}"), "invalid state SHA");
    Connection internal = DriverManager.getConnection("jdbc:default:connection:");
    if (!databaseCacheLoaded) {
      codecSha256 = MessageDigest.getInstance("SHA-256");
      loadKernelPack(internal);
      databaseCacheLoaded = true;
    }
    long snapshotStarted = System.nanoTime();
    refreshPackedLiveState(internal, session);
    lastSnapshotNanos = System.nanoTime() - snapshotStarted;
    require("game".equals(liveMode) || "dead".equals(liveMode),
        "dynamic renderer currently supports GAME/DEAD only");
    long started = System.nanoTime();
    traverseAndProject(liveCameraX, liveCameraY, liveAngle, false);
    lastRenderNanos = System.nanoTime() - started;
    started = System.nanoTime();
    encodePackedTicZeroPayload(stateSha);
    lastCodecNanos = System.nanoTime() - started;
    started = System.nanoTime();
    payload.truncate(0);
    int firstLength = Math.min(32767, codecGzipLength);
    int written = payload.setBytes(1, codecGzip, 0, firstLength);
    if (codecGzipLength > firstLength)
      written += payload.setBytes(firstLength + 1, codecGzip, firstLength,
          codecGzipLength - firstLength);
    require(written == codecGzipLength, "short dynamic BLOB write");
    lastBlobNanos = System.nanoTime() - started;
    StringBuilder frameSha = new StringBuilder(64);
    for (byte value : codecDigest) {
      frameSha.append((char) HEX[(value >>> 4) & 15]);
      frameSha.append((char) HEX[value & 15]);
    }
    return frameSha.toString();
  }

  public static String renderSession(String session, String stateSha, Blob payload) {
    try {
      String result=renderSessionUnsafe(session, stateSha, payload);lastDynamicFailure="";return result;
    } catch (Throwable failure) {
      lastDynamicFailure=failure.getClass().getName()+":"+failure.getMessage();
      try { if (payload != null) payload.truncate(0); } catch (Throwable ignored) {}
      return "ERROR:" + failure.getClass().getName();
    }
  }

  private static String renderSnapshotUnsafe(Blob snapshot,String stateSha,Blob payload)
      throws Exception {
    require(payload!=null,"caller-owned BLOB is required");
    require(stateSha!=null&&stateSha.matches("[0-9a-f]{64}"),"invalid state SHA");
    if(!databaseCacheLoaded) {
      Connection internal=DriverManager.getConnection("jdbc:default:connection:");
      loadKernelPack(internal);databaseCacheLoaded=true;
    }
    long started=System.nanoTime();decodeDynamicSnapshot(snapshot,null);
    lastSnapshotNanos=System.nanoTime()-started;
    require("game".equals(liveMode)||"dead".equals(liveMode),
        "dynamic renderer currently supports GAME/DEAD only");
    started=System.nanoTime();traverseAndProject(liveCameraX,liveCameraY,liveAngle,false);
    lastRenderNanos=System.nanoTime()-started;
    started=System.nanoTime();encodePackedTicZeroPayload(stateSha);
    lastCodecNanos=System.nanoTime()-started;
    started=System.nanoTime();payload.truncate(0);
    int firstLength=Math.min(32767,codecGzipLength);
    int written=payload.setBytes(1,codecGzip,0,firstLength);
    if(codecGzipLength>firstLength)
      written+=payload.setBytes(firstLength+1,codecGzip,firstLength,
          codecGzipLength-firstLength);
    require(written==codecGzipLength,"short packed-snapshot BLOB write");
    lastBlobNanos=System.nanoTime()-started;
    StringBuilder frameSha=new StringBuilder(64);
    for(byte value:codecDigest){frameSha.append((char)HEX[(value>>>4)&15]);
      frameSha.append((char)HEX[value&15]);}
    return frameSha.toString();
  }

  public static String renderSnapshot(Blob snapshot,String stateSha,Blob payload) {
    try{return renderSnapshotUnsafe(snapshot,stateSha,payload);}
    catch(Throwable failure){try{if(payload!=null)payload.truncate(0);}catch(Throwable ignored){}
      return "ERROR:"+failure.getClass().getName();}
  }

  private static String renderPackedSessionUnsafe(String session,Blob snapshot,
      String stateSha,Blob payload) throws Exception {
    require(session!=null&&session.matches("[0-9a-f]{32}"),"invalid session token");
    require(payload!=null,"caller-owned BLOB is required");
    require(stateSha!=null&&stateSha.matches("[0-9a-f]{64}"),"invalid state SHA");
    if(!databaseCacheLoaded){Connection internal=DriverManager.getConnection(
        "jdbc:default:connection:");loadKernelPack(internal);databaseCacheLoaded=true;}
    long started=System.nanoTime();decodeDynamicSnapshot(snapshot,session);
    lastSnapshotNanos=System.nanoTime()-started;
    require("game".equals(liveMode)||"dead".equals(liveMode),
        "dynamic renderer currently supports GAME/DEAD only");
    started=System.nanoTime();traverseAndProject(liveCameraX,liveCameraY,liveAngle,false);
    lastRenderNanos=System.nanoTime()-started;
    started=System.nanoTime();encodePackedTicZeroPayload(stateSha);
    lastCodecNanos=System.nanoTime()-started;
    started=System.nanoTime();payload.truncate(0);
    int firstLength=Math.min(32767,codecGzipLength);
    int written=payload.setBytes(1,codecGzip,0,firstLength);
    if(codecGzipLength>firstLength)written+=payload.setBytes(firstLength+1,codecGzip,
        firstLength,codecGzipLength-firstLength);
    require(written==codecGzipLength,"short session snapshot BLOB write");
    lastBlobNanos=System.nanoTime()-started;
    StringBuilder frameSha=new StringBuilder(64);
    for(byte value:codecDigest){frameSha.append((char)HEX[(value>>>4)&15]);
      frameSha.append((char)HEX[value&15]);}
    return frameSha.toString();
  }

  public static String renderPackedSession(String session,Blob snapshot,String stateSha,
      Blob payload){try{String result=renderPackedSessionUnsafe(session,snapshot,stateSha,payload);
      lastDynamicFailure="";return result;}
    catch(Throwable failure){lastDynamicFailure=failure.getClass().getName()+":"+failure.getMessage();
      try{if(payload!=null)payload.truncate(0);}catch(Throwable ignored){}
      return "ERROR:"+failure.getClass().getName();}}

  public static String lastDynamicFailure(){return lastDynamicFailure;}

  public static String compareSessionOracle(String session) throws Exception {
    Connection internal = DriverManager.getConnection("jdbc:default:connection:");
    if (!databaseCacheLoaded) {
      codecSha256 = MessageDigest.getInstance("SHA-256");
      loadKernelPack(internal); databaseCacheLoaded = true;
    }
    refreshPackedLiveState(internal, session);
    traverseAndProject(liveCameraX, liveCameraY, liveAngle, false);
    int differences = 0, world = 0, hud = 0;
    int minColumn = WIDTH, maxColumn = -1, minRow = 200, maxRow = -1, rowsSeen = 0;
    try (PreparedStatement statement = internal.prepareStatement(
        "select column_no,row_no,palette_index from frame_pixel " +
        "where session_token=? order by column_no,row_no")) {
      statement.setString(1, session); statement.setFetchSize(1024);
      try (ResultSet rows = statement.executeQuery()) {
        while (rows.next()) {
          int column = rows.getInt(1), row = rows.getInt(2);
          require(column * 200 + row == rowsSeen, "SQL oracle frame is incomplete");
          int actual = finalFrame[rowsSeen] & 255;
          if (actual != rows.getInt(3)) {
            differences++;
            if (row < 168) world++; else hud++;
            minColumn = Math.min(minColumn, column); maxColumn = Math.max(maxColumn, column);
            minRow = Math.min(minRow, row); maxRow = Math.max(maxRow, row);
          }
          rowsSeen++;
        }
      }
    }
    require(rowsSeen == WIDTH * 200, "SQL oracle frame row count mismatch");
    return differences + "|" + world + "|" + hud + "|" + minColumn + "|" +
        maxColumn + "|" + minRow + "|" + maxRow;
  }

  private static int parseUnsigned(byte[] json, int[] at) {
    int value = 0, digits = 0;
    while (at[0] < json.length && json[at[0]] >= '0' && json[at[0]] <= '9') {
      value = value * 10 + json[at[0]++] - '0'; digits++;
    }
    require(digits != 0, "invalid SQL RLE number");
    return value;
  }

  private static void expect(byte[] json, int[] at, int value) {
    require(at[0] < json.length && json[at[0]++] == value, "invalid SQL RLE syntax");
  }

  private static String compareSqlPayloadInternal(String session, Blob sqlPayload,
      boolean refresh) throws Exception {
    require(sqlPayload != null && sqlPayload.length() <= Integer.MAX_VALUE,
        "SQL oracle payload is required");
    byte[] compressed = sqlPayload.getBytes(1, (int) sqlPayload.length());
    byte[] json = gunzip(compressed, compressed.length);
    byte[] marker = "\"cols\":[".getBytes(StandardCharsets.US_ASCII);
    int start = -1;
    outer: for (int index = 0; index <= json.length - marker.length; index++) {
      for (int match = 0; match < marker.length; match++)
        if (json[index + match] != marker[match]) continue outer;
      start = index + marker.length; break;
    }
    require(start >= 0, "SQL oracle cols missing");
    byte[] expected = new byte[WIDTH * 200];
    int[] at = {start};
    for (int column = 0; column < WIDTH; column++) {
      if (column != 0) expect(json, at, ',');
      expect(json, at, '[');
      int nextRow = 0, runs = 0;
      while (json[at[0]] != ']') {
        if (runs++ != 0) expect(json, at, ',');
        expect(json, at, '[');
        int y0 = parseUnsigned(json, at); expect(json, at, ',');
        int length = parseUnsigned(json, at); expect(json, at, ',');
        int palette = parseUnsigned(json, at); expect(json, at, ']');
        require(y0 == nextRow && length > 0 && y0 + length <= 200 && palette <= 255,
            "invalid SQL RLE run");
        Arrays.fill(expected, column * 200 + y0, column * 200 + y0 + length,
            (byte) palette);
        nextRow += length;
      }
      expect(json, at, ']'); require(nextRow == 200, "incomplete SQL RLE column");
    }
    expect(json, at, ']');
    if(refresh){Connection internal=DriverManager.getConnection("jdbc:default:connection:");
      if(!databaseCacheLoaded){codecSha256=MessageDigest.getInstance("SHA-256");
        loadKernelPack(internal);databaseCacheLoaded=true;}
      refreshPackedLiveState(internal,session);
      traverseAndProject(liveCameraX,liveCameraY,liveAngle,false);}
    int differences = 0, world = 0, hud = 0;
    int minColumn = WIDTH, maxColumn = -1, minRow = 200, maxRow = -1;
    StringBuilder samples = new StringBuilder();
    for (int index = 0; index < expected.length; index++) {
      if ((expected[index] & 255) == (finalFrame[index] & 255)) continue;
      int column = index / 200, row = index % 200;
      if (differences < 12) {
        int owningSector = -1;
        for (int interval = intervalOffset[column];
             interval < intervalOffset[column] + intervalCount[column]; interval++) {
          int sector = intervalSector[interval];
          double distance = row < 100 ? planeCeilingDistance[sector * 200 + row] :
              planeFloorDistance[sector * 200 + row];
          if (distance >= intervalStart[interval] && distance < intervalEnd[interval]) {
            owningSector = sector; break;
          }
        }
        samples.append('|').append(column).append(',').append(row)
            .append(',').append(expected[index] & 255).append(',').append(finalFrame[index] & 255)
            .append(',').append(wallFrame[index] >= 0 ? 'W' : 'P').append(',').append(owningSector);
      }
      differences++; if (row < 168) world++; else hud++;
      minColumn = Math.min(minColumn, column); maxColumn = Math.max(maxColumn, column);
      minRow = Math.min(minRow, row); maxRow = Math.max(maxRow, row);
    }
    return differences + "|" + world + "|" + hud + "|" + minColumn + "|" +
        maxColumn + "|" + minRow + "|" + maxRow + samples;
  }

  public static String compareSqlPayload(String session,Blob sqlPayload) throws Exception {
    return compareSqlPayloadInternal(session,sqlPayload,true);
  }

  public static String compareCurrentSqlPayload(Blob sqlPayload) throws Exception {
    require(databaseCacheLoaded,"renderer cache not loaded");
    return compareSqlPayloadInternal(null,sqlPayload,false);
  }

  public static long lastRenderNanos() { return lastRenderNanos; }
  public static long lastCodecNanos() { return lastCodecNanos; }
  public static long lastBlobNanos() { return lastBlobNanos; }
  public static long lastBspNanos() { return lastBspNanos; }
  public static long lastSolidNanos() { return lastSolidNanos; }
  public static long lastPortalNanos() { return lastPortalNanos; }
  public static long lastPortalResetNanos(){return lastPortalResetNanos;}
  public static long lastPortalSortNanos(){return lastPortalSortNanos;}
  public static long lastPortalWalkNanos(){return lastPortalWalkNanos;}
  public static long lastPlaneNanos() { return lastPlaneNanos; }
  public static long lastSpriteNanos() { return lastSpriteNanos; }
  public static long lastPresentationNanos() { return lastPresentationNanos; }
  public static String lastCardinality(){return projectedSegs+"|"+candidatePairs+"|"+
    acceptedPairs+"|"+visiblePairs+"|"+activePortalPairs+"|"+intervalTotal+"|"+
    orderedHitTotal+"|"+largeSortColumns+"|"+wallRowAttempts+"|"+planeRowAttempts+"|"+
    occludedBboxes;}
  public static long lastKernelLoadNanos() { return lastKernelLoadNanos; }
  public static long lastSnapshotNanos() { return lastSnapshotNanos; }
  static long retainedUpdateNanos() { return lastRetainedUpdateNanos; }
  /** Canonical reviewed combat ray; the retained simulator must not rederive projection trig. */
  static double combatRayX(int angle,int column){
    require(angle>=0&&angle<ANGLES&&column>=0&&column<WIDTH,"combat ray index");
    return rayXProfile[angle*WIDTH+column];
  }
  static double combatRayY(int angle,int column){
    require(angle>=0&&angle<ANGLES&&column>=0&&column<WIDTH,"combat ray index");
    return rayYProfile[angle*WIDTH+column];
  }
  static double combatFarDistance(){require(farDistance>0,"combat far distance");return farDistance;}

  private static byte[] gunzip(byte[] bytes, int length) throws Exception {
    try (GZIPInputStream input = new GZIPInputStream(new ByteArrayInputStream(bytes, 0, length));
         ByteArrayOutputStream output = new ByteArrayOutputStream(codecJson.length)) {
      byte[] chunk = new byte[8192];
      int count;
      while ((count = input.read(chunk)) >= 0) output.write(chunk, 0, count);
      return output.toByteArray();
    }
  }

  private static boolean equalPrefix(byte[] left, int leftLength, byte[] right) {
    if (leftLength != right.length) return false;
    for (int index = 0; index < leftLength; index++)
      if (left[index] != right[index]) return false;
    return true;
  }

  private static void runCodecOnly(double px, double py) throws Exception {
    traverseAndProject(px, py, 0, false);
    encodePackedTicZeroPayload(ZERO_SHA);
    byte[] packedRoundTrip = gunzip(codecGzip, codecGzipLength);
    require(equalPrefix(codecJson, codecJsonLength, packedRoundTrip),
        "packed gzip round trip differs from canonical payload");
    String packedJson = new String(packedRoundTrip, StandardCharsets.UTF_8);
    String marker = "\"frame_b64\":\"";
    int frameStart = packedJson.indexOf(marker) + marker.length();
    int frameEnd = packedJson.indexOf('"', frameStart);
    require(frameStart >= marker.length() && frameEnd > frameStart,
        "packed frame_b64 missing");
    require(Arrays.equals(codecFrame,
        Base64.getDecoder().decode(packedJson.substring(frameStart, frameEnd))),
        "packed frame_b64 differs from indexed frame");
    for (int index = 0; index < 1000; index++) encodePackedTicZeroPayload(ZERO_SHA);
    int count = 1500;
    long[] sha = new long[count], json = new long[count], gzip = new long[count], total = new long[count];
    for (int index = 0; index < count; index++) {
      long t0 = System.nanoTime();
      prepareFrameSha();
      long t1 = System.nanoTime();
      buildPackedLiveJson(ZERO_SHA);
      long t2 = System.nanoTime();
      compressJson();
      long t3 = System.nanoTime();
      sha[index] = t1 - t0; json[index] = t2 - t1; gzip[index] = t3 - t2;
      total[index] = t3 - t0; sink += codecGzipLength + codecGzip[10];
    }
    Arrays.sort(sha); Arrays.sort(json); Arrays.sort(gzip); Arrays.sort(total);
    System.out.printf(java.util.Locale.ROOT,
        "PACKED_CODEC json_bytes=%d gzip_bytes=%d sha_p95_ms=%.6f " +
        "json_p95_ms=%.6f gzip_p95_ms=%.6f total_p50_ms=%.6f total_p95_ms=%.6f%n",
        codecJsonLength, codecGzipLength, percentile(sha, .95),
        percentile(json, .95), percentile(gzip, .95), percentile(total, .50),
        percentile(total, .95));
  }

  public static void main(String[] args) throws Exception {
    require(args.length == 1 || (args.length == 2 && "--codec-only".equals(args[1])),
        "usage: DoomBspKernelBench PASSWORD_FILE [--codec-only]");
    codecSha256 = MessageDigest.getInstance("SHA-256");
    String password = new String(Files.readAllBytes(Paths.get(args[0])), StandardCharsets.UTF_8).trim();
    long loadStart = System.nanoTime();
    try (Connection connection = DriverManager.getConnection(
        "jdbc:oracle:thin:@127.0.0.1:1521/FREEPDB1", "DOOM", password)) {
      password = null;
      load(connection);
      double loadMs = (System.nanoTime() - loadStart) / 1_000_000.0;
      double px = -416, py = 256;
      if (args.length == 2) {
        runCodecOnly(px, py);
        return;
      }
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
          portalOracle[17] == 0 && portalOracle[18] == 0 && portalOracle[19] == 0 &&
          portalOracle[21] == 0 && portalOracle[22] == 0 && portalOracle[23] == 0,
          "portal walk differs from production SQL: missing=" + portalOracle[1] +
          " extra=" + portalOracle[2] + " clip_mismatch=" + portalOracle[3] +
          " wall_missing=" + portalOracle[5] + " wall_color=" + portalOracle[6] +
          " wall_extra=" + portalOracle[7] + " world_missing=" + portalOracle[9] +
          " world_color=" + portalOracle[10] + " world_extra=" + portalOracle[11] +
          " masked_missing=" + portalOracle[13] + " masked_color=" + portalOracle[14] +
          " masked_extra=" + portalOracle[15] + " full_masked_missing=" + portalOracle[17] +
          " full_masked_color=" + portalOracle[18] + " full_masked_extra=" + portalOracle[19] +
          " presentation_missing=" + portalOracle[21] +
          " presentation_color=" + portalOracle[22] +
          " presentation_extra=" + portalOracle[23]);

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
      for (int i = 0; i < 1000; i++) encodePackedTicZeroPayload(ZERO_SHA);
      int codecSampleCount = 3000;
      long[] codecSamples = new long[codecSampleCount];
      for (int i = 0; i < codecSampleCount; i++) {
        long start = System.nanoTime();
        encodePackedTicZeroPayload(ZERO_SHA);
        codecSamples[i] = System.nanoTime() - start;
        sink += codecGzipLength + codecGzip[10];
      }
      Arrays.sort(codecSamples);
      long[] compositeSamples = new long[codecSampleCount];
      for (int i = 0; i < codecSampleCount; i++) {
        long start = System.nanoTime();
        traverseAndProject(px + (i % 7) - 3, py + (i % 11) - 5, i % ANGLES, false);
        encodePackedTicZeroPayload(ZERO_SHA);
        compositeSamples[i] = System.nanoTime() - start;
        sink += codecGzipLength + codecGzip[10];
      }
      Arrays.sort(compositeSamples);
      double retention = auditCandidates / (12.0 * segTotal * WIDTH);
      double visibleRetention = auditVisibleCandidates / (12.0 * segTotal * WIDTH);
      double p95 = percentile(samples, .95);
      double codecP95 = percentile(codecSamples, .95);
      double compositeP95 = percentile(compositeSamples, .95);
      require(p95 <= 12.0, "no-JDBC composite p95 gate failed: " + p95 + " ms");
      require(codecP95 <= 5.0, "codec p95 gate failed: " + codecP95 + " ms");
      require(compositeP95 <= 20.0,
          "renderer+codec p95 gate failed: " + compositeP95 + " ms");
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
          "sql_presentation=%d presentation_missing=%d presentation_color=%d presentation_extra=%d " +
          "oracle_rle_runs=%d packed_json_bytes=%d packed_gzip_bytes=%d " +
          "codec_p50_ms=%.6f codec_p95_ms=%.6f " +
          "composite_p50_ms=%.6f composite_p95_ms=%.6f " +
          "max_nodes=%d max_ssectors=%d sink=%d%n",
          loadMs, percentile(samples, .50), p95, percentile(samples, .99),
          auditAccepted, auditMissing, retention, auditVisible, auditVisibleMissing,
          visibleRetention, portalOracle[0], portalOracle[1], portalOracle[2], portalOracle[3],
          portalOracle[4], portalOracle[5], portalOracle[6], portalOracle[7],
          portalOracle[8], portalOracle[9], portalOracle[10], portalOracle[11],
          portalOracle[12], portalOracle[13], portalOracle[14], portalOracle[15],
          portalOracle[16], portalOracle[17], portalOracle[18], portalOracle[19],
          portalOracle[20], portalOracle[21], portalOracle[22], portalOracle[23],
          codecRunCount, codecJsonLength, codecGzipLength,
          percentile(codecSamples, .50), codecP95,
          percentile(compositeSamples, .50), compositeP95,
          maxNodes, maxSubsectors, sink);
    }
  }
}
