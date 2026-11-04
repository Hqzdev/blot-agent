package dev.blot.cloud.storage;

import dev.blot.cloud.CloudFailure;
import java.io.IOException;
import java.nio.file.*;
import java.sql.*;
import java.util.function.Function;

public final class CloudDatabase {
  private final String url;

  public CloudDatabase(Path path) {
    try {
      Files.createDirectories(path.toAbsolutePath().getParent());
    } catch (IOException failure) {
      throw new CloudFailure(503, "storage_unavailable");
    }
    url = "jdbc:sqlite:" + path.toAbsolutePath();
    transact(
        tx -> {
          CloudSchema.migrate(tx);
          return null;
        });
  }

  public <T> T transact(Function<CloudTransaction, T> operation) {
    try (var connection = DriverManager.getConnection(url);
        var statement = connection.createStatement()) {
      statement.execute("PRAGMA foreign_keys = ON");
      statement.execute("PRAGMA busy_timeout = 5000");
      statement.execute("PRAGMA journal_mode = WAL");
      statement.execute("PRAGMA synchronous = FULL");
      statement.execute("BEGIN IMMEDIATE");
      try {
        T result = operation.apply(new CloudTransaction(connection));
        statement.execute("COMMIT");
        return result;
      } catch (RuntimeException | Error failure) {
        statement.execute("ROLLBACK");
        throw failure;
      }
    } catch (SQLException failure) {
      throw failure(failure);
    }
  }

  static CloudFailure failure(SQLException failure) {
    return new CloudFailure(
        failure.getErrorCode() == 19 ? 409 : 503,
        failure.getErrorCode() == 19 ? "storage_conflict" : "storage_unavailable");
  }
}
