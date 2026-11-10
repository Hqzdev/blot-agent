package dev.blot.infrastructure.workspace.database;

import dev.blot.application.ports.JsonCodec;
import dev.blot.application.ports.V3Store;
import dev.blot.application.workspace.WorkspaceFailure;
import java.nio.charset.StandardCharsets;
import java.nio.file.*;
import java.sql.*;
import java.util.*;
import java.util.function.Function;

/** Append-only revisions keep paginated snapshots consistent with their event watermark. */
public final class SqliteV3Store implements V3Store {
  private final String url;
  private final JsonCodec json;

  public SqliteV3Store(Path database, JsonCodec json) {
    this.json = json;
    this.url = "jdbc:sqlite:" + database.toAbsolutePath();
    try {
      Files.createDirectories(database.toAbsolutePath().getParent());
      try (var c = connect();
          var s = c.createStatement()) {
        s.execute(
            "CREATE TABLE IF NOT EXISTS v3_receipts (owner TEXT NOT NULL, command_id TEXT NOT NULL, digest TEXT NOT NULL, receipt TEXT NOT NULL, PRIMARY KEY(owner,command_id))");
        s.execute(
            "CREATE TABLE IF NOT EXISTS v3_revisions (seq INTEGER PRIMARY KEY AUTOINCREMENT, owner TEXT NOT NULL, kind TEXT NOT NULL, id TEXT NOT NULL, version INTEGER NOT NULL, value TEXT NOT NULL, deleted INTEGER NOT NULL, event_id TEXT NOT NULL)");
        s.execute(
            "CREATE INDEX IF NOT EXISTS v3_record_history ON v3_revisions(owner,kind,id,seq)");
      }
    } catch (java.io.IOException | SQLException e) {
      throw unavailable();
    }
  }

  private Connection connect() throws SQLException {
    var c = DriverManager.getConnection(url);
    try (var s = c.createStatement()) {
      s.execute("PRAGMA busy_timeout=5000");
      s.execute("PRAGMA journal_mode=WAL");
    }
    return c;
  }

  public Set<UUID> owners() {
    try (var c = connect();
        var s = c.createStatement();
        var rows = s.executeQuery("SELECT DISTINCT owner FROM v3_revisions")) {
      var result = new HashSet<UUID>();
      while (rows.next()) result.add(UUID.fromString(rows.getString(1)));
      return result;
    } catch (SQLException e) {
      throw unavailable();
    }
  }

  public <T> T transact(UUID owner, Function<Transaction, T> operation) {
    try (var c = connect();
        var s = c.createStatement()) {
      s.execute("BEGIN IMMEDIATE");
      try {
        T result = operation.apply(new Tx(c, owner));
        s.execute("COMMIT");
        return result;
      } catch (RuntimeException | Error failure) {
        s.execute("ROLLBACK");
        throw failure;
      }
    } catch (SQLException e) {
      throw unavailable();
    }
  }

  private static WorkspaceFailure unavailable() {
    return new WorkspaceFailure(503, "storage_unavailable", "Хранилище v3 недоступно");
  }

  private final class Tx implements Transaction {
    private final Connection connection;
    private final UUID owner;

    Tx(Connection connection, UUID owner) {
      this.connection = connection;
      this.owner = owner;
    }

    private PreparedStatement query(String sql, Object... args) throws SQLException {
      var statement = connection.prepareStatement(sql);
      for (int i = 0; i < args.length; i++)
        statement.setObject(i + 1, args[i] instanceof UUID ? args[i].toString() : args[i]);
      return statement;
    }

    public Optional<Accepted> receipt(UUID id) {
      try (var s =
              query(
                  "SELECT digest,receipt FROM v3_receipts WHERE owner=? AND command_id=?",
                  owner,
                  id);
          var rows = s.executeQuery()) {
        return rows.next()
            ? Optional.of(
                new Accepted(rows.getString(1), json.read(rows.getString(2), Receipt.class)))
            : Optional.empty();
      } catch (SQLException e) {
        throw unavailable();
      }
    }

    public void accept(UUID id, String digest, Receipt receipt) {
      try (var s =
          query(
              "INSERT INTO v3_receipts VALUES(?,?,?,?)", owner, id, digest, json.write(receipt))) {
        s.executeUpdate();
      } catch (SQLException e) {
        throw unavailable();
      }
    }

    @SuppressWarnings("unchecked")
    private Record record(ResultSet row) throws SQLException {
      return new Record(
          row.getString("kind"),
          UUID.fromString(row.getString("id")),
          row.getLong("version"),
          json.read(row.getString("value"), Map.class),
          row.getBoolean("deleted"));
    }

