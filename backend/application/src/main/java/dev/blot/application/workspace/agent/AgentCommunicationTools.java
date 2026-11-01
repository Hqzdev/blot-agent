package dev.blot.application.workspace.agent;

import dev.blot.application.ports.*;
import dev.blot.application.ports.WorkspaceStore;
import dev.blot.application.workspace.Records;
import dev.blot.application.workspace.WorkspaceFailure;
import dev.blot.core.workspace.*;
import dev.blot.core.workspace.Entity;
import dev.blot.core.workspace.EntityKind;
import dev.blot.core.workspace.agent.AgentSessionData;
import dev.blot.core.workspace.conversation.InboxData;
import java.nio.file.*;
import java.util.*;

/** Общение с коллегами и владельцем не меняет системные права агента. */
public final class AgentCommunicationTools {
  private final WorkspaceStore store;
  private final Records records;

  public AgentCommunicationTools(WorkspaceStore store, Records records) {
    this.store = store;
    this.records = records;
  }

  public Object message(Entity<AgentSessionData> s, Map<String, Object> a, UUID invocationId) {
    UUID recipient = UUID.fromString(required(a, "recipientSessionId"));
    return store.transact(
        tx -> {
          var other =
              Records.require(
                  tx, EntityKind.AGENT_SESSION, s.ownerId(), recipient, AgentSessionData.class);
          if (!Objects.equals(s.projectId(), other.projectId())
              || !Objects.equals(s.parentId(), other.parentId())) throw forbidden();
          var existing =
              tx
                  .all(EntityKind.INBOX, s.ownerId(), s.projectId(), recipient, InboxData.class)
                  .stream()
                  .filter(e -> invocationId != null && invocationId.equals(e.data().invocationId()))
                  .findFirst();
          if (existing.isPresent()) return existing.get();
          long count =
              tx
                  .list(
                      EntityKind.INBOX,
                      s.ownerId(),
                      s.projectId(),
                      recipient,
                      InboxData.class,
                      10000)
                  .stream()
                  .filter(e -> !e.data().processed())
                  .count();
          if (count >= 20)
            throw new WorkspaceFailure(
                429, "message_limit", "Получатель ещё не обработал сообщения");
          return records.create(
              tx,
              EntityKind.INBOX,
              s.ownerId(),
              s.projectId(),
              recipient,
              new InboxData(
                  s.id(),
                  recipient,
                  s.data().taskId(),
                  Records.text(required(a, "content"), "content", 8000),
                  false,
                  invocationId));
        });
  }

  public Object question(Entity<AgentSessionData> s, Map<String, Object> a, UUID invocationId) {
    Object options = a.get("options");
    if (!(options instanceof List<?> list)
        || list.size() != 3
        || list.stream().anyMatch(v -> !(v instanceof String)))
      throw WorkspaceFailure.invalid("Нужны три варианта ответа");
    for (Object option : list) Records.text((String) option, "option", 1000);
    return store.transact(
        tx -> {
          var existing =
              tx.all(EntityKind.CHECKPOINT, s.ownerId(), s.projectId(), s.id(), Map.class).stream()
                  .filter(
                      e ->
                          invocationId != null
                              && invocationId
                                  .toString()
                                  .equals(String.valueOf(e.data().get("invocationId"))))
                  .findFirst();
          if (existing.isPresent()) return existing.get();
          var question = new LinkedHashMap<String, Object>();
          question.put("type", "question");
          question.put("question", Records.text(required(a, "question"), "question", 2000));
          question.put("options", list);
          question.put("open", true);
          if (invocationId != null) question.put("invocationId", invocationId);
          return records.create(
              tx, EntityKind.CHECKPOINT, s.ownerId(), s.projectId(), s.id(), question);
        });
  }

  private static WorkspaceFailure forbidden() {
    return new WorkspaceFailure(403, "forbidden", "Инструмент выходит за назначенную область");
  }

  private static String required(Map<String, Object> a, String key) {
    Object value = a.get(key);
    if (!(value instanceof String s)) throw WorkspaceFailure.invalid("Нужно поле " + key);
    return s;
  }
}
