import java.math.BigDecimal;
import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.sql.Blob;
import java.sql.Connection;
import java.sql.DriverManager;
import java.sql.PreparedStatement;
import java.sql.ResultSet;
import java.util.Arrays;

public final class DoomStateCodecBench {
  private static byte[] output = new byte[262144];
  private static int length;
  private static MessageDigest sha256;
  private static long lastQueryNanos;
  private static long lastEncodeNanos;
  private static long lastBlobNanos;
  private static long lastTotalNanos;

  private static final String SESSION_SQL =
      "select s.skill,s.current_player_id,s.current_tic,s.rng_cursor,s.game_mode," +
      "s.map_status,s.paused,s.menu_state,s.automap_state,s.last_command_seq,s.save_lineage," +
      "p.player_id,p.x,p.y,p.z,p.momentum_x,p.momentum_y,p.momentum_z,p.angle," +
      "p.view_height,p.view_bob,p.health,p.armor,p.armor_type,p.blue_key,p.yellow_key," +
      "p.red_key,p.ammo_bullets,p.ammo_shells,p.ammo_rockets,p.ammo_cells,p.weapon_mask," +
      "p.selected_weapon,p.pending_weapon,p.weapon_state,p.weapon_state_tics,p.flash_state," +
      "p.flash_state_tics,p.refire,p.backpack,p.power_berserk,p.power_invulnerability," +
      "p.power_invisibility,p.power_ironfeet,p.power_lightamp,p.kill_count,p.item_count," +
      "p.secret_count,p.alive,p.noclip " +
      "from game_sessions s join players p on p.session_token=s.session_token " +
      "and p.player_id=s.current_player_id where s.session_token=?";

  private static final String MOBJ_SQL =
      "select mobj_id,thing_type,state_id,state_tics,x,y,z,momentum_x,momentum_y," +
      "momentum_z,angle,radius,height,health,flags,target_mobj_id,tracer_mobj_id," +
      "reaction_time,spawn_thing_id,owner_mobj_id,projectile_kind,exploded,sector_id," +
      "move_direction,awake,attack_cooldown,monster_health_seen,death_processed " +
      "from mobjs where session_token=? order by mobj_id";
  private static final String[] MOBJ_KEYS = {
      "mobj_id","thing_type","state_id","state_tics","x","y","z","momentum_x",
      "momentum_y","momentum_z","angle","radius","height","health","flags",
      "target_mobj_id","tracer_mobj_id","reaction_time","spawn_thing_id",
      "owner_mobj_id","projectile_kind","exploded","sector_id","move_direction",
      "awake","attack_cooldown","monster_health_seen","death_processed"};
  private static final boolean[] MOBJ_STRING = flags(28, 2, 20);

  private static final String SECTOR_SQL =
      "select sector_id,floor_height,ceiling_height,light_level,light_timer," +
      "secret_found,damage_clock from sector_state where session_token=? order by sector_id";
  private static final String[] SECTOR_KEYS = {"sector_id","floor_height","ceiling_height",
      "light_level","light_timer","secret_found","damage_clock"};
  private static final boolean[] SECTOR_STRING = flags(7);

  private static final String LINE_SQL =
      "select linedef_id,trigger_count,switch_on from line_state " +
      "where session_token=? order by linedef_id";
  private static final String[] LINE_KEYS = {"linedef_id","trigger_count","switch_on"};
  private static final boolean[] LINE_STRING = flags(3);

  private static final String MOVER_SQL =
      "select mover_id,sector_id,plane,direction,speed,target_height,wait_tics,timer_tics," +
      "mover_kind,origin_height,source_linedef_id from active_movers " +
      "where session_token=? order by mover_id";
  private static final String[] MOVER_KEYS = {"mover_id","sector_id","plane","direction",
      "speed","target_height","wait_tics","timer_tics","mover_kind","origin_height",
      "source_linedef_id"};
  private static final boolean[] MOVER_STRING = flags(11, 2, 8);

