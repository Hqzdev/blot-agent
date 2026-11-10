package dev.blot.application.workspace.v3;

import dev.blot.application.ports.*;
import dev.blot.application.ports.V3Store.Record;
import dev.blot.application.workspace.WorkspaceFailure;
import dev.blot.core.v3.*;
import dev.blot.core.workspace.identity.Actor;
import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.time.*;
import java.util.*;

/** The server owns identity, metadata, versions and message ordering. */
public final class V3Workspace {
  public static final Set<String> COMMANDS =
      Set.of(
          "agent.save",
          "conversation.create",
          "conversation.send_message",
          "conversation.update",
          "conversation.delete");

  public record Command(
      int schemaVersion,
      UUID commandId,
      UUID workspaceId,
      String type,
      Long expectedVersion,
      Instant expiresAt,
      Map<String, Object> payload) {}

  public record Snapshot(
      int schemaVersion,
      long sequence,
      Map<String, List<Map<String, Object>>> records,
      String nextCursor) {}

  private final V3Store store;
  private final JsonCodec json;
  private final Clock clock;

  public V3Workspace(V3Store store, JsonCodec json, Clock clock) {
    this.store = store;
    this.json = json;
    this.clock = clock;
  }

  public UUID workspaceId(UUID owner) {
    return UUID.nameUUIDFromBytes(("blot:v3:" + owner).getBytes(StandardCharsets.UTF_8));
  }

  public V3Store.Receipt execute(Actor actor, Command command) {
    if (command == null
        || command.schemaVersion() != 3
        || command.commandId() == null
        || command.type() == null
        || command.expiresAt() == null
        || command.payload() == null) throw WorkspaceFailure.invalid("Неверная команда v3");
    if (command.workspaceId() != null
        && !workspaceId(actor.accountId()).equals(command.workspaceId()))
      throw WorkspaceFailure.missing();
    String digest = digest(json.write(command));
    return store.transact(
        actor.accountId(),
        tx -> {
          var existing = tx.receipt(command.commandId());
          if (existing.isPresent()) {
            if (!existing.get().digest().equals(digest))
              throw WorkspaceFailure.conflict("commandId уже использован с другим содержимым");
            return existing.get().receipt();
          }
          if (!command.expiresAt().isAfter(clock.instant()))
            throw WorkspaceFailure.invalid("Команда просрочена");
          if (!COMMANDS.contains(command.type()))
            throw new WorkspaceFailure(
                501, "unsupported_command", "Эта операция ещё не поддерживается сервером v3");
          switch (command.type()) {
            case "agent.save" -> saveAgent(tx, actor, command);
            case "conversation.create" -> createConversation(tx, actor, command);
            case "conversation.send_message" -> sendMessage(tx, actor, command);
            case "conversation.update", "conversation.delete" ->
                updateConversation(tx, actor, command);
            default -> throw new IllegalStateException();
          }
          var receipt = new V3Store.Receipt(3, command.commandId(), UUID.randomUUID(), "ACCEPTED");
          tx.accept(command.commandId(), digest, receipt);
          return receipt;
        });
  }

  private void saveAgent(V3Store.Transaction tx, Actor actor, Command command) {
    fields(command.payload(), Set.of("profile"));
    AgentProfile profile;
    try {
      profile = json.convert(command.payload().get("profile"), AgentProfile.class);
    } catch (IllegalArgumentException e) {
      throw WorkspaceFailure.invalid("Неверный профиль агента");
    }
    if (profile == null) throw WorkspaceFailure.invalid("Укажите профиль агента");
    var old = tx.find("AgentProfile", profile.metadata().id());
    long version = expected(command, old);
    var metadata = metadata(actor.accountId(), profile.metadata().id(), version, old.orElse(null));
    var value =
        new AgentProfile(
            metadata,
            nonempty(profile.name()),
            profile.roleId(),
            profile.avatarShape(),
            profile.avatarColor(),
            profile.instructions(),
            nonempty(profile.modelId()),
            profile.accessMode(),
            null);
    put(tx, "AgentProfile", metadata, value);
  }

