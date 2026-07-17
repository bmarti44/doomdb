import java.io.ByteArrayInputStream;
import java.io.ByteArrayOutputStream;
import java.io.DataInputStream;
import java.io.DataOutputStream;
import java.security.MessageDigest;
import java.sql.Blob;
import java.sql.Connection;
import java.sql.DriverManager;
import java.sql.PreparedStatement;
import java.sql.ResultSet;
import java.sql.Statement;
import oracle.sql.NUMBER;

/** Immutable SQL-built simulation catalog retained by one database worker. */
public final class DoomSimCatalogBench {
  private static final int MAGIC = 0x44534350; // DSCP
  private static final int VERSION = 6;
  private static final NUMBER ZERO=NUMBER.zero();
  private static boolean loaded;
  private static int[] nodeX, nodeY, nodeDx, nodeDy, child0, child1;
  private static NUMBER[] nodeXExact,nodeYExact,nodeDxExact,nodeDyExact;
  private static byte[] child0Leaf, child1Leaf;
  private static int[] subsectorSector;
  static int[] lineId, lineFlags, lineLeftSector, lineRightSector;
  static int[] lineStartVertex, lineEndVertex;
  static double[] lineX1, lineY1, lineX2, lineY2, lineLength, lineDirectionX,
      lineDirectionY;
  static byte[][] lineLengthNumber, lineDirectionXNumber, lineDirectionYNumber;
  static NUMBER[] lineLengthExact, lineDirectionXExact, lineDirectionYExact;
  static int blockOriginX, blockOriginY, blockWidth, blockHeight;
  static int[] blockOffset, blockLines;
  static double[] baseFloor, baseCeiling;
  static byte[] rejectBits, soundReachBits;
  static int[] rngValue;
  static NUMBER[] hitscanSin;
  static NUMBER[] hitscanSpread;
  static String[] hitscanSpreadText;
  static int[] stateTics, stateNext, stateAction;
  static byte[][] movementDeltaX, movementDeltaY;
  static NUMBER[] movementXExact, movementYExact;
  private static String catalogSha = "";
  private static String lastError = "";

  private DoomSimCatalogBench() {}

  private static void require(boolean value, String message) {
    if (!value) throw new IllegalStateException(message);
  }

  private static String hex(byte[] bytes) {
    char[] chars = new char[bytes.length * 2];
    char[] digits = "0123456789abcdef".toCharArray();
    for (int index = 0; index < bytes.length; index++) {
      chars[index * 2] = digits[(bytes[index] >>> 4) & 15];
      chars[index * 2 + 1] = digits[bytes[index] & 15];
    }
    return new String(chars);
  }

  private static void writeNumber(DataOutputStream out, byte[] bytes) throws Exception {
    require(bytes != null && bytes.length >= 1 && bytes.length <= 22, "NUMBER byte length");
    out.writeByte(bytes.length); out.write(bytes);
  }

  private static byte[] readNumber(DataInputStream in) throws Exception {
    int length = in.readUnsignedByte();
    require(length >= 1 && length <= 22, "NUMBER byte length");
    byte[] bytes = new byte[length]; in.readFully(bytes); return bytes;
  }

  private static void setBit(byte[] bits, int index) {
    bits[index >>> 3] |= (byte) (1 << (index & 7));
  }

  private static boolean getBit(byte[] bits, int index) {
    return (bits[index >>> 3] & (1 << (index & 7))) != 0;
  }

