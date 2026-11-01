package dev.blot.api.workspace.security;

import dev.blot.api.workspace.transport.RequestActor;
import dev.blot.application.ports.*;
import dev.blot.application.ports.ProviderGateway;
import dev.blot.application.ports.SecretStore;
import dev.blot.application.ports.WorkspaceStore;
import dev.blot.application.workspace.*;
import dev.blot.application.workspace.Records;
import dev.blot.application.workspace.WorkspaceFailure;
import dev.blot.core.workspace.*;
import dev.blot.core.workspace.EntityKind;
import dev.blot.core.workspace.execution.ModelRequestData;
import dev.blot.core.workspace.identity.AccountData;
import jakarta.servlet.http.HttpServletRequest;
import java.util.*;
import org.springframework.web.bind.annotation.*;

@RestController
public final class SecretController {
  private final RequestActor actor;
  private final SecretStore secrets;
  private final WorkspaceStore store;
  private final ProviderGateway provider;

  public SecretController(
      RequestActor actor, SecretStore secrets, WorkspaceStore store, ProviderGateway provider) {
    this.actor = actor;
    this.secrets = secrets;
    this.store = store;
    this.provider = provider;
  }

  public record Key(String key) {}

  @PutMapping("/v2/provider/key")
  public Object key(@RequestBody Key body, HttpServletRequest req) {
    var a = actor.require(req);
    actor.requireLocal(req);
    String key = Records.text(body.key(), "key", 4096);
    store.transact(
        tx -> {
          boolean active =
              tx
                  .all(EntityKind.MODEL_REQUEST, a.accountId(), null, null, ModelRequestData.class)
                  .stream()
                  .anyMatch(row -> Set.of("QUEUED", "RUNNING").contains(row.data().status()));
          if (active)
            throw WorkspaceFailure.conflict("Сначала завершите или отмените запросы к модели");
          secrets.put("provider." + a.accountId(), key);
          return null;
        });
    return Map.of("configured", true);
  }

  @GetMapping("/v2/provider/models")
  public Object models(HttpServletRequest req) {
    return provider.models(actor.require(req).accountId());
  }

  public record Smtp(String host, int port, String username, String password, String from) {}

  @PutMapping("/v2/setup/smtp")
  public Object smtp(@RequestBody Smtp body, HttpServletRequest req) {
    actor.requireLocal(req);
    boolean existing =
        store.transact(
            tx ->
                tx.scan(EntityKind.ACCOUNT, AccountData.class, 10000).stream()
                    .anyMatch(e -> e.data().verified()));
    if (existing) {
      var a = actor.require(req);
      if (a.deviceId() != null)
        throw new WorkspaceFailure(403, "local_required", "Настройка доступна на Mac");
    }
    if (body.port() < 1 || body.port() > 65535)
      throw WorkspaceFailure.invalid("Неверный порт SMTP");
    secrets.put("smtp.host", Records.text(body.host(), "host", 254));
    secrets.put("smtp.port", Integer.toString(body.port()));
    secrets.put("smtp.username", Records.text(body.username(), "username", 254));
    secrets.put("smtp.password", Records.text(body.password(), "password", 4096));
    secrets.put("smtp.from", Records.text(body.from(), "from", 254));
    return Map.of("configured", true);
  }
}
