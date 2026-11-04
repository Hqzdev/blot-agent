package dev.blot.infrastructure.workspace.database;

import dev.blot.application.ports.*;
import dev.blot.application.ports.JsonCodec;
import dev.blot.application.ports.WorkspaceStore;
import dev.blot.application.ports.WorkspaceStore.*;
import dev.blot.application.workspace.WorkspaceFailure;
import dev.blot.core.workspace.*;
import dev.blot.core.workspace.Entity;
import dev.blot.core.workspace.EntityKind;
import dev.blot.core.workspace.conversation.MemoryData;
import dev.blot.core.workspace.conversation.MessageData;
import dev.blot.core.workspace.conversation.SummaryData;
import dev.blot.core.workspace.identity.AuthSessionData;
import java.sql.*;
import java.time.*;
import java.util.*;

final class WorkspaceTransaction implements WorkspaceStore.Transaction {
  private final Connection db;
  private final JsonCodec codec;
  private final Clock clock;

  WorkspaceTransaction(Connection db, JsonCodec codec, Clock clock) {
    this.db = db;
    this.codec = codec;
    this.clock = clock;
  }

  public <T> Optional<Entity<T>> find(EntityKind kind, UUID owner, UUID id, Class<T> type) {
    return rows(kind, "owner_id=? AND id=?", Arrays.asList(owner, id), type, 1).stream()
        .findFirst();
  }

  public <T> List<Entity<T>> list(
      EntityKind kind, UUID owner, UUID project, UUID parent, Class<T> type, int limit) {
    return page(kind, owner, project, parent, type, limit, 0);
  }

  public <T> List<Entity<T>> page(
      EntityKind kind,
      UUID owner,
      UUID project,
      UUID parent,
      Class<T> type,
      int limit,
      int offset) {
    if (offset < 0) throw WorkspaceFailure.invalid("Неверная страница");
    String where = "owner_id=?";
    var args = new ArrayList<Object>();
    args.add(owner);
    if (project != null) {
      where += " AND project_id=?";
      args.add(project);
    }
    if (parent != null) {
      where += " AND parent_id=?";
      args.add(parent);
    }
    return rows(kind, where, args, type, limit, offset, "created_at,id");
  }

  public <T> List<Entity<T>> after(
      EntityKind kind,
      UUID owner,
      UUID project,
      UUID parent,
      Class<T> type,
      int limit,
      Instant createdAt,
      UUID id) {
    String where = "owner_id=? AND (created_at>? OR (created_at=? AND id>?))";
    var args = new ArrayList<Object>(List.of(owner, createdAt, createdAt, id));
    if (project != null) {
      where += " AND project_id=?";
      args.add(project);
    }
    if (parent != null) {
      where += " AND parent_id=?";
      args.add(parent);
    }
    return rows(kind, where, args, type, limit, 0, "created_at,id");
  }

  public <T> List<Entity<T>> scan(EntityKind kind, Class<T> type, int limit) {
    return rows(kind, "1=1", List.of(), type, limit);
  }

  private <T> List<Entity<T>> rows(
      EntityKind kind, String where, List<?> args, Class<T> type, int limit) {
    return rows(kind, where, args, type, limit, 0, "created_at,id");
  }

  private <T> List<Entity<T>> rows(
      EntityKind kind,
      String where,
      List<?> args,
      Class<T> type,
      int limit,
      int offset,
      String order) {
    try (var p =
        db.prepareStatement(
            "SELECT * FROM "
                + WorkspaceMigrations.table(kind)
                + " WHERE "
                + where
                + " ORDER BY "
                + order
                + " LIMIT ? OFFSET ?")) {
      bind(p, args);
      p.setInt(args.size() + 1, Math.max(1, Math.min(limit, 10000)));
      p.setInt(args.size() + 2, offset);
      var result = new ArrayList<Entity<T>>();
      try (var r = p.executeQuery()) {
        while (r.next())
          result.add(
              new Entity<>(
                  UUID.fromString(r.getString("id")),
                  UUID.fromString(r.getString("owner_id")),
                  uuid(r.getString("project_id")),
                  uuid(r.getString("parent_id")),
                  r.getLong("version"),
                  Instant.parse(r.getString("created_at")),
                  Instant.parse(r.getString("updated_at")),
                  codec.read(r.getString("data"), type)));
      }
      return List.copyOf(result);
    } catch (SQLException e) {
      throw SqliteWorkspaceStore.unavailable(e);
    }
  }