  private static byte[] buildBytes(Connection connection) throws Exception {
    ByteArrayOutputStream bytes = new ByteArrayOutputStream(262144);
    DataOutputStream out = new DataOutputStream(bytes);
    out.writeInt(MAGIC); out.writeInt(VERSION);

    try (Statement statement = connection.createStatement();
         ResultSet rows = statement.executeQuery("select count(*) from doom_map_node")) {
      rows.next(); out.writeInt(rows.getInt(1));
    }
    try (Statement statement = connection.createStatement();
         ResultSet rows = statement.executeQuery(
             "select node_id,x,y,dx,dy,child0_is_ssector,child0_id," +
             "child1_is_ssector,child1_id from doom_map_node order by node_id")) {
      int expected = 0;
      while (rows.next()) {
        require(rows.getInt(1) == expected++, "node order");
        for (int column = 2; column <= 9; column++) out.writeInt(rows.getInt(column));
      }
    }

    try (Statement statement = connection.createStatement();
         ResultSet rows = statement.executeQuery("select count(*) from doom_map_ssector")) {
      rows.next(); out.writeInt(rows.getInt(1));
    }
    try (Statement statement = connection.createStatement();
         ResultSet rows = statement.executeQuery(
             "select ss.ssector_id,sd.sector_id from doom_map_ssector ss " +
             "join doom_map_seg sg on sg.seg_id=ss.first_seg_id " +
             "join doom_map_linedef ld on ld.linedef_id=sg.linedef_id " +
             "join doom_map_sidedef sd on sd.sidedef_id=case sg.direction " +
             "when 0 then ld.right_sidedef_id else ld.left_sidedef_id end " +
             "order by ss.ssector_id")) {
      int expected = 0;
      while (rows.next()) {
        require(rows.getInt(1) == expected++, "subsector order"); out.writeInt(rows.getInt(2));
      }
    }

    try (Statement statement = connection.createStatement();
         ResultSet rows = statement.executeQuery("select count(*) from doom_collision_segment")) {
      rows.next(); out.writeInt(rows.getInt(1));
    }
    try (Statement statement = connection.createStatement();
         ResultSet rows = statement.executeQuery(
             "select linedef_id,flags,coalesce(left_sector_id,-1),right_sector_id," +
             "start_vertex_id,end_vertex_id,x1,y1,x2,y2,segment_length,direction_x,direction_y," +
             "utl_raw.cast_from_number(segment_length),utl_raw.cast_from_number(direction_x)," +
             "utl_raw.cast_from_number(direction_y) " +
             "from doom_collision_segment order by linedef_id")) {
      while (rows.next()) {
        for (int column = 1; column <= 6; column++) out.writeInt(rows.getInt(column));
        for (int column = 7; column <= 13; column++) out.writeDouble(rows.getDouble(column));
        for (int column = 14; column <= 16; column++) writeNumber(out, rows.getBytes(column));
      }
    }

    int cellCount, referenceCount;
    try (Statement statement = connection.createStatement();
         ResultSet rows = statement.executeQuery(
             "select count(*),max(block_x)+1,max(block_y)+1,min(world_min_x),min(world_min_y) " +
             "from doom_block_cell")) {
      rows.next(); cellCount = rows.getInt(1); out.writeInt(rows.getInt(2));
      out.writeInt(rows.getInt(3)); out.writeInt(rows.getInt(4)); out.writeInt(rows.getInt(5));
    }
    try (Statement statement = connection.createStatement();
         ResultSet rows = statement.executeQuery("select count(*) from doom_block_line")) {
      rows.next(); referenceCount = rows.getInt(1);
    }
    int[] offsets = new int[cellCount + 1], references = new int[referenceCount];
    try (Statement statement = connection.createStatement();
         ResultSet rows = statement.executeQuery(
             "select c.cell_id,b.linedef_id from doom_block_cell c left join doom_block_line b " +
             "on b.cell_id=c.cell_id order by c.cell_id,b.line_ordinal")) {
      int currentCell = 0, reference = 0;
      while (rows.next()) {
        int cell = rows.getInt(1);
        while (currentCell < cell) offsets[++currentCell] = reference;
        int line = rows.getInt(2);
        if (!rows.wasNull()) references[reference++] = line;
      }
      while (currentCell < cellCount) offsets[++currentCell] = reference;
      require(reference == referenceCount, "block line count");
    }
    out.writeInt(cellCount); out.writeInt(referenceCount);
    for (int value : offsets) out.writeInt(value);
    for (int value : references) out.writeInt(value);

    int sectorCount;
    try (Statement statement = connection.createStatement();
         ResultSet rows = statement.executeQuery("select count(*) from doom_map_sector")) {
      rows.next(); sectorCount = rows.getInt(1); out.writeInt(sectorCount);
    }
    try (Statement statement = connection.createStatement();
         ResultSet rows = statement.executeQuery(
             "select sector_id,floor_height,ceiling_height from doom_map_sector order by sector_id")) {
      int expected = 0;
      while (rows.next()) {
        require(rows.getInt(1) == expected++, "sector order");
        out.writeDouble(rows.getDouble(2)); out.writeDouble(rows.getDouble(3));
      }
    }

    int pairCount = sectorCount * sectorCount, bitBytes = (pairCount + 7) >>> 3;
    byte[] reject = new byte[bitBytes], sound = new byte[bitBytes];
    try (Statement statement = connection.createStatement();
         ResultSet rows = statement.executeQuery(
             "select s.sector_id,t.sector_id,coalesce(r.rejected,1) " +
             "from doom_map_sector s cross join doom_map_sector t " +
             "left join doom_sector_reject r on r.source_sector_id=s.sector_id " +
             "and r.target_sector_id=t.sector_id order by s.sector_id,t.sector_id")) {
      int index = 0;
      while (rows.next()) {
        require(rows.getInt(1) == index / sectorCount &&
            rows.getInt(2) == index % sectorCount, "REJECT pair order");
        if (rows.getInt(3) != 0) setBit(reject, index); index++;
      }
      require(index == pairCount, "REJECT pair count");
    }
    try (Statement statement = connection.createStatement();
         ResultSet rows = statement.executeQuery(
             "select s.sector_id,t.sector_id,case when r.source_sector_id is null then 0 else 1 end " +
             "from doom_map_sector s cross join doom_map_sector t " +
             "left join doom_sector_sound_reach r on r.source_sector_id=s.sector_id " +
             "and r.target_sector_id=t.sector_id order by s.sector_id,t.sector_id")) {
      int index = 0;
      while (rows.next()) {
        require(rows.getInt(1) == index / sectorCount &&
            rows.getInt(2) == index % sectorCount, "sound pair order");
        if (rows.getInt(3) != 0) setBit(sound, index); index++;
      }
      require(index == pairCount, "sound pair count");
    }
    out.writeInt(sectorCount); out.writeInt(bitBytes); out.write(reject); out.write(sound);

    try (Statement statement = connection.createStatement();
         ResultSet rows = statement.executeQuery(
             "select rng_index,rng_value from doom_rng_value order by rng_index")) {
      int index = 0; out.writeInt(256);
      while (rows.next()) {
        require(rows.getInt(1) == index, "RNG order"); out.writeInt(rows.getInt(2)); index++;
      }
      require(index == 256, "RNG count");
    }

    out.writeInt(511);
    try (Statement statement = connection.createStatement();
         ResultSet rows = statement.executeQuery(
             "select level-256 spread_difference," +
             "utl_raw.cast_from_number((level-256)*2*acos(-1)/4096)," +
             "utl_raw.cast_from_number(sin((level-256)*2*acos(-1)/4096))," +
             "to_char((level-256)*2*acos(-1)/4096,'TM9'," +
             "'NLS_NUMERIC_CHARACTERS=''.,''') " +
             "from dual connect by level<=511 order by spread_difference")) {
      int difference = -255;
      while (rows.next()) {
        require(rows.getInt(1) == difference++, "hitscan spread order");
        writeNumber(out, rows.getBytes(2)); writeNumber(out, rows.getBytes(3));
        out.writeUTF(rows.getString(4));
      }
      require(difference == 256, "hitscan spread count");
    }

    int stateCount;
    try (Statement statement = connection.createStatement();
         ResultSet rows = statement.executeQuery("select count(*) from doom_state_def")) {
      rows.next(); stateCount = rows.getInt(1); out.writeInt(stateCount);
    }
    try (Statement statement = connection.createStatement();
         ResultSet rows = statement.executeQuery(
             "select s.state_index,s.tics,coalesce(n.state_index,-1)," +
             "case s.action_name when 'CHASE' then 1 when 'MELEE' then 2 " +
             "when 'HITSCAN' then 3 when 'PROJECTILE' then 4 else 0 end " +
             "from (select d.*,row_number() over(order by state_id)-1 state_index " +
             "from doom_state_def d) s left join " +
             "(select state_id,row_number() over(order by state_id)-1 state_index " +
             "from doom_state_def) n on n.state_id=s.next_state_id order by s.state_index")) {
      int index = 0;
      while (rows.next()) {
        require(rows.getInt(1) == index, "state order");
        out.writeInt(rows.getInt(2)); out.writeInt(rows.getInt(3)); out.writeInt(rows.getInt(4));
        index++;
      }
      require(index == stateCount, "state count");
    }

    String movementSql =
        "select utl_raw.cast_from_number((f*cos(a*acos(-1)/180)+s*sin(a*acos(-1)/180))*8*(r+1))," +
        "utl_raw.cast_from_number((f*sin(a*acos(-1)/180)-s*cos(a*acos(-1)/180))*8*(r+1)) " +
        "from (select (level-1)*5.625 a from dual connect by level<=64) cross join " +
        "(select level-2 f from dual connect by level<=3) cross join " +
        "(select level-2 s from dual connect by level<=3) cross join " +
        "(select level-1 r from dual connect by level<=2) order by a,f,s,r";
    out.writeInt(64 * 18);
    try (Statement statement = connection.createStatement();
         ResultSet rows = statement.executeQuery(movementSql)) {
      int count = 0;
      while (rows.next()) {
        writeNumber(out, rows.getBytes(1)); writeNumber(out, rows.getBytes(2)); count++;
      }
      require(count == 64 * 18, "movement lookup count");
    }
    out.flush(); return bytes.toByteArray();
  }

