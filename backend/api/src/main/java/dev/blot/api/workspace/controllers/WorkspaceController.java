package dev.blot.api.workspace.controllers;

import dev.blot.api.workspace.transport.RecordCursor;
import dev.blot.api.workspace.transport.RequestActor;
import dev.blot.application.ports.*;
import dev.blot.application.ports.WorkspaceStore;
import dev.blot.application.workspace.*;
import dev.blot.application.workspace.Records;
import dev.blot.application.workspace.WorkspaceFailure;
import dev.blot.application.workspace.agent.RoleCatalog;
import dev.blot.application.workspace.commands.CommandDispatcher;
import dev.blot.application.workspace.commands.ToolDefinitions;
import dev.blot.application.workspace.identity.DeviceService;
import dev.blot.core.workspace.*;
import dev.blot.core.workspace.EntityKind;
import jakarta.servlet.http.HttpServletRequest;
import java.util.*;
import org.springframework.http.*;
import org.springframework.web.bind.annotation.*;

@RestController
@RequestMapping("/v2")
public final class WorkspaceController {
  private static final Set<EntityKind> PUBLIC =
      EnumSet.complementOf(
          EnumSet.of(
              EntityKind.ACCOUNT,
              EntityKind.CHALLENGE,
              EntityKind.AUTH_SESSION,
              EntityKind.PAIRING));
  private final WorkspaceStore store;
  private final CommandDispatcher commands;
  private final RequestActor actor;
  private final DeviceService devices;

  public WorkspaceController(
      WorkspaceStore store, CommandDispatcher commands, RequestActor actor, DeviceService devices) {
    this.store = store;
    this.commands = commands;
    this.actor = actor;
    this.devices = devices;
  }

  @PostMapping("/commands")
  public Object command(@RequestBody CommandDispatcher.Command command, HttpServletRequest req) {
    return ResponseEntity.accepted().body(commands.execute(actor.require(req), command));
  }

  @GetMapping("/commands/{id}")
  public Object receipt(@PathVariable UUID id, HttpServletRequest req) {
    var a = actor.require(req);
    return store.transact(
        tx -> tx.command(a.accountId(), id).orElseThrow(WorkspaceFailure::missing));
  }

  @GetMapping("/records/{kind}")
  public Object list(
      @PathVariable EntityKind kind,
      @RequestParam(required = false) UUID projectId,
      @RequestParam(required = false) UUID parentId,
      @RequestParam(defaultValue = "100") int limit,
      @RequestParam(defaultValue = "0") int offset,
      @RequestParam(required = false) String cursor,
      HttpServletRequest req) {
    var a = actor.require(req);
    allowed(kind);
    if (offset < 0 || offset > 10_000_000 || limit < 1 || limit > 500)
      throw WorkspaceFailure.invalid("Неверная страница");
    if (cursor != null) {
      if (offset != 0) throw WorkspaceFailure.invalid("Используйте курсор без offset");
      var position = RecordCursor.decode(cursor);
      return store.transact(
          tx ->
              tx.after(
                  kind,
                  a.accountId(),
                  projectId,
                  parentId,
                  Object.class,
                  limit,
                  position.createdAt(),
                  position.id()));
    }
    return store.transact(
        tx -> tx.page(kind, a.accountId(), projectId, parentId, Object.class, limit, offset));
  }

  @GetMapping("/records/{kind}/{id}")
  public Object read(@PathVariable EntityKind kind, @PathVariable UUID id, HttpServletRequest req) {
    var a = actor.require(req);
    allowed(kind);
    return store.transact(tx -> Records.require(tx, kind, a.accountId(), id, Object.class));
  }

  @GetMapping("/snapshot")
  public Object snapshot(HttpServletRequest req) {
    var a = actor.require(req);
    return store.transact(
        tx -> {
          var data = new LinkedHashMap<String, Object>();
          var nextOffsets = new LinkedHashMap<String, Integer>();
          var nextCursors = new LinkedHashMap<String, String>();
          for (var kind : PUBLIC) {
            var rows = tx.page(kind, a.accountId(), null, null, Object.class, 501, 0);
            data.put(kind.name(), rows.stream().limit(500).toList());
            if (rows.size() > 500) {
              nextOffsets.put(kind.name(), 500);
              nextCursors.put(kind.name(), RecordCursor.encode(rows.get(499)));
            }
          }
          return Map.of(
              "schemaVersion",
              2,
              "watermark",
              Long.toString(tx.watermark(a.accountId())),
              "records",
              data,
              "nextOffsets",
              nextOffsets,
              "nextCursors",
              nextCursors);
        });
  }

  @GetMapping("/pairing/{id}/ticket")
  public Object ticket(@PathVariable UUID id, HttpServletRequest req) {
    return devices.ticket(actor.require(req), id);
  }

  public record PairRequest(UUID id, String secret, String name, String platform) {}

  @PostMapping("/pairing/request")
  public Object pair(@RequestBody PairRequest p) {
    return Map.of("deviceId", devices.request(p.id(), p.secret(), p.name(), p.platform()));
  }

  @PostMapping("/pairing/claim")
  public Object claim(@RequestBody PairRequest p) {
    return devices.claim(p.id(), p.secret());
  }

  @GetMapping("/roles")
  public Object roles(HttpServletRequest req) {
    actor.require(req);
    var catalog = new RoleCatalog();
    var tools = new ToolDefinitions();
    return catalog.roles().stream()
        .sorted()
        .map(
            role ->
                Map.of(
                    "role",
                    role,
                    "instruction",
                    catalog.instruction(role),
                    "functions",
                    tools.functions(role)))
        .toList();
  }

  @GetMapping("/compatibility")
  public Object compatibility() {
    return Map.of(
        "schemaVersions", List.of(2), "commands", commands.types(), "serverVersion", "2.0.0");
  }

  private static void allowed(EntityKind kind) {
    if (!PUBLIC.contains(kind)) throw WorkspaceFailure.missing();
  }
}
