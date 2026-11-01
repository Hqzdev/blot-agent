package dev.blot.application.workspace.conversation;

import dev.blot.application.ports.*;
import dev.blot.application.ports.WorkspaceStore;
import dev.blot.application.workspace.Records;
import dev.blot.application.workspace.WorkspaceFailure;
import dev.blot.core.workspace.*;
import dev.blot.core.workspace.Entity;
import dev.blot.core.workspace.EntityKind;
import dev.blot.core.workspace.agent.AgentSessionData;
import dev.blot.core.workspace.conversation.MemoryData;
import dev.blot.core.workspace.conversation.MessageData;
import dev.blot.core.workspace.conversation.SummaryData;
import dev.blot.core.workspace.identity.Actor;
import dev.blot.core.workspace.projects.ProjectData;
import java.util.*;

public final class MemoryService {
  private final WorkspaceStore store;
  private final Records records;

  public MemoryService(WorkspaceStore store, Records records) {
    this.store = store;
    this.records = records;
  }

  public Entity<MemoryData> save(
      WorkspaceStore.Transaction tx,
      Actor actor,
      UUID project,
      UUID id,
      Long version,
      MemoryData data) {
    if (data == null
        || data.scope() == null
        || data.status() == null
        || !Set.of("user", "project", "task", "session").contains(data.scope())
        || !Set.of("active", "candidate", "stale").contains(data.status()))
      throw WorkspaceFailure.invalid("Неверная область или актуальность памяти");
    Records.text(data.content(), "content", 16000);
    if (data.scope().equals("user") && project != null
        || Set.of("user", "project").contains(data.scope()) && data.scopeId() != null)
      throw WorkspaceFailure.invalid("Неверная область памяти");
    if (!data.scope().equals("user") && project == null)
      throw WorkspaceFailure.invalid("Нужен проект");
    if (project != null)
      Records.require(tx, EntityKind.PROJECT, actor.accountId(), project, ProjectData.class);
    if (Set.of("task", "session").contains(data.scope())) {
      var kind = data.scope().equals("task") ? EntityKind.TASK : EntityKind.AGENT_SESSION;
      var target = Records.require(tx, kind, actor.accountId(), data.scopeId(), Map.class);
      if (!Objects.equals(project, target.projectId()))
        throw WorkspaceFailure.invalid("Память относится к другому проекту");
    }
    if (data.sourceId() != null)
      Records.require(
          tx, EntityKind.MESSAGE, actor.accountId(), data.sourceId(), MessageData.class);
    if (id == null)
      return records.create(
          tx, EntityKind.MEMORY, actor.accountId(), project, data.scopeId(), data);
    var old = Records.require(tx, EntityKind.MEMORY, actor.accountId(), id, MemoryData.class);
    Records.version(old, version);
    if (!Objects.equals(old.projectId(), project)
        || !old.data().scope().equals(data.scope())
        || !Objects.equals(old.data().scopeId(), data.scopeId()))
      throw WorkspaceFailure.invalid("Область существующей записи памяти менять нельзя");
    invalidate(tx, actor.accountId(), id);
    return records.change(tx, EntityKind.MEMORY, old, data);
  }

  public List<Entity<MemoryData>> search(UUID owner, UUID project, UUID session, String query) {
    return store.transact(
        tx -> {
          UUID task = null;
          if (session != null)
            task =
                Records.require(
                        tx, EntityKind.AGENT_SESSION, owner, session, AgentSessionData.class)
                    .data()
                    .taskId();
          UUID taskId = task;
          return tx.searchMemory(owner, project, session, taskId, query, 100).stream()
              .map(id -> Records.require(tx, EntityKind.MEMORY, owner, id, MemoryData.class))
              .filter(
                  e ->
                      e.data().status().equals("active")
                          && (e.data().scope().equals("user")
                              || Objects.equals(project, e.projectId())
                                  && (!e.data().scope().equals("session")
                                      || Objects.equals(session, e.data().scopeId()))
                                  && (!e.data().scope().equals("task")
                                      || Objects.equals(taskId, e.data().scopeId()))))
              .limit(20)
              .toList();
        });
  }

  public void delete(WorkspaceStore.Transaction tx, Actor actor, UUID id, Long version) {
    var entry = Records.require(tx, EntityKind.MEMORY, actor.accountId(), id, MemoryData.class);
    Records.version(entry, version);
    invalidate(tx, actor.accountId(), id);
    tx.delete(EntityKind.MEMORY, actor.accountId(), id);
    tx.event(actor.accountId(), null, "memory.deleted", Map.of("id", id));
  }

  public void removeSource(WorkspaceStore.Transaction tx, Actor actor, UUID message) {
    for (var entry : tx.all(EntityKind.MEMORY, actor.accountId(), null, null, MemoryData.class)) {
      var data = entry.data();
      if (message.equals(data.sourceId())) {
        invalidate(tx, actor.accountId(), entry.id());
        records.change(
            tx,
            EntityKind.MEMORY,
            entry,
            new MemoryData(data.scope(), data.scopeId(), data.content(), null, "stale"));
      }
    }
  }

  private void invalidate(WorkspaceStore.Transaction tx, UUID owner, UUID id) {
    for (var s : tx.all(EntityKind.SUMMARY, owner, null, null, SummaryData.class)) {
      var d = s.data();
      if (d.valid() && d.memoryIds().contains(id))
        records.change(
            tx,
            EntityKind.SUMMARY,
            s,
            new SummaryData(
                d.conversationId(), d.throughOrdinal(), d.content(), d.memoryIds(), false));
    }
  }
}