  public static String buildCatalog() {
    try {
      Connection connection = DriverManager.getConnection("jdbc:default:connection:");
      byte[] bytes = buildBytes(connection);
      String sha = hex(MessageDigest.getInstance("SHA-256").digest(bytes));
      try (PreparedStatement statement = connection.prepareStatement(
          "select encoded_bytes from doom_renderer_asset_pack " +
          "where asset_kind='simulation_kernel' for update")) {
        try (ResultSet rows = statement.executeQuery()) {
          require(rows.next(), "simulation kernel placeholder missing");
          Blob blob = rows.getBlob(1); blob.truncate(0);
          for (int offset = 0; offset < bytes.length;) {
            int count = Math.min(32767, bytes.length - offset);
            require(blob.setBytes(offset + 1L, bytes, offset, count) == count, "short BLOB write");
            offset += count;
          }
          blob.free(); require(!rows.next(), "simulation kernel duplicate");
        }
      }
      try (PreparedStatement statement = connection.prepareStatement(
          "update doom_renderer_asset_pack set element_count=?,payload_sha256=? " +
          "where asset_kind='simulation_kernel'")) {
        statement.setInt(1, bytes.length); statement.setString(2, sha);
        require(statement.executeUpdate() == 1, "simulation kernel metadata update");
      }
      lastError = ""; return "OK|" + bytes.length + "|" + sha;
    } catch (Throwable error) {
      loaded = false; lastError = error.getClass().getName() + ":" + error.getMessage();
      return "ERR|" + lastError;
    }
  }

