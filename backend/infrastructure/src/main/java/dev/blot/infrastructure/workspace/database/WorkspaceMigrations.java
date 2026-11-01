package dev.blot.infrastructure.workspace.database;

import dev.blot.core.workspace.EntityKind;
import java.nio.file.*;
import java.sql.*;

/** Новая схема не меняет пользовательские записи начального API. */
final class WorkspaceMigrations {
  static void apply(Connection connection, Path database) throws SQLException {
    try (var s = connection.createStatement()) {
      s.execute("CREATE TABLE IF NOT EXISTS workspace_schema(version INTEGER NOT NULL)");
      int version = 0;
      try (var r = s.executeQuery("SELECT version FROM workspace_schema")) {
        if (r.next()) version = r.getInt(1);
      }
      if (version > 8) throw new SQLException("База создана более новой версией Blot");
      if (version == 8) return;
      // VACUUM INTO создаёт согласованную копию, включая зафиксированный WAL.
      if (Files.exists(database)) backup(connection, database);
      s.execute("BEGIN IMMEDIATE");
      try {
        for (var kind : EntityKind.values()) {
          String table = table(kind);
          s.execute(
              "CREATE TABLE IF NOT EXISTS "
                  + table
                  + "(id TEXT PRIMARY KEY,owner_id TEXT NOT NULL,project_id TEXT,parent_id TEXT,version INTEGER NOT NULL,created_at TEXT NOT NULL,updated_at TEXT NOT NULL,data TEXT NOT NULL,UNIQUE(owner_id,id),FOREIGN KEY(owner_id) REFERENCES v2_account(id),FOREIGN KEY(owner_id,project_id) REFERENCES v2_project(owner_id,id))");
          s.execute(
              "CREATE INDEX IF NOT EXISTS "
                  + table
                  + "_scope ON "
                  + table
                  + "(owner_id,project_id,parent_id,created_at,id)");
        }
        s.execute(
            "CREATE TABLE IF NOT EXISTS v2_commands(owner_id TEXT NOT NULL,command_id TEXT NOT NULL,hash TEXT NOT NULL,data TEXT NOT NULL,PRIMARY KEY(owner_id,command_id))");
        s.execute(
            "CREATE TABLE IF NOT EXISTS v2_events(seq INTEGER PRIMARY KEY AUTOINCREMENT,event_id TEXT NOT NULL UNIQUE,owner_id TEXT NOT NULL,project_id TEXT,type TEXT NOT NULL,occurred_at TEXT NOT NULL,data TEXT NOT NULL)");
        s.execute("CREATE INDEX IF NOT EXISTS v2_events_owner ON v2_events(owner_id,seq)");
        s.execute(
            "CREATE VIRTUAL TABLE IF NOT EXISTS v2_memory_search USING fts5(id UNINDEXED,owner_id UNINDEXED,content)");
        s.execute(
            "CREATE UNIQUE INDEX IF NOT EXISTS v2_accounts_email ON v2_account(json_extract(data,'$.email'))");
        s.execute(
            "CREATE INDEX IF NOT EXISTS v2_message_ordinal ON v2_message(owner_id,parent_id,json_extract(data,'$.ordinal'))");
        s.execute(
            "CREATE INDEX IF NOT EXISTS v2_session_token ON v2_auth_session(json_extract(data,'$.tokenHash'))");
        s.execute("DELETE FROM v2_memory_search");
        s.execute(
            "INSERT INTO v2_memory_search(id,owner_id,content) SELECT id,owner_id,json_extract(data,'$.content') FROM v2_memory");
        s.execute(
            "CREATE TABLE IF NOT EXISTS v2_legacy_claims(source_id TEXT PRIMARY KEY,owner_id TEXT NOT NULL,project_id TEXT NOT NULL)");
        s.execute("DELETE FROM workspace_schema");
        s.execute("INSERT INTO workspace_schema VALUES(8)");
        s.execute("COMMIT");
      } catch (SQLException | RuntimeException e) {
        s.execute("ROLLBACK");
        throw e;
      }
    }
  }

  private static void backup(Connection connection, Path database) throws SQLException {
    String suffix = java.util.UUID.randomUUID().toString();
    Path ready = database.resolveSibling(database.getFileName() + ".before-v8-" + suffix);
    Path temporary = ready.resolveSibling(ready.getFileName() + ".tmp");
    try {
      try (var statement = connection.prepareStatement("VACUUM INTO ?")) {
        statement.setString(1, temporary.toString());
        statement.execute();
      }
      try (var file = java.nio.channels.FileChannel.open(temporary, StandardOpenOption.WRITE)) {
        file.force(true);
      }
      Files.move(temporary, ready, StandardCopyOption.ATOMIC_MOVE);
    } catch (java.io.IOException failure) {
      throw new SQLException("Не удалось завершить резервную копию", failure);
    } finally {
      try {
        Files.deleteIfExists(temporary);
      } catch (java.io.IOException ignored) {
        /* Незавершённая копия не считается готовой. */
      }
    }
  }

  static String table(EntityKind kind) {
    return "v2_" + kind.name().toLowerCase(java.util.Locale.ROOT);
  }
}
