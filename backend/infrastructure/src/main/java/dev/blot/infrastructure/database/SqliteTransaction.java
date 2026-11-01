package dev.blot.infrastructure.database;

import dev.blot.application.*;
import dev.blot.application.ApplicationEvent;
import dev.blot.application.BlotUnitOfWork.*;
import dev.blot.core.*;
import dev.blot.core.Project;
import dev.blot.core.Run;
import dev.blot.core.SpecificationRevision;
import dev.blot.core.Task;
import java.sql.*;
import java.util.*;
import java.util.function.Function;

final class SqliteTransaction implements Transaction {
  private final Connection connection;
  private final StorageCodec codec = new StorageCodec();

  SqliteTransaction(Connection connection) {
    this.connection = connection;
  }

  private void execute(String sql, Object... params) {
    try (PreparedStatement statement = connection.prepareStatement(sql)) {
      bind(statement, params);
      statement.executeUpdate();
    } catch (SQLException e) {
      throw SqliteUnitOfWork.failure(e);
    }
  }

  private void bind(PreparedStatement statement, Object[] params) throws SQLException {
    for (int i = 0; i < params.length; i++) statement.setObject(i + 1, params[i]);
  }

  private <T> List<T> query(String sql, Function<String, T> decode, Object... params) {
    try (PreparedStatement statement = connection.prepareStatement(sql)) {
      bind(statement, params);
      try (ResultSet results = statement.executeQuery()) {
        List<T> values = new ArrayList<>();
        while (results.next()) values.add(decode.apply(results.getString(1)));
        return List.copyOf(values);
      }
    } catch (SQLException e) {
      throw SqliteUnitOfWork.failure(e);
    }
  }

  @Override
  public ProjectRepository projects() {
    return new ProjectRepository() {
      public Optional<Project> findById(UUID id) {
        return query("SELECT data FROM projects WHERE id=?", codec::decodeProject, id.toString())
            .stream()
            .findFirst();
      }

      public void save(Project value) {
        execute(
            "INSERT INTO projects (id,data) VALUES (?,?)",
            value.id().toString(),
            codec.encode(value));
      }
    };
  }

  @Override
  public RunRepository runs() {
    return new RunRepository() {
      public Optional<Run> findById(UUID id) {
        return query("SELECT data FROM runs WHERE id=?", codec::decodeRun, id.toString()).stream()
            .findFirst();
      }

      public void save(Run value) {
        execute(
            "INSERT INTO runs (id,project_id,data) VALUES (?,?,?) ON CONFLICT(id) DO UPDATE SET data=excluded.data",
            value.id().toString(),
            value.projectId().toString(),
            codec.encode(value));
      }
    };
  }

  @Override
  public SpecificationRevisionRepository specifications() {
    return new SpecificationRevisionRepository() {
      public List<SpecificationRevision> findByRunId(UUID id) {
        return query(
            "SELECT data FROM specifications WHERE run_id=?",
            codec::decodeSpecificationRevision,
            id.toString());
      }

      public void save(SpecificationRevision value) {
        execute(
            "INSERT INTO specifications (id,run_id,revision,data) VALUES (?,?,?,?)",
            value.id().toString(),
            value.runId().toString(),
            value.revision(),
            codec.encode(value));
      }
    };
  }

  @Override
  public TaskRepository tasks() {
    return new TaskRepository() {
      public Optional<Task> findById(UUID id) {
        return query("SELECT data FROM tasks WHERE id=?", codec::decodeTask, id.toString()).stream()
            .findFirst();
      }

      public List<Task> findByRunId(UUID id) {
        return query("SELECT data FROM tasks WHERE run_id=?", codec::decodeTask, id.toString());
      }

      public void save(Task value) {
        execute(
            "INSERT INTO tasks (id,project_id,run_id,data) VALUES (?,?,?,?)",
            value.id().toString(),
            value.projectId().toString(),
            value.runId().toString(),
            codec.encode(value));
        for (UUID id : value.dependencyIds())
          execute(
              "INSERT INTO task_dependencies(task_id,dependency_id) VALUES (?,?)",
              value.id().toString(),
              id.toString());
      }
    };
  }

  @Override
  public void appendEvent(ApplicationEvent event) {
    Map<String, Object> data = new LinkedHashMap<>();
    data.put("eventId", event.eventId().toString());
    data.put("projectId", event.projectId().toString());
    data.put("runId", event.runId() == null ? null : event.runId().toString());
    data.put("entityId", event.entityId().toString());
    data.put("schemaVersion", event.schemaVersion());
    data.put("entityVersion", event.entityVersion());
    data.put("occurredAt", event.occurredAt().toString());
    data.put("type", event.type());
    data.put("payload", event.payload());
    execute(
        "INSERT INTO outbox(event_id,project_id,run_id,data) VALUES (?,?,?,?)",
        event.eventId().toString(),
        event.projectId().toString(),
        event.runId() == null ? null : event.runId().toString(),
        codec.encode(data));
  }
}