  private static void decode(byte[] bytes) throws Exception {
    DataInputStream in = new DataInputStream(new ByteArrayInputStream(bytes));
    require(in.readInt() == MAGIC && in.readInt() == VERSION, "catalog header");
    int count = in.readInt();
    nodeX = new int[count]; nodeY = new int[count]; nodeDx = new int[count]; nodeDy = new int[count];
    nodeXExact=new NUMBER[count];nodeYExact=new NUMBER[count];
    nodeDxExact=new NUMBER[count];nodeDyExact=new NUMBER[count];
    child0Leaf = new byte[count]; child1Leaf = new byte[count];
    child0 = new int[count]; child1 = new int[count];
    for (int id = 0; id < count; id++) {
      nodeX[id] = in.readInt(); nodeY[id] = in.readInt();
      nodeXExact[id]=new NUMBER((long)nodeX[id]);nodeYExact[id]=new NUMBER((long)nodeY[id]);
      nodeDx[id] = in.readInt(); nodeDy[id] = in.readInt();
      nodeDxExact[id]=new NUMBER((long)nodeDx[id]);nodeDyExact[id]=new NUMBER((long)nodeDy[id]);
      child0Leaf[id] = (byte) in.readInt(); child0[id] = in.readInt();
      child1Leaf[id] = (byte) in.readInt(); child1[id] = in.readInt();
    }
    count = in.readInt(); subsectorSector = new int[count];
    for (int id = 0; id < count; id++) subsectorSector[id] = in.readInt();
    count = in.readInt();
    lineId = new int[count]; lineFlags = new int[count]; lineLeftSector = new int[count];
    lineRightSector = new int[count]; lineStartVertex = new int[count]; lineEndVertex = new int[count];
    lineX1 = new double[count]; lineY1 = new double[count]; lineX2 = new double[count];
    lineY2 = new double[count]; lineLength = new double[count];
    lineDirectionX = new double[count]; lineDirectionY = new double[count];
    lineLengthNumber = new byte[count][]; lineDirectionXNumber = new byte[count][];
    lineDirectionYNumber = new byte[count][];
    lineLengthExact = new NUMBER[count]; lineDirectionXExact = new NUMBER[count];
    lineDirectionYExact = new NUMBER[count];
    for (int id = 0; id < count; id++) {
      lineId[id] = in.readInt(); lineFlags[id] = in.readInt();
      lineLeftSector[id] = in.readInt(); lineRightSector[id] = in.readInt();
      lineStartVertex[id] = in.readInt(); lineEndVertex[id] = in.readInt();
      lineX1[id] = in.readDouble(); lineY1[id] = in.readDouble();
      lineX2[id] = in.readDouble(); lineY2[id] = in.readDouble();
      lineLength[id] = in.readDouble(); lineDirectionX[id] = in.readDouble();
      lineDirectionY[id] = in.readDouble();
      lineLengthNumber[id] = readNumber(in); lineDirectionXNumber[id] = readNumber(in);
      lineDirectionYNumber[id] = readNumber(in);
      lineLengthExact[id] = new NUMBER(lineLengthNumber[id]);
      lineDirectionXExact[id] = new NUMBER(lineDirectionXNumber[id]);
      lineDirectionYExact[id] = new NUMBER(lineDirectionYNumber[id]);
    }
    blockWidth = in.readInt(); blockHeight = in.readInt();
    blockOriginX = in.readInt(); blockOriginY = in.readInt();
    int cellCount = in.readInt(), referenceCount = in.readInt();
    require(cellCount == blockWidth * blockHeight, "block dimensions");
    blockOffset = new int[cellCount + 1]; blockLines = new int[referenceCount];
    for (int index = 0; index < blockOffset.length; index++) blockOffset[index] = in.readInt();
    for (int index = 0; index < blockLines.length; index++) blockLines[index] = in.readInt();
    count = in.readInt(); baseFloor = new double[count]; baseCeiling = new double[count];
    for (int id = 0; id < count; id++) {
      baseFloor[id] = in.readDouble(); baseCeiling[id] = in.readDouble();
    }
    int matrixSectors = in.readInt(), bitBytes = in.readInt();
    require(matrixSectors == count && bitBytes == (count * count + 7) / 8,
        "sector matrix dimensions");
    rejectBits = new byte[bitBytes]; soundReachBits = new byte[bitBytes];
    in.readFully(rejectBits); in.readFully(soundReachBits);
    int rngCount = in.readInt(); require(rngCount == 256, "RNG count");
    rngValue = new int[rngCount];
    for (int index = 0; index < rngCount; index++) {
      rngValue[index] = in.readInt(); require(rngValue[index] >= 0 && rngValue[index] <= 255, "RNG value");
    }
    int spreadCount = in.readInt(); require(spreadCount == 511, "hitscan spread count");
    hitscanSpread = new NUMBER[spreadCount]; hitscanSin = new NUMBER[spreadCount];
    hitscanSpreadText = new String[spreadCount];
    for (int index = 0; index < spreadCount; index++) {
      hitscanSpread[index] = new NUMBER(readNumber(in));
      hitscanSin[index] = new NUMBER(readNumber(in)); hitscanSpreadText[index] = in.readUTF();
    }
    int stateCount = in.readInt(); require(stateCount > 0 && stateCount <= 4096, "state count");
    stateTics = new int[stateCount]; stateNext = new int[stateCount]; stateAction = new int[stateCount];
    for (int index = 0; index < stateCount; index++) {
      stateTics[index] = in.readInt(); stateNext[index] = in.readInt(); stateAction[index] = in.readInt();
      require(stateTics[index] >= -1 && stateNext[index] >= -1 && stateNext[index] < stateCount &&
          stateAction[index] >= 0 && stateAction[index] <= 4, "state value");
    }
    count = in.readInt(); require(count == 64 * 18, "movement lookup count");
    movementDeltaX = new byte[count][]; movementDeltaY = new byte[count][];
    movementXExact = new NUMBER[count]; movementYExact = new NUMBER[count];
    for (int id = 0; id < count; id++) {
      movementDeltaX[id] = readNumber(in); movementDeltaY[id] = readNumber(in);
      movementXExact[id] = new NUMBER(movementDeltaX[id]);
      movementYExact[id] = new NUMBER(movementDeltaY[id]);
    }
    require(in.read() == -1, "catalog trailing bytes");
  }

