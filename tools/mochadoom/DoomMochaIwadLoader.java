import java.io.BufferedInputStream;
import java.io.InputStream;
import java.nio.file.Files;
import java.nio.file.Path;
import java.security.MessageDigest;
import java.sql.ResultSet;
import java.sql.Connection;
import java.sql.DriverManager;
import java.sql.PreparedStatement;
import java.util.Arrays;
import java.util.LinkedHashMap;
import java.util.Map;

/** Build-time loader for the pinned Freedoom IWAD. Never loaded into OJVM. */
public final class DoomMochaIwadLoader {
  private DoomMochaIwadLoader() {}

  public static void main(String[] args) throws Exception {
    if (args.length != 5) {
      throw new IllegalArgumentException(
          "usage: jdbc-url user iwad-path expected-sha engine-revision");
    }
    String password = System.getenv("DOOMDB_PASSWORD");
    if (password == null || password.isEmpty()) {
      throw new IllegalStateException("DOOMDB_PASSWORD is required");
    }
    Path path = Path.of(args[2]);
    String actualSha = sha256(path);
    if (!actualSha.equals(args[3])) {
      throw new IllegalStateException("IWAD SHA mismatch: " + actualSha);
    }
    try (Connection connection =
             DriverManager.getConnection(args[0], args[1], password)) {
      connection.setAutoCommit(false);
      byte[] iwad = Files.readAllBytes(path);
      try (PreparedStatement delete = connection.prepareStatement(
               "delete from doom_engine_artifact where artifact_name=?")) {
        delete.setString(1, "freedoom1.wad");
        delete.executeUpdate();
      }
      try (PreparedStatement insert = connection.prepareStatement(
               "insert into doom_engine_artifact(artifact_name,engine_revision,"
                   + "media_type,payload_sha256,payload_bytes) "
                   + "values(?,?,?,?,?)");
           InputStream input = new BufferedInputStream(
               Files.newInputStream(path))) {
        insert.setString(1, "freedoom1.wad");
        insert.setString(2, args[4]);
        insert.setString(3, "application/x-doom-wad");
        insert.setString(4, actualSha);
        insert.setBinaryStream(5, input, Files.size(path));
        if (insert.executeUpdate() != 1) {
          throw new IllegalStateException("IWAD insert count");
        }
      }
      int soundCount = loadSounds(connection, iwad);
      connection.commit();
      System.out.println("PASS MOCHADOOM-SOUND-LOAD count=" + soundCount);
    }
    System.out.println("PASS MOCHADOOM-IWAD-LOAD sha256=" + actualSha);
  }

