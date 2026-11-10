package dev.blot.client;

import com.fasterxml.jackson.databind.JsonNode;
import dev.blot.core.v3.*;
import java.io.*;
import java.net.*;
import java.nio.charset.StandardCharsets;
import java.time.Instant;
import java.util.*;

/**
 * Blocking transport for a background executor. Tokens stay in memory and redirects are rejected.
 */
public final class WorkspaceClient {
  public record State(
      long sequence,
      List<AgentProfile> agents,
      List<Conversation> conversations,
      List<Message> messages) {
    public State {
      agents = List.copyOf(agents);
      conversations = List.copyOf(conversations);
      messages = List.copyOf(messages);
    }
  }

  public record Receipt(int schemaVersion, UUID commandId, UUID operationId, String state) {}

  public static final class Failure extends IOException {
    private final int status;
    private final String code;

    public Failure(int status, String code, String message) {
      super(message);
      this.status = status;
      this.code = code;
    }

    public int status() {
      return status;
    }

    public String code() {
      return code;
    }
  }

  private final URI base;
  private final String token;
  private final WorkspaceJson json = new WorkspaceJson();
  private UUID ownerId;
  private UUID workspaceId;
  private final Map<UUID, String> commandBodies = new LinkedHashMap<>();

  public WorkspaceClient(URI base, String token) {
    String host = base.getHost();
    boolean loopback =
        "localhost".equalsIgnoreCase(host)
            || "127.0.0.1".equals(host)
            || "[::1]".equals(host)
            || "::1".equals(host);
    if (host == null
        || (!"https".equalsIgnoreCase(base.getScheme())
            && !("http".equalsIgnoreCase(base.getScheme()) && loopback))
        || base.getUserInfo() != null
        || base.getQuery() != null
        || base.getFragment() != null
        || !(base.getPath().isEmpty() || base.getPath().equals("/")))
      throw new IllegalArgumentException(
          "Укажите HTTPS-адрес сервера без пути. HTTP доступен только на этом компьютере.");
    if (token == null
        || token.isBlank()
        || token.length() > 512
        || token.contains("\r")
        || token.contains("\n"))
      throw new IllegalArgumentException("Укажите действующую сессию устройства");
    this.base = base.resolve("/");
    this.token = token;
  }

  public synchronized State connect() throws IOException {
    var info = request("GET", "/v3/compatibility", null);
    boolean version = false;
    for (var v : info.path("schemaVersions")) if (v.asInt() == 3) version = true;
    if (!version) throw new Failure(409, "incompatible", "Сервер не поддерживает v3");
    try {
      ownerId = UUID.fromString(info.path("ownerId").asText());
      workspaceId = UUID.fromString(info.path("workspaceId").asText());
    } catch (IllegalArgumentException e) {
      throw new Failure(502, "invalid_response", "Сервер вернул неверные данные подключения");
    }
    return refresh();
  }

  public synchronized State refresh() throws IOException {
    if (ownerId == null) throw new IllegalStateException("Сначала подключитесь к серверу");
    var agents = new ArrayList<AgentProfile>();
    var conversations = new ArrayList<Conversation>();
    var messages = new ArrayList<Message>();
    String cursor = null;
    long sequence = -1;
    var seen = new HashSet<String>();
    do {
      var page =
          request(
              "GET",
              "/v3/snapshot"
                  + (cursor == null
                      ? ""
                      : "?cursor=" + URLEncoder.encode(cursor, StandardCharsets.UTF_8)),
              null);
      if (page.path("schemaVersion").asInt() != 3
          || !page.path("sequence").canConvertToLong()
          || !page.path("records").isObject()
          || !page.has("nextCursor"))
        throw new Failure(502, "invalid_snapshot", "Неверный snapshot сервера");
      long watermark = page.path("sequence").asLong();
      if (watermark < 0 || (sequence >= 0 && sequence != watermark))
        throw new Failure(
            409, "inconsistent_snapshot", "Данные изменились во время загрузки. Обновите чат.");
      sequence = watermark;
      read(page.path("records").path("AgentProfile"), AgentProfile.class, agents);
      read(page.path("records").path("Conversation"), Conversation.class, conversations);
      read(page.path("records").path("Message"), Message.class, messages);
      cursor = page.path("nextCursor").isNull() ? null : page.path("nextCursor").asText();
      if (cursor != null && (!seen.add(cursor) || seen.size() > 10_000))
        throw new Failure(502, "invalid_cursor", "Сервер повторяет страницу данных");
    } while (cursor != null);
    messages.sort(Comparator.comparing(m -> Objects.requireNonNullElse(m.position(), 0L)));
    return new State(sequence, agents, conversations, messages);
  }

  private <T> void read(JsonNode array, Class<T> type, List<T> destination) throws IOException {
    if (array.isMissingNode()) return;
    if (!array.isArray()) throw new Failure(502, "invalid_snapshot", "Неверный список записей");
    for (var record : array) {
      if (!ownerId.toString().equals(record.path("metadata").path("ownerId").asText())
          || !workspaceId.toString().equals(record.path("metadata").path("workspaceId").asText()))
        throw new Failure(502, "identity_mismatch", "Сервер вернул данные другого пространства");
      destination.add(json.convert(record, type));
    }
  }

