package dev.blot.application.ports;

import dev.blot.core.workspace.*;
import dev.blot.core.workspace.Entity;
import dev.blot.core.workspace.EntityKind;
import dev.blot.core.workspace.conversation.MessageData;
import dev.blot.core.workspace.conversation.SummaryData;
import dev.blot.core.workspace.identity.AuthSessionData;
import java.util.*;
import java.util.function.Function;

/** Короткая транзакция для записей, квитанций и журнала событий. */
public interface WorkspaceStore {
  <T> T transact(Function<Transaction, T> operation);

  interface Transaction {
    <T> Optional<Entity<T>> find(EntityKind kind, UUID owner, UUID id, Class<T> type);

    <T> List<Entity<T>> list(
        EntityKind kind, UUID owner, UUID project, UUID parent, Class<T> type, int limit);

    <T> List<Entity<T>> page(
        EntityKind kind,
        UUID owner,
        UUID project,
        UUID parent,
        Class<T> type,
        int limit,
        int offset);

    <T> List<Entity<T>> after(
        EntityKind kind,
        UUID owner,
        UUID project,
        UUID parent,
        Class<T> type,
        int limit,
        java.time.Instant createdAt,
        UUID id);

    Optional<Entity<AuthSessionData>> authSession(String hash);

    <T> List<Entity<T>> states(EntityKind kind, Class<T> type, List<String> states, int limit);

    default <T> List<Entity<T>> all(
        EntityKind kind, UUID owner, UUID project, UUID parent, Class<T> type) {
      var result = new ArrayList<Entity<T>>();
      int offset = 0;
      while (true) {
        var values = page(kind, owner, project, parent, type, 1000, offset);
        result.addAll(values);
        if (values.size() < 1000) return List.copyOf(result);
        offset += values.size();
      }
    }

    List<Entity<MessageData>> history(UUID owner, UUID conversation, long afterOrdinal, int limit);

    long nextOrdinal(UUID owner, UUID conversation);

    Optional<Entity<MessageData>> latestToolCall(UUID owner, UUID conversation);

    Optional<Entity<SummaryData>> latestSummary(UUID owner, UUID conversation);

    <T> List<Entity<T>> scan(EntityKind kind, Class<T> type, int limit);

    <T> void insert(EntityKind kind, Entity<T> entity);

    <T> void update(EntityKind kind, Entity<T> entity, long expectedVersion);

    void delete(EntityKind kind, UUID owner, UUID id);

    void event(UUID owner, UUID project, String type, Object payload);

    Optional<CommandReceipt> command(UUID owner, UUID commandId);

    void command(UUID owner, CommandReceipt receipt);

    List<StoredEvent> events(UUID owner, long after, int limit);

    long watermark(UUID owner);

    Set<String> referencedArtifacts();

    Set<String> projectPaths();

    List<LegacyProject> unclaimedProjects(int offset, int limit);

    String legacyArchive(UUID project);

    void claimLegacy(UUID sourceProject, UUID owner, UUID project);

    <T> List<Entity<T>> reservedBudgets(Class<T> type, int limit);

    List<UUID> searchMemory(
        UUID owner, UUID project, UUID session, UUID task, String query, int limit);
  }

  record LegacyProject(UUID id, String name, String repositoryPath) {}

  record CommandReceipt(
      UUID commandId, String hash, String decision, UUID operationId, Object result) {}

  record StoredEvent(
      long seq,
      UUID eventId,
      UUID ownerId,
      UUID projectId,
      String type,
      String occurredAt,
      Object payload) {}
}
