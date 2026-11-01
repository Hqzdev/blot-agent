package dev.blot.infrastructure.database;

import dev.blot.application.*;
import dev.blot.application.BlotUnitOfWork;
import java.nio.file.Path;
import java.sql.*;
import java.util.function.Function;

/** Opens a connection per operation; BEGIN IMMEDIATE serializes writes across instances. */
public final class SqliteUnitOfWork implements BlotUnitOfWork {
  private final String url;

  public SqliteUnitOfWork(Path database) {
    url = "jdbc:sqlite:" + database.toAbsolutePath().normalize();
    try (Connection connection = connect();
        Statement statement = connection.createStatement()) {
      statement.execute("BEGIN IMMEDIATE");
      try {
        int version;
        try (ResultSet result = statement.executeQuery("PRAGMA user_version")) {
          version = result.getInt(1);
        }
        if (version > 1) throw new SQLException("Unsupported database schema " + version);
        statement.execute(
            "CREATE TABLE IF NOT EXISTS projects (id TEXT PRIMARY KEY, data TEXT NOT NULL)");
        statement.execute(
            "CREATE TABLE IF NOT EXISTS runs (id TEXT PRIMARY KEY, project_id TEXT NOT NULL REFERENCES projects(id), data TEXT NOT NULL, UNIQUE(id, project_id))");
        statement.execute(
            "CREATE TABLE IF NOT EXISTS specifications (id TEXT PRIMARY KEY, run_id TEXT NOT NULL REFERENCES runs(id), revision INTEGER NOT NULL CHECK(revision > 0), data TEXT NOT NULL, UNIQUE(run_id, revision))");
        statement.execute(
            "CREATE TABLE IF NOT EXISTS tasks (id TEXT PRIMARY KEY, project_id TEXT NOT NULL, run_id TEXT NOT NULL, data TEXT NOT NULL, FOREIGN KEY(run_id, project_id) REFERENCES runs(id, project_id))");
        statement.execute(
            "CREATE TABLE IF NOT EXISTS task_dependencies (task_id TEXT NOT NULL REFERENCES tasks(id), dependency_id TEXT NOT NULL REFERENCES tasks(id), PRIMARY KEY(task_id, dependency_id), CHECK(task_id <> dependency_id))");
        statement.execute(
            "CREATE TABLE IF NOT EXISTS outbox (seq INTEGER PRIMARY KEY AUTOINCREMENT, event_id TEXT NOT NULL UNIQUE, project_id TEXT NOT NULL REFERENCES projects(id), run_id TEXT REFERENCES runs(id), data TEXT NOT NULL)");
        statement.execute("PRAGMA user_version=1");
        statement.execute("COMMIT");
      } catch (RuntimeException | SQLException e) {
        statement.execute("ROLLBACK");
        throw e;
      }
    } catch (SQLException e) {
      throw failure(e);
    }
  }

  private Connection connect() throws SQLException {
    Connection connection = DriverManager.getConnection(url);
    try (Statement statement = connection.createStatement()) {
      statement.execute("PRAGMA foreign_keys=ON");
      statement.execute("PRAGMA busy_timeout=5000");
    } catch (SQLException e) {
      connection.close();
      throw e;
    }
    return connection;
  }

  @Override
  public <T> T transact(Function<Transaction, T> operation) {
    try (Connection connection = connect();
        Statement statement = connection.createStatement()) {
      statement.execute("BEGIN IMMEDIATE");
      try {
        T value = operation.apply(new SqliteTransaction(connection));
        statement.execute("COMMIT");
        return value;
      } catch (RuntimeException | Error | SQLException e) {
        try {
          statement.execute("ROLLBACK");
        } catch (SQLException rollback) {
          e.addSuppressed(rollback);
        }
        throw e;
      }
    } catch (SQLException e) {
      throw failure(e);
    }
  }

  static StorageException failure(SQLException e) {
    return new StorageException(
        e.getErrorCode() == 19
            ? StorageException.Kind.CONSTRAINT
            : StorageException.Kind.CONNECTION,
        e);
  }
}