  public synchronized Receipt saveAgent(String name, String instructions, String model)
      throws IOException {
    requireConnected();
    var metadata =
        new RecordMetadata(
            UUID.randomUUID(), ownerId, workspaceId, 0, Instant.now(), Instant.now());
    var profile =
        new AgentProfile(
            metadata,
            name,
            "custom",
            "circle",
            "ink",
            instructions,
            model,
            AccessMode.ASK_FIRST,
            null);
    return command("agent.save", Map.of("profile", profile), null);
  }

  public synchronized Receipt createConversation(AgentProfile agent, String title)
      throws IOException {
    return command(
        "conversation.create",
        Map.of("title", title, "agentId", agent.metadata().id(), "kind", "DIRECT"),
        null);
  }

  public synchronized Receipt send(Conversation conversation, String content, UUID commandId)
      throws IOException {
    return command(
        "conversation.send_message",
        Map.of(
            "conversationId",
            conversation.metadata().id(),
            "content",
            content,
            "artifactIds",
            List.of()),
        conversation.metadata().version(),
        commandId);
  }

  private Receipt command(String type, Map<String, ?> payload, Long version) throws IOException {
    return command(type, payload, version, UUID.randomUUID());
  }

  private Receipt command(String type, Map<String, ?> payload, Long version, UUID id)
      throws IOException {
    requireConnected();
    var command = new LinkedHashMap<String, Object>();
    command.put("schemaVersion", 3);
    command.put("commandId", id);
    command.put("workspaceId", workspaceId);
    command.put("type", type);
    command.put("expectedVersion", version);
    command.put("expiresAt", Instant.now().plusSeconds(300).toString());
    command.put("payload", payload);
    String body = commandBodies.get(id);
    if (body == null) {
      body = json.encode(command);
      commandBodies.put(id, body);
      if (commandBodies.size() > 256)
        commandBodies.remove(commandBodies.keySet().iterator().next());
    } else {
      var original = json.tree(body);
      if (!original.path("type").asText().equals(type)
          || !original.path("payload").equals(json.tree(json.encode(payload))))
        throw new IllegalArgumentException("commandId уже связан с другим сообщением");
    }
    try {
      return validatedReceipt(request("POST", "/v3/commands", body), id);
    } catch (Failure failure) {
      if (failure.status() >= 500 && failure.status() != 501) return reconcile(id);
      throw failure;
    } catch (IOException uncertain) {
      return reconcile(id);
    }
  }

  public synchronized Receipt receipt(UUID commandId) throws IOException {
    return validatedReceipt(request("GET", "/v3/commands/" + commandId, null), commandId);
  }

  private Receipt reconcile(UUID id) throws IOException {
    try {
      return receipt(id);
    } catch (IOException unavailable) {
      throw new Failure(
          0,
          "command_uncertain",
          "Связь прервана. Статус отправки неизвестен; повторите проверку с тем же сообщением.");
    }
  }

  private Receipt validatedReceipt(JsonNode value, UUID id) throws IOException {
    var receipt = json.convert(value, Receipt.class);
    if (receipt.schemaVersion() != 3
        || !id.equals(receipt.commandId())
        || receipt.operationId() == null
        || !"ACCEPTED".equals(receipt.state()))
      throw new IOException("Сервер не подтвердил принятие команды");
    return receipt;
  }

  private void requireConnected() {
    if (ownerId == null) throw new IllegalStateException("Сначала подключитесь к серверу");
  }

  private JsonNode request(String method, String path, String body) throws IOException {
    var connection = (HttpURLConnection) base.resolve(path).toURL().openConnection();
    connection.setInstanceFollowRedirects(false);
    connection.setConnectTimeout(30_000);
    connection.setReadTimeout(30_000);
    connection.setRequestMethod(method);
    connection.setRequestProperty("Authorization", "Bearer " + token);
    connection.setRequestProperty("Accept", "application/json");
    try {
      if (body != null) {
        byte[] bytes = body.getBytes(StandardCharsets.UTF_8);
        connection.setDoOutput(true);
        connection.setRequestProperty("Content-Type", "application/json");
        connection.setFixedLengthStreamingMode(bytes.length);
        try (var output = connection.getOutputStream()) {
          output.write(bytes);
        }
      }
      int status = connection.getResponseCode();
      var input = status >= 400 ? connection.getErrorStream() : connection.getInputStream();
      String text;
      if (input == null) text = "{}";
      else
        try (input) {
          byte[] bytes = input.readNBytes(2_097_153);
          if (bytes.length > 2_097_152)
            throw new Failure(502, "response_too_large", "Ответ сервера слишком большой");
          text = new String(bytes, StandardCharsets.UTF_8);
        }
      if (status < 200 || status >= 300) {
        String message = "Сервер отклонил запрос (" + status + ")", code = "http_error";
        try {
          var error = json.tree(text);
          if (error.path("message").isTextual()) message = error.path("message").asText();
          if (error.path("code").isTextual()) code = error.path("code").asText();
        } catch (IOException ignored) {
        }
        throw new Failure(status, code, message);
      }
      return json.tree(text);
    } finally {
      connection.disconnect();
    }
  }
}