  private void createConversation(V3Store.Transaction tx, Actor actor, Command command) {
    fields(command.payload(), Set.of("title", "agentId", "kind"));
    if (!command.payload().containsKey("agentId"))
      throw WorkspaceFailure.invalid("Укажите agentId");
    if (command.expectedVersion() != null && command.expectedVersion() != 0)
      throw WorkspaceFailure.conflict("Новая запись имеет версию 0");
    UUID agent = optionalId(command.payload().get("agentId"));
    if (agent != null) require(tx, "AgentProfile", agent);
    var kind = command.payload().getOrDefault("kind", "DIRECT");
    if (!"DIRECT".equals(kind))
      throw new WorkspaceFailure(
          501, "group_runtime_unavailable", "Групповой runtime ещё не поддерживается сервером");
    var metadata = metadata(actor.accountId(), UUID.randomUUID(), 1, null);
    put(
        tx,
        "Conversation",
        metadata,
        new Conversation(
            metadata,
            agent,
            text(command.payload(), "title"),
            actor.deviceId() != null,
            false,
            false,
            ConversationKind.DIRECT));
  }

  private void sendMessage(V3Store.Transaction tx, Actor actor, Command command) {
    fields(
        command.payload(),
        Set.of("conversationId", "content", "artifactIds", "replyToMessageId", "mentions"));
    var conversation = require(tx, "Conversation", id(command.payload().get("conversationId")));
    expected(command, Optional.of(conversation));
    var chat = json.convert(conversation.value(), Conversation.class);
    if (chat.agentId() == null) throw WorkspaceFailure.invalid("Выберите агента для чата");
    require(tx, "AgentProfile", chat.agentId());
    if (!(command.payload().get("artifactIds") instanceof List<?> attachments)
        || !attachments.isEmpty())
      throw new WorkspaceFailure(
          501, "attachments_unavailable", "Вложения ещё не поддерживаются сервером v3");
    if (command.payload().get("mentions") instanceof List<?> mentions && !mentions.isEmpty())
      throw new WorkspaceFailure(
          501, "mentions_unavailable", "Упоминания ещё не поддерживаются сервером v3");
    UUID replyId = optionalId(command.payload().get("replyToMessageId"));
    if (replyId != null
        && !json.convert(require(tx, "Message", replyId).value(), Message.class)
            .conversationId()
            .equals(chat.metadata().id()))
      throw WorkspaceFailure.invalid("Ответ должен относиться к тому же чату");
    var messages =
        tx.records("Message").stream()
            .map(r -> json.convert(r.value(), Message.class))
            .filter(m -> m.conversationId().equals(chat.metadata().id()))
            .toList();
    if (messages.stream()
        .anyMatch(
            m ->
                m.role() == MessageRole.ASSISTANT
                    && (m.delivery() == DeliveryState.SAVED
                        || m.delivery() == DeliveryState.RUNNING)))
      throw WorkspaceFailure.conflict("Дождитесь ответа агента");
    long position =
        messages.stream()
                .map(Message::position)
                .filter(Objects::nonNull)
                .mapToLong(Long::longValue)
                .max()
                .orElse(0)
            + 1;
    var metadata = metadata(actor.accountId(), command.commandId(), 1, null);
    if (tx.find("Message", metadata.id()).isPresent())
      throw WorkspaceFailure.conflict("Идентификатор сообщения уже занят");
    put(
        tx,
        "Message",
        metadata,
        new Message(
            metadata,
            chat.metadata().id(),
            MessageRole.USER,
            text(command.payload(), "content"),
            DeliveryState.ACCEPTED,
            command.commandId(),
            List.of(),
            null,
            replyId,
            List.of(),
            position,
            null));
    var response = metadata(actor.accountId(), UUID.randomUUID(), 1, null);
    put(
        tx,
        "Message",
        response,
        new Message(
            response,
            chat.metadata().id(),
            MessageRole.ASSISTANT,
            "",
            DeliveryState.SAVED,
            command.commandId(),
            List.of(),
            chat.agentId(),
            metadata.id(),
            List.of(),
            position + 1,
            null));
  }