  public static String loadCatalog() {
    try {
      Connection connection = DriverManager.getConnection("jdbc:default:connection:");
      try (Statement statement = connection.createStatement();
           ResultSet rows = statement.executeQuery(
               "select encoded_bytes,payload_sha256 from doom_renderer_asset_pack " +
               "where asset_kind='simulation_kernel'")) {
        require(rows.next(), "simulation kernel missing"); Blob blob = rows.getBlob(1);
        require(blob.length() <= Integer.MAX_VALUE, "simulation kernel too large");
        byte[] bytes = blob.getBytes(1, (int) blob.length()); blob.free();
        String expectedSha = rows.getString(2); require(!rows.next(), "simulation kernel duplicate");
        String actualSha = hex(MessageDigest.getInstance("SHA-256").digest(bytes));
        require(actualSha.equals(expectedSha), "simulation kernel SHA mismatch");
        decode(bytes); catalogSha = actualSha;
      }
      loaded = true; lastError = ""; return summary();
    } catch (Throwable error) {
      loaded = false; lastError = error.getClass().getName() + ":" + error.getMessage();
      return "ERR|" + lastError;
    }
  }

  private static int side(double x, double y, int node) {
    int dx = nodeDx[node], dy = nodeDy[node];
    if (dx == 0) return x <= nodeX[node] ? (dy > 0 ? 1 : 0) : (dy < 0 ? 1 : 0);
    if (dy == 0) return y <= nodeY[node] ? (dx < 0 ? 1 : 0) : (dx > 0 ? 1 : 0);
    return (x - nodeX[node]) * dy - (y - nodeY[node]) * dx > 0 ? 0 : 1;
  }