  private static final String SWITCH_SQL =
      "select linedef_id,timer_tics,restore_texture from active_switches " +
      "where session_token=? order by linedef_id";
  private static final String[] SWITCH_KEYS = {"linedef_id","timer_tics","restore_texture"};
  private static final boolean[] SWITCH_STRING = flags(3, 2);

  private DoomStateCodecBench() {}

  private static boolean[] flags(int size, int... indexes) {
    boolean[] result = new boolean[size];
    for (int index : indexes) result[index] = true;
    return result;
  }

  private static void ensure(int needed) {
    if (length + needed <= output.length) return;
    output = Arrays.copyOf(output, Math.max(output.length * 2, length + needed));
  }

  private static void ascii(String value) {
    ensure(value.length());
    for (int i = 0; i < value.length(); i++) output[length++] = (byte) value.charAt(i);
  }

  private static void quoted(String value) {
    if (value == null) { ascii("null"); return; }
    ensure(value.length() * 3 + 2);
    output[length++] = '"';
    for (int offset = 0; offset < value.length();) {
      int codepoint = value.codePointAt(offset);
      offset += Character.charCount(codepoint);
      if (codepoint == '"' || codepoint == '\\') {
        output[length++] = '\\'; output[length++] = (byte) codepoint;
      } else if (codepoint == '\b') ascii("\\b");
      else if (codepoint == '\f') ascii("\\f");
      else if (codepoint == '\n') ascii("\\n");
      else if (codepoint == '\r') ascii("\\r");
      else if (codepoint == '\t') ascii("\\t");
      else if (codepoint < 32) {
        ascii(String.format("\\u%04x", codepoint));
      } else {
        byte[] bytes = new String(Character.toChars(codepoint)).getBytes(StandardCharsets.UTF_8);
        ensure(bytes.length);
        System.arraycopy(bytes, 0, output, length, bytes.length); length += bytes.length;
      }
    }
    output[length++] = '"';
  }

  private static void number(BigDecimal value) {
    if (value == null) { ascii("null"); return; }
    value = value.stripTrailingZeros();
    ascii(value.signum() == 0 ? "0" : value.toPlainString());
  }

  private static void key(String key, boolean first) {
    if (!first) output[length++] = ',';
    quoted(key); output[length++] = ':';
  }

  private static void fieldNumber(ResultSet row, String name, int column, boolean first)
      throws Exception {
    key(name, first); number(row.getBigDecimal(column));
  }

  private static void fieldString(ResultSet row, String name, int column, boolean first)
      throws Exception {
    key(name, first); quoted(row.getString(column));
  }

  private static void array(Connection connection, String session, String name, String sql,
      String[] keys, boolean[] strings, int legacyCutoff) throws Exception {
    key(name, false); output[length++] = '[';
    try (PreparedStatement statement = connection.prepareStatement(sql)) {
      statement.setString(1, session);
      try (ResultSet rows = statement.executeQuery()) {
        boolean firstRow = true;
        while (rows.next()) {
          if (!firstRow) output[length++] = ',';
          firstRow = false; output[length++] = '{';
          int fieldCount = legacyCutoff > 0 ? legacyCutoff : keys.length;
          for (int field = 0; field < fieldCount; field++) {
            if (strings[field]) fieldString(rows, keys[field], field + 1, field == 0);
            else fieldNumber(rows, keys[field], field + 1, field == 0);
          }
          output[length++] = '}';
        }
      }
    }
    output[length++] = ']';
  }