  private static int loadSounds(Connection connection, byte[] wad)
      throws Exception {
    if (wad.length < 12 ||
        !(ascii(wad, 0, 4).equals("IWAD") || ascii(wad, 0, 4).equals("PWAD"))) {
      throw new IllegalStateException("invalid WAD header");
    }
    int count = littleInt(wad, 4);
    int directory = littleInt(wad, 8);
    if (count < 1 || directory < 12 ||
        (long) directory + (long) count * 16L > wad.length) {
      throw new IllegalStateException("invalid WAD directory");
    }
    Map<String, byte[]> sounds = new LinkedHashMap<>();
    for (int index = 0; index < count; index++) {
      int entry = directory + index * 16;
      int offset = littleInt(wad, entry);
      int length = littleInt(wad, entry + 4);
      String name = ascii(wad, entry + 8, 8).replace("\0", "");
      if (!name.matches("DS[A-Z0-9]{1,6}")) continue;
      if (offset < 0 || length < 8 || (long) offset + length > wad.length) {
        throw new IllegalStateException("invalid sound lump " + name);
      }
      sounds.put(name, Arrays.copyOfRange(wad, offset, offset + length));
    }
    int nextId;
    try (PreparedStatement select = connection.prepareStatement(
        "select coalesce(max(asset_id),-1)+1 from doom_asset");
         ResultSet rows = select.executeQuery()) {
      if (!rows.next()) throw new IllegalStateException("asset id query");
      nextId = rows.getInt(1);
    }
    for (Map.Entry<String, byte[]> sound : sounds.entrySet()) {
      String sha = sha256(sound.getValue());
      Integer assetId = null;
      String currentSha = null;
      try (PreparedStatement select = connection.prepareStatement(
          "select asset_id,raw_sha256 from doom_asset "
              + "where asset_kind='sound' and asset_name=?")) {
        select.setString(1, sound.getKey());
        try (ResultSet rows = select.executeQuery()) {
          if (rows.next()) {
            assetId = rows.getInt(1);
            currentSha = rows.getString(2);
          }
        }
      }
      if (assetId == null) {
        assetId = nextId++;
        try (PreparedStatement insert = connection.prepareStatement(
            "insert into doom_asset(asset_id,asset_kind,asset_name,raw_sha256) "
                + "values(?,'sound',?,?)")) {
          insert.setInt(1, assetId);
          insert.setString(2, sound.getKey());
          insert.setString(3, sha);
          insert.executeUpdate();
        }
      } else if (!sha.equals(currentSha)) {
        throw new IllegalStateException(
            "sound asset provenance conflict " + sound.getKey());
      }
      try (PreparedStatement merge = connection.prepareStatement(
          "merge into doom_asset_source d using(select 'sound' asset_kind,"
              + "? asset_name,0 source_ordinal,? lump_name,? source_sha256 "
              + "from dual) s on(d.asset_kind=s.asset_kind and "
              + "d.asset_name=s.asset_name and d.source_ordinal=s.source_ordinal) "
              + "when matched then update set d.lump_name=s.lump_name,"
              + "d.source_sha256=s.source_sha256 when not matched then insert "
              + "(asset_kind,asset_name,source_ordinal,lump_name,source_sha256) "
              + "values(s.asset_kind,s.asset_name,s.source_ordinal,s.lump_name,"
              + "s.source_sha256)")) {
        merge.setString(1, sound.getKey());
        merge.setString(2, sound.getKey());
        merge.setString(3, sha);
        merge.executeUpdate();
      }
      int updated;
      try (PreparedStatement update = connection.prepareStatement(
          "update doom_asset_blob set media_type='audio/x-doom',"
              + "encoded_bytes=? where asset_id=?");
           InputStream input = new java.io.ByteArrayInputStream(sound.getValue())) {
        update.setBinaryStream(1, input, sound.getValue().length);
        update.setInt(2, assetId);
        updated = update.executeUpdate();
      }
      if (updated == 0) {
        try (PreparedStatement insert = connection.prepareStatement(
            "insert into doom_asset_blob(asset_id,media_type,encoded_bytes) "
                + "values(?,'audio/x-doom',?)");
             InputStream input = new java.io.ByteArrayInputStream(sound.getValue())) {
          insert.setInt(1, assetId);
          insert.setBinaryStream(2, input, sound.getValue().length);
          insert.executeUpdate();
        }
      }
    }
    return sounds.size();
  }

  private static int littleInt(byte[] bytes, int offset) {
    return (bytes[offset] & 0xff) | ((bytes[offset + 1] & 0xff) << 8)
        | ((bytes[offset + 2] & 0xff) << 16) | (bytes[offset + 3] << 24);
  }

  private static String ascii(byte[] bytes, int offset, int length) {
    StringBuilder value = new StringBuilder(length);
    for (int index = 0; index < length; index++) {
      value.append((char) (bytes[offset + index] & 0xff));
    }
    return value.toString();
  }

  private static String sha256(Path path) throws Exception {
    MessageDigest digest = MessageDigest.getInstance("SHA-256");
    try (InputStream input = new BufferedInputStream(
        Files.newInputStream(path))) {
      byte[] buffer = new byte[64 * 1024];
      for (int read; (read = input.read(buffer)) >= 0;) {
        if (read > 0) digest.update(buffer, 0, read);
      }
    }
    StringBuilder result = new StringBuilder(64);
    for (byte value : digest.digest()) {
      result.append(String.format("%02x", value & 0xff));
    }
    return result.toString();
  }

  private static String sha256(byte[] bytes) throws Exception {
    MessageDigest digest = MessageDigest.getInstance("SHA-256");
    digest.update(bytes);
    StringBuilder result = new StringBuilder(64);
    for (byte value : digest.digest()) {
      result.append(String.format("%02x", value & 0xff));
    }
    return result.toString();
  }
}
