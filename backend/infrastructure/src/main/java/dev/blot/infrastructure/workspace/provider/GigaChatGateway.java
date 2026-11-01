package dev.blot.infrastructure.workspace.provider;

import dev.blot.application.ports.*;
import dev.blot.application.ports.JsonCodec;
import dev.blot.application.ports.ProviderGateway;
import dev.blot.application.ports.SecretStore;
import dev.blot.application.workspace.WorkspaceFailure;
import dev.blot.application.workspace.identity.TokenGenerator;
import java.net.*;
import java.net.http.*;
import java.time.*;
import java.util.*;
import java.util.concurrent.*;
import java.util.function.*;

/** HTTP и формат провайдера не выходят за границы этого адаптера. */
public final class GigaChatGateway implements ProviderGateway {
  private record Access(String token, Instant expires, String keyHash) {}

  private final GigaChatTls http;
  private final TokenGenerator tokens = new TokenGenerator();
  private final JsonCodec json;
  private final SecretStore secrets;
  private final URI api;
  private final URI oauth;
  private final Clock clock;
  private final Map<String, Access> access = new ConcurrentHashMap<>();

  public GigaChatGateway(
      HttpClient http, JsonCodec json, SecretStore secrets, URI api, URI oauth, Clock clock) {
    this.http = new GigaChatTls(secrets, http);
    this.json = json;
    this.secrets = secrets;
    this.api = URI.create(api.toString().endsWith("/") ? api.toString() : api.toString() + "/");
    this.oauth = oauth;
    this.clock = clock;
    if (!api.getScheme().equals("https") || !oauth.getScheme().equals("https"))
      throw new IllegalArgumentException("Provider requires TLS");
  }

  private synchronized String token(UUID owner) {
    String key =
        secrets
            .get("provider." + owner)
            .orElseThrow(
                () -> new WorkspaceFailure(503, "provider_unconfigured", "Подключите GigaChat"));
    String keyHash = tokens.digest(key);
    var cached = access.get(keyHash);
    if (cached != null
        && cached.keyHash().equals(keyHash)
        && cached.expires().isAfter(clock.instant().plusSeconds(60))) return cached.token();
    try {
      var req =
          HttpRequest.newBuilder(oauth)
              .timeout(Duration.ofSeconds(30))
              .header("Authorization", "Basic " + key)
              .header("RqUID", UUID.randomUUID().toString())
              .header("Content-Type", "application/x-www-form-urlencoded")
              .POST(HttpRequest.BodyPublishers.ofString("scope=GIGACHAT_API_PERS"))
              .build();
      var response = http.client(owner).send(req, HttpResponse.BodyHandlers.ofString());
      check(response.statusCode());
      Map<?, ?> data = json.read(response.body(), Map.class);
      var a =
          new Access(
              (String) data.get("access_token"),
              Instant.ofEpochMilli(((Number) data.get("expires_at")).longValue()),
              keyHash);
      access.put(keyHash, a);
      return a.token();
    } catch (InterruptedException e) {
      Thread.currentThread().interrupt();
      throw cancelled();
    } catch (java.io.IOException | ClassCastException | NullPointerException e) {
      throw unavailable();
    }
  }

  public String concurrencyKey(UUID owner) {
    String key =
        secrets
            .get("provider." + owner)
            .orElseThrow(
                () -> new WorkspaceFailure(503, "provider_unconfigured", "Подключите GigaChat"));
    return tokens.digest(key);
  }

  public List<String> models(UUID owner) {
    Map<?, ?> data = request(owner, "models", null);
    Object rows = data.get("data");
    if (!(rows instanceof List<?> list)) throw unavailable();
    return list.stream().map(v -> (String) ((Map<?, ?>) v).get("id")).toList();
  }

  public long countTokens(UUID owner, String model, String text) {
    Object response = raw(owner, "tokens/count", Map.of("model", model, "input", List.of(text)));
    if (response instanceof List<?> list
        && !list.isEmpty()
        && list.getFirst() instanceof Map<?, ?> m
        && m.get("tokens") instanceof Number n) return n.longValue();
    throw unavailable();
  }