  private static void encode(Connection connection, String session, boolean legacy) throws Exception {
    length = 0;
    long queryStarted = System.nanoTime();
    try (PreparedStatement statement = connection.prepareStatement(SESSION_SQL)) {
      statement.setString(1, session);
      try (ResultSet row = statement.executeQuery()) {
        if (!row.next()) throw new IllegalArgumentException("unknown session");
        long encodeStarted = System.nanoTime();
        output[length++] = '{';
        // Oracle's schema field is a literal, not a stored column.
        key("schema", true); ascii("1");
        fieldNumber(row,"skill",1,false);
        fieldNumber(row,"current_player_id",2,false);
        fieldNumber(row,"tic",3,false);
        fieldNumber(row,"rng_cursor",4,false);
        fieldString(row,"game_mode",5,false);
        fieldString(row,"map_status",6,false);
        fieldNumber(row,"paused",7,false);
        fieldString(row,"menu_state",8,false);
        fieldString(row,"automap_state",9,false);
        if (legacy) {
          fieldNumber(row,"last_command_seq",10,false);
          fieldString(row,"save_lineage",11,false);
        }
        key("player", false); output[length++] = '{';
        String[] playerKeys = {"player_id","x","y","z","momentum_x","momentum_y",
            "momentum_z","angle","view_height","view_bob","health","armor","armor_type",
            "blue_key","yellow_key","red_key","ammo_bullets","ammo_shells","ammo_rockets",
            "ammo_cells","weapon_mask","selected_weapon","pending_weapon","weapon_state",
            "weapon_state_tics","flash_state","flash_state_tics","refire","backpack",
            "power_berserk","power_invulnerability","power_invisibility","power_ironfeet",
            "power_lightamp","kill_count","item_count","secret_count","alive","noclip"};
        boolean[] playerStrings = flags(playerKeys.length, 21, 22, 23, 25);
        int playerCount = legacy ? 22 : playerKeys.length;
        for (int field = 0; field < playerCount; field++) {
          if (playerStrings[field]) fieldString(row,playerKeys[field],12 + field,field == 0);
          else fieldNumber(row,playerKeys[field],12 + field,field == 0);
        }
        if (legacy) {
          // Legacy keeps power-invulnerability through power-lightamp and counters/alive.
          for (int field = 30; field <= 37; field++) {
            if (playerStrings[field]) fieldString(row,playerKeys[field],12 + field,false);
            else fieldNumber(row,playerKeys[field],12 + field,false);
          }
        }
        output[length++] = '}';
        lastQueryNanos = System.nanoTime() - queryStarted;
        array(connection,session,"mobjs",MOBJ_SQL,MOBJ_KEYS,MOBJ_STRING,legacy ? 19 : 0);
        array(connection,session,"sectors",SECTOR_SQL,SECTOR_KEYS,SECTOR_STRING,0);
        array(connection,session,"lines",LINE_SQL,LINE_KEYS,LINE_STRING,0);
        array(connection,session,"movers",MOVER_SQL,MOVER_KEYS,MOVER_STRING,0);
        array(connection,session,"switches",SWITCH_SQL,SWITCH_KEYS,SWITCH_STRING,0);
        key("ordering_version", false); quoted("APPENDIX-F-1");
        output[length++] = '}';
        lastEncodeNanos = System.nanoTime() - encodeStarted;
      }
    }
  }

  public static String writeState(String session, int legacyFlag, Blob payload) throws Exception {
    long totalStarted = System.nanoTime();
    if (payload == null) throw new IllegalArgumentException("caller-owned BLOB required");
    if (sha256 == null) sha256 = MessageDigest.getInstance("SHA-256");
    Connection connection = DriverManager.getConnection("jdbc:default:connection:");
    encode(connection, session, legacyFlag == 1);
    byte[] digest = sha256.digest(Arrays.copyOf(output, length));
    long started = System.nanoTime();
    payload.truncate(0);
    int offset = 0;
    while (offset < length) {
      int count = Math.min(32767, length - offset);
      int written = payload.setBytes(offset + 1L, output, offset, count);
      if (written != count) throw new IllegalStateException("short state BLOB write");
      offset += count;
    }
    lastBlobNanos = System.nanoTime() - started;
    StringBuilder hex = new StringBuilder(64);
    for (byte value : digest) hex.append(String.format("%02x", value & 255));
    lastTotalNanos = System.nanoTime() - totalStarted;
    return hex.toString();
  }

  public static long lastQueryNanos() { return lastQueryNanos; }
  public static long lastEncodeNanos() { return lastEncodeNanos; }
  public static long lastBlobNanos() { return lastBlobNanos; }
  public static long lastTotalNanos() { return lastTotalNanos; }
}