  public static int locateSector(double x, double y) {
    try {
      require(loaded, "catalog not loaded"); require(Double.isFinite(x) && Double.isFinite(y), "point");
      int node = nodeX.length - 1;
      while (true) {
        int side = side(x, y, node);
        boolean leaf = side == 0 ? child0Leaf[node] != 0 : child1Leaf[node] != 0;
        int child = side == 0 ? child0[node] : child1[node];
        if (leaf) { require(child >= 0 && child < subsectorSector.length, "subsector"); return subsectorSector[child]; }
        require(child >= 0 && child < nodeX.length, "node child"); node = child;
      }
    } catch (Throwable error) {
      lastError = error.getClass().getName() + ":" + error.getMessage(); return -1;
    }
  }

  static int locateSector(NUMBER x,NUMBER y)throws Exception{
    require(loaded&&x!=null&&y!=null,"exact point");int node=nodeX.length-1;
    while(true){int dx=nodeDx[node],dy=nodeDy[node],side;
      if(dx==0)side=x.compareTo(nodeXExact[node])<=0?(dy>0?1:0):(dy<0?1:0);
      else if(dy==0)side=y.compareTo(nodeYExact[node])<=0?(dx<0?1:0):(dx>0?1:0);
      else side=x.sub(nodeXExact[node]).mul(nodeDyExact[node])
          .sub(y.sub(nodeYExact[node]).mul(nodeDxExact[node])).compareTo(ZERO)>0?0:1;
      boolean leaf=side==0?child0Leaf[node]!=0:child1Leaf[node]!=0;
      int child=side==0?child0[node]:child1[node];
      if(leaf){require(child>=0&&child<subsectorSector.length,"exact subsector");
        return subsectorSector[child];}
      require(child>=0&&child<nodeX.length,"exact node child");node=child;
    }
  }

