package dev.blot.application.workspace.execution;

import dev.blot.application.ports.*;
import dev.blot.application.ports.GitGateway;
import dev.blot.application.ports.JsonCodec;
import dev.blot.application.ports.ProviderGateway;
import dev.blot.application.ports.WorkspaceStore;
import dev.blot.application.workspace.WorkspaceFailure;
import dev.blot.application.workspace.agent.AgentCommunicationTools;
import dev.blot.application.workspace.agent.AgentFiles;
import dev.blot.application.workspace.agent.DelegationService;
import dev.blot.application.workspace.commands.ToolDefinitions;
import dev.blot.application.workspace.identity.TokenGenerator;
import dev.blot.application.workspace.permissions.PermissionService;
import dev.blot.core.workspace.*;
import dev.blot.core.workspace.Entity;
import dev.blot.core.workspace.EntityKind;
import dev.blot.core.workspace.agent.AgentSessionData;
import dev.blot.core.workspace.execution.PreparedActionData;
import java.nio.file.*;
import java.util.*;
import java.util.function.BooleanSupplier;

/** Модель получает только этот проверяемый вход к файловым и системным операциям. */
public final class ToolService {
  private final WorkspaceStore store;
  private final PermissionService permissions;
  private final GitGateway git;
  private final JsonCodec json;
  private final TokenGenerator tokens;
  private final DelegationService delegation;
  private final ToolDefinitions definitions;
  private final AgentFiles files;
  private final PreparedActionExecutor actions;
  private final AgentCommunicationTools communication;

  public ToolService(
      WorkspaceStore store,
      PermissionService permissions,
      GitGateway git,
      JsonCodec json,
      TokenGenerator tokens,
      DelegationService delegation,
      ToolDefinitions definitions,
      AgentFiles files,
      PreparedActionExecutor actions,
      AgentCommunicationTools communication) {
    this.store = store;
    this.permissions = permissions;
    this.git = git;
    this.json = json;
    this.tokens = tokens;
    this.delegation = delegation;
    this.definitions = definitions;
    this.files = files;
    this.actions = actions;
    this.communication = communication;
  }

  public Object execute(
      Entity<AgentSessionData> session,
      ProviderGateway.ToolCall call,
      BooleanSupplier cancelled,
      UUID invocationId) {
    String name = call.name().replace('_', '.');
    Map<String, Object> args = arguments(call.arguments());
    if (cancelled.getAsBoolean())
      throw new WorkspaceFailure(409, "cancelled", "Сессия остановлена");
    return switch (name) {
      case "project.read.file" -> files.read(session, args);
      case "project.search" -> files.search(session, args);
      case "patch.prepare" -> preparePatch(session, args);
      case "patch.apply" ->
          actions.execute(session, UUID.fromString(required(args, "preparedActionId")), cancelled);
      case "process.run" -> run(session, args, cancelled);
      case "artifact.read" -> files.readArtifact(session, args);
      case "task.message" -> communication.message(session, args, invocationId);
      case "user.ask" -> communication.question(session, args, invocationId);
      case "agent.spawn" -> {
        var spec = json.convert(args, Spawn.class);
        yield delegation.spawn(session, spec.title(), spec.criteria(), spec.role(), spec.paths());
      }
      case "agent.wait" -> delegation.results(session);
      default -> throw WorkspaceFailure.invalid("Неизвестный или недоступный инструмент");
    };
  }

  public record Spawn(String title, List<String> criteria, String role, List<String> paths) {}

  public List<ProviderGateway.Function> functions(String role) {
    return definitions.functions(role);
  }

  private Object preparePatch(Entity<AgentSessionData> s, Map<String, Object> a) {
    writable(s);
    Path target = files.path(s, required(a, "path"), true);
    String content = required(a, "content");
    if (content.length() > 1_000_000) throw WorkspaceFailure.invalid("Изменение слишком большое");
    String before = files.hash(target);
    var args =
        Map.<String, Object>of(
            "path", required(a, "path"), "content", content, "beforeHash", before);
    String base = git.inspect(Path.of(s.data().workspace())).baseSha();
    return store.transact(
        tx ->
            permissions.prepare(
                tx,
                s.ownerId(),
                s.projectId(),
                s.id(),
                s.data().taskId(),
                "patch.apply",
                base,
                args));
  }

  private Object run(Entity<AgentSessionData> s, Map<String, Object> a, BooleanSupplier cancelled) {
    if (functions(s.data().role()).stream().noneMatch(f -> f.name().equals("process_run")))
      throw forbidden();
    String base = git.inspect(Path.of(s.data().workspace())).baseSha();
    var preparedArgs = new LinkedHashMap<String, Object>(a);
    preparedArgs.put("snapshotHash", tokens.digest(git.snapshot(Path.of(s.data().workspace()))));
    var action =
        store.transact(
            tx ->
                tx
                    .list(
                        EntityKind.PREPARED_ACTION,
                        s.ownerId(),
                        s.projectId(),
                        s.id(),
                        PreparedActionData.class,
                        10000)
                    .stream()
                    .filter(
                        e ->
                            e.data().capability().equals("process.run")
                                && json.write(e.data().arguments()).equals(json.write(preparedArgs))
                                && e.data().baseSha().equals(base))
                    .reduce((x, y) -> y)
                    .orElseGet(
                        () ->
                            permissions.prepare(
                                tx,
                                s.ownerId(),
                                s.projectId(),
                                s.id(),
                                s.data().taskId(),
                                "process.run",
                                base,
                                preparedArgs)));
    return actions.execute(s, action.id(), cancelled);
  }

  private static void writable(Entity<AgentSessionData> s) {
    if (!Set.of("BACKEND", "FRONTEND", "BUILDER", "INTEGRATOR").contains(s.data().role()))
      throw forbidden();
  }

  private static WorkspaceFailure forbidden() {
    return new WorkspaceFailure(403, "forbidden", "Инструмент выходит за назначенную область");
  }

  private static Map<String, Object> arguments(Object value) {
    if (!(value instanceof Map<?, ?> map)
        || map.keySet().stream().anyMatch(k -> !(k instanceof String)))
      throw WorkspaceFailure.invalid("Ожидается объект аргументов");
    var result = new LinkedHashMap<String, Object>();
    map.forEach((k, v) -> result.put((String) k, v));
    return result;
  }

  private static String required(Map<String, Object> a, String key) {
    Object value = a.get(key);
    if (!(value instanceof String s)) throw WorkspaceFailure.invalid("Нужно поле " + key);
    return s;
  }
}
