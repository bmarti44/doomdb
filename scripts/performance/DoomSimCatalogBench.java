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
  private static final int VERSION = 1;
  private static boolean loaded;
  private static int[] nodeX, nodeY, nodeDx, nodeDy, child0, child1;
  private static byte[] child0Leaf, child1Leaf;
  private static int[] subsectorSector;
  private static int[] lineId, lineFlags, lineLeftSector, lineRightSector;
  private static int[] lineStartVertex, lineEndVertex;
  private static double[] lineX1, lineY1, lineX2, lineY2, lineLength, lineDirectionX,
      lineDirectionY;
  private static double[] baseFloor, baseCeiling;
  private static byte[][] movementDeltaX, movementDeltaY;
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
             "start_vertex_id,end_vertex_id,x1,y1,x2,y2,segment_length,direction_x,direction_y " +
             "from doom_collision_segment order by linedef_id")) {
      while (rows.next()) {
        for (int column = 1; column <= 6; column++) out.writeInt(rows.getInt(column));
        for (int column = 7; column <= 13; column++) out.writeDouble(rows.getDouble(column));
      }
    }

    try (Statement statement = connection.createStatement();
         ResultSet rows = statement.executeQuery("select count(*) from doom_map_sector")) {
      rows.next(); out.writeInt(rows.getInt(1));
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
    child0Leaf = new byte[count]; child1Leaf = new byte[count];
    child0 = new int[count]; child1 = new int[count];
    for (int id = 0; id < count; id++) {
      nodeX[id] = in.readInt(); nodeY[id] = in.readInt();
      nodeDx[id] = in.readInt(); nodeDy[id] = in.readInt();
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
    for (int id = 0; id < count; id++) {
      lineId[id] = in.readInt(); lineFlags[id] = in.readInt();
      lineLeftSector[id] = in.readInt(); lineRightSector[id] = in.readInt();
      lineStartVertex[id] = in.readInt(); lineEndVertex[id] = in.readInt();
      lineX1[id] = in.readDouble(); lineY1[id] = in.readDouble();
      lineX2[id] = in.readDouble(); lineY2[id] = in.readDouble();
      lineLength[id] = in.readDouble(); lineDirectionX[id] = in.readDouble();
      lineDirectionY[id] = in.readDouble();
    }
    count = in.readInt(); baseFloor = new double[count]; baseCeiling = new double[count];
    for (int id = 0; id < count; id++) {
      baseFloor[id] = in.readDouble(); baseCeiling[id] = in.readDouble();
    }
    count = in.readInt(); require(count == 64 * 18, "movement lookup count");
    movementDeltaX = new byte[count][]; movementDeltaY = new byte[count][];
    for (int id = 0; id < count; id++) {
      movementDeltaX[id] = readNumber(in); movementDeltaY[id] = readNumber(in);
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

  private static int movementIndex(int angleIndex, int forward, int strafe, int run) {
    require(angleIndex >= 0 && angleIndex < 64 && forward >= -1 && forward <= 1 &&
        strafe >= -1 && strafe <= 1 && run >= 0 && run <= 1, "movement lookup domain");
    return (((angleIndex * 3 + forward + 1) * 3 + strafe + 1) * 2 + run);
  }

  public static NUMBER movementX(int angleIndex, int forward, int strafe, int run) {
    try { require(loaded, "catalog not loaded"); return new NUMBER(movementDeltaX[
        movementIndex(angleIndex, forward, strafe, run)]); }
    catch (Throwable error) { lastError = error.getClass().getName() + ":" + error.getMessage(); return null; }
  }

  public static NUMBER movementY(int angleIndex, int forward, int strafe, int run) {
    try { require(loaded, "catalog not loaded"); return new NUMBER(movementDeltaY[
        movementIndex(angleIndex, forward, strafe, run)]); }
    catch (Throwable error) { lastError = error.getClass().getName() + ":" + error.getMessage(); return null; }
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