  public List<LegacyProject> unclaimedProjects(int offset, int limit) {
    if (!hasLegacy()) return List.of();
    try (var query =
        db.prepareStatement(
            "SELECT p.id,json_extract(p.data,'$.name'),json_extract(p.data,'$.repositoryPath') FROM projects p LEFT JOIN v2_legacy_claims c ON p.id=c.source_id WHERE c.source_id IS NULL ORDER BY p.id LIMIT ? OFFSET ?")) {
      query.setInt(1, Math.min(500, Math.max(1, limit)));
      query.setInt(2, Math.max(0, offset));
      var result = new ArrayList<LegacyProject>();
      try (var rows = query.executeQuery()) {
        while (rows.next())
          result.add(
              new LegacyProject(
                  UUID.fromString(rows.getString(1)), rows.getString(2), rows.getString(3)));
      }
      return List.copyOf(result);
    } catch (SQLException e) {
      throw SqliteWorkspaceStore.unavailable(e);
    }
  }

  public String legacyArchive(UUID project) {
    if (!hasLegacy()) throw WorkspaceFailure.missing();
    var queries =
        Map.of(
            "project", "SELECT data FROM projects WHERE id=?",
            "runs", "SELECT data FROM runs WHERE project_id=?",
            "tasks", "SELECT data FROM tasks WHERE project_id=?",
            "specifications",
                "SELECT s.data FROM specifications s JOIN runs r ON s.run_id=r.id WHERE r.project_id=?",
            "events", "SELECT data FROM outbox WHERE project_id=?");
    var result = new LinkedHashMap<String, Object>();
    for (var entry : queries.entrySet()) {
      var values = new ArrayList<Object>();
      try (var query = db.prepareStatement(entry.getValue())) {
        query.setString(1, project.toString());
        try (var rows = query.executeQuery()) {
          while (rows.next()) values.add(codec.read(rows.getString(1), Object.class));
        }
      } catch (SQLException e) {
        throw SqliteWorkspaceStore.unavailable(e);
      }
      result.put(entry.getKey(), values);
    }
    if (((List<?>) result.get("project")).isEmpty()) throw WorkspaceFailure.missing();
    result.put("schemaVersion", 1);
    return codec.write(result);
  }

  public void claimLegacy(UUID source, UUID owner, UUID project) {
    execute(
        "INSERT INTO v2_legacy_claims(source_id,owner_id,project_id) VALUES(?,?,?)",
        List.of(source, owner, project));
  }

  private boolean hasLegacy() {
    try (var query =
            db.prepareStatement(
                "SELECT 1 FROM sqlite_master WHERE type='table' AND name='projects'");
        var rows = query.executeQuery()) {
      return rows.next();
    } catch (SQLException e) {
      throw SqliteWorkspaceStore.unavailable(e);
    }
  }

  public Set<String> projectPaths() {
    try (var query =
            db.prepareStatement(
                "SELECT json_extract(data,'$.repositoryPath') FROM v2_project UNION SELECT json_extract(data,'$.repositoryPath') FROM v2_workspace_cleanup");
        var rows = query.executeQuery()) {
      var paths = new HashSet<String>();
      while (rows.next()) {
        String path = rows.getString(1);
        if (path != null) paths.add(path);
      }
      return Set.copyOf(paths);
    } catch (SQLException failure) {
      throw SqliteWorkspaceStore.unavailable(failure);
    }
  }

  public Set<String> referencedArtifacts() {
    try (var query =
            db.prepareStatement(
                "SELECT DISTINCT json_extract(data,'$.relativePath') FROM v2_artifact");
        var rows = query.executeQuery()) {
      var paths = new HashSet<String>();
      while (rows.next()) {
        String path = rows.getString(1);
        if (path != null) paths.add(path);
      }
      return Set.copyOf(paths);
    } catch (SQLException e) {
      throw SqliteWorkspaceStore.unavailable(e);
    }
  }

  public <T> List<Entity<T>> reservedBudgets(Class<T> type, int limit) {
    return rows(EntityKind.BUDGET, "json_extract(data,'$.reserved')>0", List.of(), type, limit);
  }

  public Optional<Entity<AuthSessionData>> authSession(String hash) {
    return rows(
            EntityKind.AUTH_SESSION,
            "json_extract(data,'$.tokenHash')=?",
            List.of(hash),
            AuthSessionData.class,
            1)
        .stream()
        .findFirst();
  }

  public <T> List<Entity<T>> states(
      EntityKind kind, Class<T> type, List<String> states, int limit) {
    if (states.isEmpty()) return List.of();
    String placeholders = String.join(",", Collections.nCopies(states.size(), "?"));
    return rows(
        kind, "json_extract(data,'$.status') IN (" + placeholders + ")", states, type, limit);
  }