  private void updateConversation(V3Store.Transaction tx, Actor actor, Command command) {
    boolean delete = command.type().equals("conversation.delete");
    fields(
        command.payload(),
        delete
            ? Set.of("conversationId")
            : Set.of("conversationId", "title", "pinned", "archived"));
    var old = require(tx, "Conversation", id(command.payload().get("conversationId")));
    long version = expected(command, Optional.of(old));
    var chat = json.convert(old.value(), Conversation.class);
    var metadata = metadata(actor.accountId(), old.id(), version, old);
    if (delete) {
      tx.put(
          new Record(
              old.kind(),
              old.id(),
              version,
              map(
                  new Conversation(
                      metadata,
                      chat.agentId(),
                      chat.title(),
                      chat.mobileOwned(),
                      chat.pinned(),
                      chat.archived(),
                      chat.kind())),
              true));
      for (var record : tx.records("Message")) {
        var message = json.convert(record.value(), Message.class);
        if (message.conversationId().equals(old.id()))
          tx.put(new Record("Message", record.id(), record.version() + 1, record.value(), true));
      }
    } else {
      var p = command.payload();
      put(
          tx,
          "Conversation",
          metadata,
          new Conversation(
              metadata,
              chat.agentId(),
              p.containsKey("title") ? text(p, "title") : chat.title(),
              chat.mobileOwned(),
              bool(p, "pinned", chat.pinned()),
              bool(p, "archived", chat.archived()),
              chat.kind()));
    }
  }

  public Snapshot snapshot(UUID owner, String cursor, int limit) {
    if (limit < 1 || limit > 500) throw WorkspaceFailure.invalid("Неверный размер страницы");
    return store.transact(
        owner,
        tx -> {
          var page = tx.snapshot(cursor, limit);
          var records = new LinkedHashMap<String, List<Map<String, Object>>>();
          for (var record : page.records())
            records
                .computeIfAbsent(record.kind(), ignored -> new ArrayList<>())
                .add(record.value());
          return new Snapshot(3, page.sequence(), records, page.nextCursor());
        });
  }

  public Record require(V3Store.Transaction tx, String kind, UUID id) {
    return tx.find(kind, id).filter(r -> !r.deleted()).orElseThrow(WorkspaceFailure::missing);
  }

  public RecordMetadata metadata(UUID owner, UUID id, long version, Record old) {
    var created =
        old == null
            ? clock.instant()
            : json.convert(old.value().get("metadata"), RecordMetadata.class).createdAt();
    return new RecordMetadata(id, owner, workspaceId(owner), version, created, clock.instant());
  }

  public void put(V3Store.Transaction tx, String kind, RecordMetadata metadata, Object value) {
    tx.put(new Record(kind, metadata.id(), metadata.version(), map(value), false));
  }

  @SuppressWarnings("unchecked")
  private Map<String, Object> map(Object value) {
    return json.convert(value, Map.class);
  }

  private static long expected(Command command, Optional<Record> old) {
    long current = old.map(Record::version).orElse(0L);
    if (old.filter(Record::deleted).isPresent()
        || (current > 0 && command.expectedVersion() == null)
        || (command.expectedVersion() != null && command.expectedVersion() != current))
      throw WorkspaceFailure.conflict("Версия записи изменилась");
    return current + 1;
  }

  private static void fields(Map<String, Object> value, Set<String> allowed) {
    if (!allowed.containsAll(value.keySet()))
      throw WorkspaceFailure.invalid("Неизвестные поля команды");
  }

  private static boolean bool(Map<String, Object> value, String key, boolean fallback) {
    if (!value.containsKey(key)) return fallback;
    if (!(value.get(key) instanceof Boolean result))
      throw WorkspaceFailure.invalid("Неверный флаг " + key);
    return result;
  }

  private static String nonempty(String value) {
    if (value == null || value.isBlank() || value.length() > 100_000)
      throw WorkspaceFailure.invalid("Укажите текст длиной до 100000 символов");
    return value;
  }

  private static String text(Map<String, Object> payload, String key) {
    if (!(payload.get(key) instanceof String value))
      throw WorkspaceFailure.invalid("Укажите " + key);
    return nonempty(value);
  }

  private static UUID id(Object value) {
    try {
      return UUID.fromString(Objects.toString(value, ""));
    } catch (IllegalArgumentException e) {
      throw WorkspaceFailure.invalid("Неверный идентификатор");
    }
  }

  private static UUID optionalId(Object value) {
    return value == null ? null : id(value);
  }

  private static String digest(String value) {
    try {
      return HexFormat.of()
          .formatHex(
              MessageDigest.getInstance("SHA-256").digest(value.getBytes(StandardCharsets.UTF_8)));
    } catch (java.security.NoSuchAlgorithmException e) {
      throw new IllegalStateException(e);
    }
  }
}
