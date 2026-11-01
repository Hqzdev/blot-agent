package dev.blot.infrastructure.workspace.database;

import dev.blot.application.ports.*;
import dev.blot.application.ports.JsonCodec;
import dev.blot.application.ports.WorkspaceStore;
import dev.blot.application.workspace.WorkspaceFailure;
import java.nio.file.Path;
import java.sql.*;
import java.time.Clock;
import java.util.function.Function;

public final class SqliteWorkspaceStore implements WorkspaceStore {
  private final String url;
  private final JsonCodec codec;
  private final Clock clock;

  public SqliteWorkspaceStore(Path database, JsonCodec codec, Clock clock) {
    this.url = "jdbc:sqlite:" + database.toAbsolutePath();
    this.codec = codec;
    this.clock = clock;
    try (var c = connect()) {
      WorkspaceMigrations.apply(c, database.toAbsolutePath());
    } catch (SQLException e) {
      throw unavailable(e);
    }
  }

  private Connection connect() throws SQLException {
    var c = DriverManager.getConnection(url);
    try (var s = c.createStatement()) {
      s.execute("PRAGMA foreign_keys=ON");
      s.execute("PRAGMA busy_timeout=5000");
      s.execute("PRAGMA journal_mode=WAL");
    }
    return c;
  }

  public <T> T transact(Function<Transaction, T> operation) {
    try (var c = connect();
        var s = c.createStatement()) {
      s.execute("BEGIN IMMEDIATE");
      try {
        T value = operation.apply(new WorkspaceTransaction(c, codec, clock));
        s.execute("COMMIT");
        return value;
      } catch (RuntimeException | Error e) {
        s.execute("ROLLBACK");
        throw e;
      }
    } catch (SQLException e) {
      throw unavailable(e);
    }
  }

  static WorkspaceFailure unavailable(SQLException e) {
    return new WorkspaceFailure(
        e.getErrorCode() == 19 ? 409 : 503,
        e.getErrorCode() == 19 ? "conflict" : "storage_unavailable",
        "Хранилище недоступно или запись конфликтует");
  }
}