    public Optional<Record> find(String kind, UUID id) {
      try (var s =
              query(
                  "SELECT * FROM v3_revisions WHERE owner=? AND kind=? AND id=? ORDER BY seq DESC LIMIT 1",
                  owner,
                  kind,
                  id);
          var rows = s.executeQuery()) {
        return rows.next() ? Optional.of(record(rows)) : Optional.empty();
      } catch (SQLException e) {
        throw unavailable();
      }
    }

    public List<Record> records(String kind) {
      try (var s =
              query(
                  "SELECT * FROM v3_revisions r WHERE owner=? AND kind=? AND deleted=0 AND NOT EXISTS (SELECT 1 FROM v3_revisions n WHERE n.owner=r.owner AND n.kind=r.kind AND n.id=r.id AND n.seq>r.seq) ORDER BY seq",
                  owner,
                  kind);
          var rows = s.executeQuery()) {
        var result = new ArrayList<Record>();
        while (rows.next()) result.add(record(rows));
        return result;
      } catch (SQLException e) {
        throw unavailable();
      }
    }

    public void put(Record value) {
      var old = find(value.kind(), value.id());
      if (value.version() != old.map(r -> r.version() + 1).orElse(1L))
        throw WorkspaceFailure.conflict("Версия записи изменилась");
      try (var s =
          query(
              "INSERT INTO v3_revisions(owner,kind,id,version,value,deleted,event_id) VALUES(?,?,?,?,?,?,?)",
              owner,
              value.kind(),
              value.id(),
              value.version(),
              json.write(value.value()),
              value.deleted(),
              UUID.randomUUID())) {
        s.executeUpdate();
      } catch (SQLException e) {
        throw unavailable();
      }
    }

    public long sequence() {
      try (var s = query("SELECT COALESCE(MAX(seq),0) FROM v3_revisions WHERE owner=?", owner);
          var rows = s.executeQuery()) {
        return rows.next() ? rows.getLong(1) : 0;
      } catch (SQLException e) {
        throw unavailable();
      }
    }

    public Page snapshot(String cursor, int limit) {
      long watermark = sequence();
      long offset = 0;
      if (cursor != null) {
        try {
          String[] parts =
              new String(Base64.getUrlDecoder().decode(cursor), StandardCharsets.UTF_8).split(":");
          if (parts.length != 3 || !parts[0].equals(owner.toString()))
            throw new IllegalArgumentException();
          long requested = Long.parseLong(parts[1]);
          offset = Long.parseLong(parts[2]);
          if (requested < 0 || requested > watermark || offset < 0 || offset > 10_000_000)
            throw new IllegalArgumentException();
          watermark = requested;
        } catch (IllegalArgumentException e) {
          throw WorkspaceFailure.invalid("Неверный курсор v3");
        }
      }
      try (var s =
              query(
                  "SELECT * FROM v3_revisions r WHERE owner=? AND seq<=? AND deleted=0 AND NOT EXISTS (SELECT 1 FROM v3_revisions n WHERE n.owner=r.owner AND n.kind=r.kind AND n.id=r.id AND n.seq>r.seq AND n.seq<=?) ORDER BY kind,id LIMIT ? OFFSET ?",
                  owner,
                  watermark,
                  watermark,
                  limit + 1,
                  offset);
          var rows = s.executeQuery()) {
        var result = new ArrayList<Record>();
        while (rows.next()) result.add(record(rows));
        String next =
            result.size() > limit
                ? Base64.getUrlEncoder()
                    .withoutPadding()
                    .encodeToString(
                        (owner + ":" + watermark + ":" + (offset + limit))
                            .getBytes(StandardCharsets.UTF_8))
                : null;
        return new Page(
            watermark, List.copyOf(result.subList(0, Math.min(limit, result.size()))), next);
      } catch (SQLException e) {
        throw unavailable();
      }
    }

    public List<Event> events(long after, int limit) {
      try (var s =
              query(
                  "SELECT * FROM v3_revisions WHERE owner=? AND seq>? ORDER BY seq LIMIT ?",
                  owner,
                  after,
                  limit);
          var rows = s.executeQuery()) {
        var result = new ArrayList<Event>();
        while (rows.next())
          result.add(
              new Event(
                  3,
                  UUID.fromString(rows.getString("event_id")),
                  rows.getLong("seq"),
                  rows.getString("kind"),
                  UUID.fromString(rows.getString("id")),
                  rows.getLong("version"),
                  rows.getBoolean("deleted")));
        return result;
      } catch (SQLException e) {
        throw unavailable();
      }
    }
  }
}
