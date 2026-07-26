import java.io.BufferedInputStream;
import java.io.BufferedReader;
import java.io.InputStream;
import java.io.InputStreamReader;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.security.MessageDigest;
import java.sql.Connection;
import java.sql.DriverManager;
import java.sql.PreparedStatement;
import java.sql.ResultSet;
import java.util.ArrayList;
import java.util.List;

/**
 * Deployment-side loader for the database-resident ORDS client.
 *
 * <p>This class is build tooling, never OJVM code. It streams each pinned file
 * through JDBC and then hashes the Oracle-resident BLOB with DBMS_CRYPTO before
 * committing the replacement inventory atomically.</p>
 */
public final class DoomHostedStaticLoader {
  private static final class Asset {
    final String key;
    final String sha256;
    final long bytes;
    final String contentType;
    final String cacheControl;

    Asset(String key, String sha256, long bytes, String contentType,
        String cacheControl) {
      this.key = key;
      this.sha256 = sha256;
      this.bytes = bytes;
      this.contentType = contentType;
      this.cacheControl = cacheControl;
    }
  }

  private DoomHostedStaticLoader() {}

  public static void main(String[] args) throws Exception {
    if (args.length != 4) {
      throw new IllegalArgumentException(
          "usage: jdbc-url user build-directory loader-manifest.tsv");
    }
    String password = System.getenv("DOOMDB_PASSWORD");
    if (password == null || password.isEmpty()) {
      password = new BufferedReader(new InputStreamReader(System.in)).readLine();
    }
    if (password == null || password.isEmpty()) {
      throw new IllegalStateException("database password is required");
    }
    Path build = Path.of(args[2]).toRealPath();
    Path manifest = Path.of(args[3]).toRealPath();
    List<Asset> assets = readManifest(manifest);
    long totalBytes = 0;
    for (Asset asset : assets) {
      Path file = resolve(build, asset.key);
      long bytes = Files.size(file);
      String digest = sha256(file);
      if (bytes != asset.bytes || !digest.equals(asset.sha256)) {
        throw new IllegalStateException(
            "build-side static integrity mismatch: " + asset.key);
      }
      totalBytes += bytes;
    }

    try (Connection connection =
             DriverManager.getConnection(args[0], args[1], password)) {
      connection.setAutoCommit(false);
      try {
        try (PreparedStatement delete =
                 connection.prepareStatement("delete from doom_hosted_asset")) {
          delete.executeUpdate();
        }
        try (PreparedStatement insert = connection.prepareStatement(
            "insert into doom_hosted_asset(asset_path,content_type,"
                + "cache_control,content_sha256,content_length,payload) "
                + "values(?,?,?,?,?,?)")) {
          for (Asset asset : assets) {
            Path file = resolve(build, asset.key);
            insert.setString(1, asset.key);
            insert.setString(2, asset.contentType);
            insert.setString(3, asset.cacheControl);
            insert.setString(4, asset.sha256);
            insert.setLong(5, asset.bytes);
            try (InputStream input =
                     new BufferedInputStream(Files.newInputStream(file))) {
              insert.setBinaryStream(6, input, asset.bytes);
              if (insert.executeUpdate() != 1) {
                throw new IllegalStateException(
                    "static insert count: " + asset.key);
              }
            }
          }
        }
        verifyDatabaseInventory(connection, assets);
        connection.commit();
      } catch (Exception failure) {
        connection.rollback();
        throw failure;
      }
    }
    System.out.println("PASS T11.2-HOSTED-STATIC-LOAD assets=" + assets.size()
        + " bytes=" + totalBytes + " manifest_sha256=" + sha256(manifest));
  }

  private static List<Asset> readManifest(Path path) throws Exception {
    List<String> lines = Files.readAllLines(path, StandardCharsets.UTF_8);
    if (lines.isEmpty()
        || !lines.get(0).equals(
            "asset_path\tsha256\tbytes\tcontent_type\tcache_control")) {
      throw new IllegalStateException("static loader manifest header");
    }
    List<Asset> assets = new ArrayList<>();
    for (int index = 1; index < lines.size(); index++) {
      if (lines.get(index).isEmpty()) continue;
      String[] fields = lines.get(index).split("\\t", -1);
      if (fields.length != 5
          || !fields[0].matches("[A-Za-z0-9][A-Za-z0-9._-]{0,254}")
          || !fields[1].matches("[0-9a-f]{64}")
          || !fields[2].matches("[1-9][0-9]*")
          || fields[3].isEmpty() || fields[4].isEmpty()) {
        throw new IllegalStateException(
            "static loader manifest row " + (index + 1));
      }
      assets.add(new Asset(fields[0], fields[1],
          Long.parseLong(fields[2]), fields[3], fields[4]));
    }
    if (assets.isEmpty()
        || assets.stream().noneMatch(asset -> asset.key.equals("index.html"))
        || assets.stream().map(asset -> asset.key).distinct().count()
            != assets.size()) {
      throw new IllegalStateException("static loader manifest inventory");
    }
    return assets;
  }

  private static Path resolve(Path build, String key) throws Exception {
    Path file = build.resolve(key).toRealPath();
    if (!file.getParent().equals(build) || !Files.isRegularFile(file)
        || Files.isSymbolicLink(file)) {
      throw new IllegalStateException("unsafe static path: " + key);
    }
    return file;
  }

  private static void verifyDatabaseInventory(
      Connection connection, List<Asset> assets) throws Exception {
    try (PreparedStatement count = connection.prepareStatement(
             "select count(*) from doom_hosted_asset");
         ResultSet rows = count.executeQuery()) {
      if (!rows.next() || rows.getInt(1) != assets.size()) {
        throw new IllegalStateException("Oracle static inventory count");
      }
    }
    try (PreparedStatement verify = connection.prepareStatement(
        "select content_type,cache_control,content_sha256,content_length,"
            + "dbms_lob.getlength(payload),"
            + "lower(rawtohex(dbms_crypto.hash(payload,4))) "
            + "from doom_hosted_asset where asset_path=?")) {
      for (Asset asset : assets) {
        verify.setString(1, asset.key);
        try (ResultSet rows = verify.executeQuery()) {
          if (!rows.next()
              || !asset.contentType.equals(rows.getString(1))
              || !asset.cacheControl.equals(rows.getString(2))
              || !asset.sha256.equals(rows.getString(3))
              || asset.bytes != rows.getLong(4)
              || asset.bytes != rows.getLong(5)
              || !asset.sha256.equals(rows.getString(6))
              || rows.next()) {
            throw new IllegalStateException(
                "Oracle-resident static staging mismatch: " + asset.key);
          }
        }
      }
    }
  }

  private static String sha256(Path path) throws Exception {
    MessageDigest digest = MessageDigest.getInstance("SHA-256");
    try (InputStream input = new BufferedInputStream(Files.newInputStream(path))) {
      byte[] buffer = new byte[1024 * 1024];
      for (int read; (read = input.read(buffer)) != -1;) {
        digest.update(buffer, 0, read);
      }
    }
    StringBuilder result = new StringBuilder(64);
    for (byte value : digest.digest()) {
      result.append(String.format("%02x", value & 0xff));
    }
    return result.toString();
  }
}
