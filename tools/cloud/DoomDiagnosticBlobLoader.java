import java.io.BufferedReader;
import java.io.Console;
import java.io.InputStreamReader;
import java.io.InputStream;
import java.nio.file.Files;
import java.nio.file.Path;
import java.security.MessageDigest;
import java.sql.Connection;
import java.sql.DriverManager;
import java.sql.PreparedStatement;
import java.sql.ResultSet;
import java.util.Properties;

/** Hash-bound JDBC BLOB loader for isolated MLE diagnostic source tables. */
public final class DoomDiagnosticBlobLoader {
  private DoomDiagnosticBlobLoader() {}

  public static void main(String[] args) throws Exception {
    if (args.length != 7) {
      throw new IllegalArgumentException(
          "usage: URL USER ENGINE_PATH ENGINE_SHA BRIDGE_PATH BRIDGE_SHA TABLE");
    }
    String password;
    Console console = System.console();
    if (console != null) {
      char[] value = console.readPassword();
      password = new String(value);
      java.util.Arrays.fill(value, '\0');
    } else {
      password = new BufferedReader(new InputStreamReader(System.in)).readLine();
    }
    if (password == null || password.isEmpty()) {
      throw new IllegalArgumentException("database password is absent");
    }
    String table = args[6];
    if (!table.matches("[A-Z][A-Z0-9_$#]{0,127}")) {
      throw new IllegalArgumentException("table is not a simple identifier");
    }
    Properties properties = new Properties();
    properties.setProperty("user", args[1]);
    properties.setProperty("password", password);
    try (Connection connection = DriverManager.getConnection(args[0], properties)) {
      connection.setAutoCommit(false);
      load(connection, table, "ENGINE", Path.of(args[2]), args[3]);
      load(connection, table, "BRIDGE", Path.of(args[4]), args[5]);
      connection.commit();
    } finally {
      password = "";
    }
  }

  private static void load(
      Connection connection, String table, String kind, Path path,
      String expectedSha) throws Exception {
    long bytes = Files.size(path);
    String actualSha;
    try (InputStream input = Files.newInputStream(path)) {
      MessageDigest digest = MessageDigest.getInstance("SHA-256");
      byte[] buffer = new byte[1 << 20];
      int count;
      while ((count = input.read(buffer)) >= 0) {
        if (count > 0) digest.update(buffer, 0, count);
      }
      actualSha = hex(digest.digest());
    }
    if (!actualSha.equals(expectedSha)) {
      throw new IllegalStateException(kind + " build-side SHA mismatch");
    }
    String update = "update " + table
        + " set source_blob=? where source_kind=?"
        + " and expected_bytes=? and expected_sha256=?";
    int updated;
    try (PreparedStatement statement = connection.prepareStatement(update);
        InputStream input = Files.newInputStream(path)) {
      statement.setBinaryStream(1, input, bytes);
      statement.setString(2, kind);
      statement.setLong(3, bytes);
      statement.setString(4, expectedSha);
      updated = statement.executeUpdate();
    }
    if (updated != 1) {
      throw new IllegalStateException(kind + " staging row mismatch");
    }
    String verify = "select dbms_lob.getlength(source_blob),"
        // DBMS_CRYPTO constants are PL/SQL-only in SQL expression context.
        // HASH_SH256 is the documented numeric algorithm id 4.
        + "lower(rawtohex(dbms_crypto.hash(source_blob,4)))"
        + " from " + table + " where source_kind=?";
    try (PreparedStatement statement = connection.prepareStatement(verify)) {
      statement.setString(1, kind);
      try (ResultSet result = statement.executeQuery()) {
        if (!result.next() || result.getLong(1) != bytes
            || !expectedSha.equals(result.getString(2))) {
          throw new IllegalStateException(kind + " database SHA fence failed");
        }
      }
    }
    System.out.println(
        "PMLE_DIAGNOSTIC_BLOB_LOAD|PASS|kind=" + kind
        + "|bytes=" + bytes + "|sha256=" + expectedSha);
  }

  private static String hex(byte[] bytes) {
    char[] digits = "0123456789abcdef".toCharArray();
    char[] output = new char[bytes.length * 2];
    for (int index = 0; index < bytes.length; index++) {
      int value = bytes[index] & 0xff;
      output[index * 2] = digits[value >>> 4];
      output[index * 2 + 1] = digits[value & 0xf];
    }
    return new String(output);
  }
}