  public List<Entity<MessageData>> history(UUID owner, UUID conversation, long after, int limit) {
    return rows(
        EntityKind.MESSAGE,
        "owner_id=? AND parent_id=? AND json_extract(data,'$.ordinal')>?",
        List.of(owner, conversation, after),
        MessageData.class,
        limit,
        0,
        "json_extract(data,'$.ordinal'),id");
  }

  public Optional<Entity<MessageData>> latestToolCall(UUID owner, UUID conversation) {
    return rows(
            EntityKind.MESSAGE,
            "owner_id=? AND parent_id=? AND json_extract(data,'$.role')='assistant' AND json_type(data,'$.functionCall')='object'",
            List.of(owner, conversation),
            MessageData.class,
            1,
            0,
            "json_extract(data,'$.ordinal') DESC")
        .stream()
        .findFirst();
  }

  public long nextOrdinal(UUID owner, UUID conversation) {
    try (var p =
        db.prepareStatement(
            "SELECT COALESCE(MAX(json_extract(data,'$.ordinal')),-1)+1 FROM v2_message WHERE owner_id=? AND parent_id=?")) {
      bind(p, List.of(owner, conversation));
      try (var row = p.executeQuery()) {
        return row.next() ? row.getLong(1) : 0;
      }
    } catch (SQLException e) {
      throw SqliteWorkspaceStore.unavailable(e);
    }
  }

  public Optional<Entity<SummaryData>> latestSummary(UUID owner, UUID conversation) {
    return rows(
            EntityKind.SUMMARY,
            "owner_id=? AND parent_id=? AND json_extract(data,'$.valid')=1",
            List.of(owner, conversation),
            SummaryData.class,
            1,
            0,
            "json_extract(data,'$.throughOrdinal') DESC")
        .stream()
        .findFirst();
  }

  public <T> void insert(EntityKind kind, Entity<T> e) {
    execute(
        "INSERT INTO "
            + WorkspaceMigrations.table(kind)
            + "(id,owner_id,project_id,parent_id,version,created_at,updated_at,data) VALUES(?,?,?,?,?,?,?,?)",
        Arrays.asList(
            e.id(),
            e.ownerId(),
            e.projectId(),
            e.parentId(),
            e.version(),
            e.createdAt(),
            e.updatedAt(),
            codec.write(e.data())));
    index(kind, e);
  }

  public <T> void update(EntityKind kind, Entity<T> e, long version) {
    int n =
        execute(
            "UPDATE "
                + WorkspaceMigrations.table(kind)
                + " SET data=?,version=?,updated_at=? WHERE owner_id=? AND id=? AND version=?",
            List.of(
                codec.write(e.data()), e.version(), e.updatedAt(), e.ownerId(), e.id(), version));
    if (n != 1) throw WorkspaceFailure.conflict("Запись изменилась, обновите состояние");
    index(kind, e);
  }

  private <T> void index(EntityKind kind, Entity<T> e) {
    if (kind == EntityKind.MEMORY) {
      execute(
          "DELETE FROM v2_memory_search WHERE id=? AND owner_id=?", List.of(e.id(), e.ownerId()));
      execute(
          "INSERT INTO v2_memory_search(id,owner_id,content) VALUES(?,?,?)",
          List.of(e.id(), e.ownerId(), codec.convert(e.data(), MemoryData.class).content()));
    }
  }

  public void delete(EntityKind kind, UUID owner, UUID id) {
    // Журнал сохраняет ID и hash команды, но удалённое содержимое не остаётся её кэшем.
    execute(
        "UPDATE v2_commands SET data=json_set(data,'$.result',json(?)) WHERE owner_id=? AND json_extract(data,'$.result.id')=?",
        List.of(codec.write(Map.of("deleted", true, "resourceId", id)), owner, id));
    execute(
        "DELETE FROM " + WorkspaceMigrations.table(kind) + " WHERE owner_id=? AND id=?",
        List.of(owner, id));
    if (kind == EntityKind.MEMORY)
      execute("DELETE FROM v2_memory_search WHERE owner_id=? AND id=?", List.of(owner, id));
  }

  public void event(UUID owner, UUID project, String type, Object payload) {
    execute(
        "INSERT INTO v2_events(event_id,owner_id,project_id,type,occurred_at,data) VALUES(?,?,?,?,?,?)",
        Arrays.asList(
            UUID.randomUUID(), owner, project, type, clock.instant(), codec.write(payload)));
  }