  private static int movementIndex(int angleIndex, int forward, int strafe, int run) {
    require(angleIndex >= 0 && angleIndex < 64 && forward >= -1 && forward <= 1 &&
        strafe >= -1 && strafe <= 1 && run >= 0 && run <= 1, "movement lookup domain");
    return (((angleIndex * 3 + forward + 1) * 3 + strafe + 1) * 2 + run);
  }

  public static NUMBER movementX(int angleIndex, int forward, int strafe, int run) {
    try { require(loaded, "catalog not loaded"); return movementXExact[
        movementIndex(angleIndex, forward, strafe, run)]; }
    catch (Throwable error) { lastError = error.getClass().getName() + ":" + error.getMessage(); return null; }
  }

  public static NUMBER movementY(int angleIndex, int forward, int strafe, int run) {
    try { require(loaded, "catalog not loaded"); return movementYExact[
        movementIndex(angleIndex, forward, strafe, run)]; }
    catch (Throwable error) { lastError = error.getClass().getName() + ":" + error.getMessage(); return null; }
  }

  private static int sectorPairIndex(int source, int target) {
    require(source >= 0 && source < baseFloor.length && target >= 0 &&
        target < baseFloor.length, "sector pair");
    return source * baseFloor.length + target;
  }

  public static int rejected(int source, int target) {
    try { require(loaded, "catalog not loaded");
      return getBit(rejectBits, sectorPairIndex(source, target)) ? 1 : 0;
    } catch (Throwable error) {
      lastError = error.getClass().getName() + ":" + error.getMessage(); return -1;
    }
  }

  public static int soundReach(int source, int target) {
    try { require(loaded, "catalog not loaded");
      return getBit(soundReachBits, sectorPairIndex(source, target)) ? 1 : 0;
    } catch (Throwable error) {
      lastError = error.getClass().getName() + ":" + error.getMessage(); return -1;
    }
  }

  public static int rng(int index) {
    try { require(loaded && index >= 0 && index < 256, "RNG index"); return rngValue[index]; }
    catch (Throwable error) {
      lastError = error.getClass().getName() + ":" + error.getMessage(); return -1;
    }
  }

  public static NUMBER hitscanSin(int difference) {
    try {
      require(loaded && difference >= -255 && difference <= 255, "hitscan spread difference");
      return hitscanSin[difference + 255];
    } catch (Throwable error) {
      lastError = error.getClass().getName() + ":" + error.getMessage(); return null;
    }
  }

  public static NUMBER hitscanSpread(int difference) {
    try {
      require(loaded && difference >= -255 && difference <= 255, "hitscan spread difference");
      return hitscanSpread[difference + 255];
    } catch (Throwable error) {
      lastError = error.getClass().getName() + ":" + error.getMessage(); return null;
    }
  }

  public static String hitscanSpreadText(int difference) {
    try {
      require(loaded && difference >= -255 && difference <= 255, "hitscan spread difference");
      return hitscanSpreadText[difference + 255];
    } catch (Throwable error) {
      lastError = error.getClass().getName() + ":" + error.getMessage(); return null;
    }
  }

  public static int stateTics(int index) {
    try { require(loaded && index >= 0 && index < stateTics.length, "state index"); return stateTics[index]; }
    catch (Throwable error) { lastError = error.getClass().getName() + ":" + error.getMessage(); return -2; }
  }
  public static int stateNext(int index) {
    try { require(loaded && index >= 0 && index < stateNext.length, "state index"); return stateNext[index]; }
    catch (Throwable error) { lastError = error.getClass().getName() + ":" + error.getMessage(); return -2; }
  }
  public static int stateAction(int index) {
    try { require(loaded && index >= 0 && index < stateAction.length, "state index"); return stateAction[index]; }
    catch (Throwable error) { lastError = error.getClass().getName() + ":" + error.getMessage(); return -1; }
  }

  public static String summary() {
    try {
      require(loaded, "catalog not loaded");
      return "OK|" + nodeX.length + "|" + subsectorSector.length + "|" + lineId.length +
          "|" + baseFloor.length + "|" + movementDeltaX.length + "|" + catalogSha;
    } catch (Throwable error) {
      lastError = error.getClass().getName() + ":" + error.getMessage(); return "ERR|" + lastError;
    }
  }

  public static String lastError() {
    try { return lastError; } catch (Throwable error) { return error.getClass().getName(); }
  }
}