  public Reply generate(Request r, Consumer<String> onText, BooleanSupplier cancelled) {
    var messages = new ArrayList<Map<String, Object>>();
    for (var m : r.messages()) {
      var row = new LinkedHashMap<String, Object>();
      row.put("role", m.role());
      row.put("content", m.content());
      if (m.name() != null) row.put("name", m.name());
      if (m.functionCall() != null) row.put("function_call", m.functionCall());
      if (m.functionStateId() != null) row.put("functions_state_id", m.functionStateId());
      messages.add(row);
    }
    var body = new LinkedHashMap<String, Object>();
    body.put("model", r.model());
    body.put("messages", messages);
    body.put("max_tokens", r.maxOutputTokens());
    body.put("stream", true);
    if (!r.functions().isEmpty()) {
      body.put("functions", r.functions());
      body.put("function_call", "auto");
    }
    var text = new StringBuilder();
    var calls = new ArrayList<ToolCall>();
    Long input = null, output = null;
    String functionName = null, functionState = null;
    Object functionArguments = null;
    var fragments = new StringBuilder();
    boolean ended = false;
    try {
      var req =
          builder(r.ownerId(), "chat/completions")
              .POST(HttpRequest.BodyPublishers.ofString(json.write(body)))
              .build();
      var response = streamingResponse(r.ownerId(), req, cancelled);
      if (response.statusCode() != 200) {
        response.body().close();
        if (response.statusCode() == 401) access.remove(concurrencyKey(r.ownerId()));
        check(response.statusCode());
      }
      try (var cancellation = new StreamCancellation(response.body(), cancelled);
          var reader =
              new java.io.BufferedReader(
                  new java.io.InputStreamReader(
                      response.body(), java.nio.charset.StandardCharsets.UTF_8))) {
        String line;
        while ((line = reader.readLine()) != null) {
          if (cancelled.getAsBoolean()) throw cancelled();
          if (!line.startsWith("data:")) continue;
          String data = line.substring(5).strip();
          if (data.equals("[DONE]")) {
            ended = true;
            break;
          }
          Map<?, ?> chunk = json.read(data, Map.class);
          if (chunk.get("usage") instanceof Map<?, ?> u) {
            if (u.get("prompt_tokens") instanceof Number n) input = n.longValue();
            if (u.get("completion_tokens") instanceof Number n) output = n.longValue();
          }
          if (chunk.get("choices") instanceof List<?> choices) {
            for (Object value : choices) {
              Map<?, ?> choice = (Map<?, ?>) value;
              String finish = String.valueOf(choice.get("finish_reason"));
              if (Set.of("stop", "function_call").contains(finish)) ended = true;
              if (finish.equals("blacklist"))
                throw new WorkspaceFailure(422, "provider_refused", "Модель отказалась отвечать");
              if (finish.equals("length"))
                throw new WorkspaceFailure(422, "output_limit", "Ответ достиг лимита модели");
              if (choice.get("delta") instanceof Map<?, ?> d) {
                if (d.get("content") instanceof String part) {
                  text.append(part);
                  onText.accept(part);
                }
                if (d.get("function_call") instanceof Map<?, ?> f) {
                  if (f.get("name") instanceof String name) functionName = name;
                  if (f.get("arguments") instanceof String part) fragments.append(part);
                  else if (f.get("arguments") != null) functionArguments = f.get("arguments");
                  if (d.get("functions_state_id") instanceof String state) functionState = state;
                }
              }
            }
          }
        }
      }
      if (cancelled.getAsBoolean()) throw cancelled();
      if (!ended) throw unavailable();
      if (functionName != null) {
        if (!fragments.isEmpty()) functionArguments = json.read(fragments.toString(), Object.class);
        if (!(functionArguments instanceof Map<?, ?>)) throw unavailable();
        calls.add(new ToolCall(functionName, functionArguments, functionState));
      }
      return new Reply(text.toString(), List.copyOf(calls), input, output);
    } catch (InterruptedException e) {
      Thread.currentThread().interrupt();
      throw cancelled();
    } catch (java.io.IOException e) {
      if (cancelled.getAsBoolean()) throw cancelled();
      throw unavailable();
    }
  }

  private HttpResponse<java.io.InputStream> streamingResponse(
      UUID owner, HttpRequest request, BooleanSupplier cancelled)
      throws java.io.IOException, InterruptedException {
    if (cancelled.getAsBoolean()) throw cancelled();
    var response = http.client(owner).sendAsync(request, HttpResponse.BodyHandlers.ofInputStream());
    boolean delivered = false;
    try {
      while (true) {
        if (cancelled.getAsBoolean()) throw cancelled();
        try {
          var value = response.get(100, TimeUnit.MILLISECONDS);
          delivered = true;
          return value;
        } catch (TimeoutException waiting) {
          /* Проверяем остановку и до получения заголовков. */
        }
      }
    } catch (ExecutionException failure) {
      throw new java.io.IOException("Provider request failed", failure.getCause());
    } catch (CancellationException failure) {
      throw new java.io.IOException("Provider request cancelled", failure);
    } finally {
      if (!delivered) {
        response.cancel(true);
        if (!response.isCompletedExceptionally() && !response.isCancelled()) {
          var value = response.getNow(null);
          if (value != null) value.body().close();
        }
      }
    }
  }

  private Map<?, ?> request(UUID owner, String path, Object body) {
    return (Map<?, ?>) raw(owner, path, body);
  }

  private Object raw(UUID owner, String path, Object body) {
    try {
      var builder = builder(owner, path);
      if (body == null) builder.GET();
      else builder.POST(HttpRequest.BodyPublishers.ofString(json.write(body)));
      var response = http.client(owner).send(builder.build(), HttpResponse.BodyHandlers.ofString());
      if (response.statusCode() == 401) access.remove(concurrencyKey(owner));
      check(response.statusCode());
      return json.read(response.body(), Object.class);
    } catch (InterruptedException e) {
      Thread.currentThread().interrupt();
      throw cancelled();
    } catch (java.io.IOException e) {
      throw unavailable();
    }
  }

  private HttpRequest.Builder builder(UUID owner, String path) {
    return HttpRequest.newBuilder(api.resolve(path))
        .timeout(Duration.ofMinutes(3))
        .header("Authorization", "Bearer " + token(owner))
        .header("Content-Type", "application/json")
        .header("Accept", "application/json");
  }

  private static void check(int code) {
    if (code >= 200 && code < 300) return;
    if (code == 401 || code == 403)
      throw new WorkspaceFailure(503, "provider_authorization", "Проверьте доступ GigaChat");
    if (code == 429)
      throw new WorkspaceFailure(429, "provider_rate_limit", "Достигнут лимит провайдера");
    if (Set.of(500, 502, 503, 504).contains(code))
      throw new WorkspaceFailure(503, "provider_temporary", "Временный отказ провайдера");
    throw new WorkspaceFailure(
        422,
        "provider_request_rejected",
        "Провайдер отклонил запрос; проверьте модель и параметры");
  }

  private static WorkspaceFailure unavailable() {
    return new WorkspaceFailure(
        503, "provider_unavailable", "Провайдер недоступен или вернул неверный ответ");
  }

  private static WorkspaceFailure cancelled() {
    return new WorkspaceFailure(409, "cancelled", "Запрос отменён");
  }
}