  public Optional<CommandReceipt> command(UUID owner, UUID id) {
    try (var p =
        db.prepareStatement("SELECT data FROM v2_commands WHERE owner_id=? AND command_id=?")) {
      bind(p, List.of(owner, id));
      try (var r = p.executeQuery()) {
        return r.next()
            ? Optional.of(codec.read(r.getString(1), CommandReceipt.class))
            : Optional.empty();
      }
    } catch (SQLException e) {
      throw SqliteWorkspaceStore.unavailable(e);
    }
  }

  public void command(UUID owner, CommandReceipt receipt) {
    execute(
        "INSERT INTO v2_commands(owner_id,command_id,hash,data) VALUES(?,?,?,?)",
        List.of(owner, receipt.commandId(), receipt.hash(), codec.write(receipt)));
  }

  public List<StoredEvent> events(UUID owner, long after, int limit) {
    try (var p =
        db.prepareStatement(
            "SELECT * FROM v2_events WHERE owner_id=? AND seq>? ORDER BY seq LIMIT ?")) {
      bind(p, List.of(owner, after, Math.min(500, Math.max(1, limit))));
      var result = new ArrayList<StoredEvent>();
      try (var r = p.executeQuery()) {
        while (r.next())
          result.add(
              new StoredEvent(
                  r.getLong("seq"),
                  UUID.fromString(r.getString("event_id")),
                  owner,
                  uuid(r.getString("project_id")),
                  r.getString("type"),
                  r.getString("occurred_at"),
                  codec.read(r.getString("data"), Object.class)));
      }
      return result;
    } catch (SQLException e) {
      throw SqliteWorkspaceStore.unavailable(e);
    }
  }

  public long watermark(UUID owner) {
    try (var p =
        db.prepareStatement("SELECT COALESCE(MAX(seq),0) FROM v2_events WHERE owner_id=?")) {
      bind(p, List.of(owner));
      try (var r = p.executeQuery()) {
        return r.next() ? r.getLong(1) : 0;
      }
    } catch (SQLException e) {
      throw SqliteWorkspaceStore.unavailable(e);
    }
  }

  public List<UUID> searchMemory(
      UUID owner, UUID project, UUID session, UUID task, String query, int limit) {
    String words =
        Arrays.stream(query.split("[^\\p{L}\\p{N}]+"))
            .filter(w -> w.length() > 1)
            .limit(20)
            .map(w -> "\"" + w + "\"")
            .collect(java.util.stream.Collectors.joining(" OR "));
    if (words.isBlank()) return List.of();
    try (var p =
        db.prepareStatement(
            "SELECT f.id FROM v2_memory_search f JOIN v2_memory m ON m.id=f.id AND m.owner_id=f.owner_id WHERE v2_memory_search MATCH ? AND f.owner_id=? AND json_extract(m.data,'$.status')='active' AND (json_extract(m.data,'$.scope')='user' OR m.project_id=? AND (json_extract(m.data,'$.scope')='project' OR json_extract(m.data,'$.scope')='session' AND json_extract(m.data,'$.scopeId')=? OR json_extract(m.data,'$.scope')='task' AND json_extract(m.data,'$.scopeId')=?)) ORDER BY bm25(v2_memory_search) LIMIT ?")) {
      bind(p, Arrays.asList(words, owner, project, session, task, Math.min(limit, 100)));
      var ids = new ArrayList<UUID>();
      try (var r = p.executeQuery()) {
        while (r.next()) ids.add(UUID.fromString(r.getString(1)));
      }
      return ids;
    } catch (SQLException e) {
      throw SqliteWorkspaceStore.unavailable(e);
    }
  }

  private int execute(String sql, List<?> args) {
    try (var p = db.prepareStatement(sql)) {
      bind(p, args);
      return p.executeUpdate();
    } catch (SQLException e) {
      throw SqliteWorkspaceStore.unavailable(e);
    }
  }

  private static UUID uuid(String s) {
    return s == null ? null : UUID.fromString(s);
  }

  private static void bind(PreparedStatement p, List<?> args) throws SQLException {
    for (int i = 0; i < args.size(); i++) {
      Object a = args.get(i);
      if (a == null) p.setNull(i + 1, java.sql.Types.NULL);
      else if (a instanceof Number) p.setObject(i + 1, a);
      else if (a instanceof Boolean b) p.setInt(i + 1, b ? 1 : 0);
      else p.setString(i + 1, a.toString());
    }
  }
}
