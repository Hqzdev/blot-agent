package dev.blot.api.workspace.v3;

import dev.blot.api.workspace.transport.RequestActor;
import dev.blot.application.ports.V3Store;
import dev.blot.application.workspace.WorkspaceFailure;
import dev.blot.application.workspace.conversation.SessionService;
import dev.blot.application.workspace.v3.V3Workspace;
import jakarta.servlet.http.HttpServletRequest;
import java.util.*;
import java.util.concurrent.atomic.AtomicBoolean;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;
import org.springframework.web.servlet.mvc.method.annotation.SseEmitter;

@RestController
@RequestMapping("/v3")
public final class V3Controller {
  private final V3Store store;
  private final V3Workspace workspace;
  private final RequestActor actor;
  private final SessionService sessions;

  public V3Controller(
      V3Store store, V3Workspace workspace, RequestActor actor, SessionService sessions) {
    this.store = store;
    this.workspace = workspace;
    this.actor = actor;
    this.sessions = sessions;
  }

  @GetMapping("/compatibility")
  public Object compatibility(HttpServletRequest request) {
    var authenticated = actor.require(request);
    return Map.of(
        "schemaVersions",
        List.of(3),
        "commands",
        V3Workspace.COMMANDS,
        "ownerId",
        authenticated.accountId(),
        "workspaceId",
        workspace.workspaceId(authenticated.accountId()),
        "features",
        List.of("direct_chat", "snapshots", "events"));
  }

  @PostMapping("/commands")
  public Object command(@RequestBody V3Workspace.Command command, HttpServletRequest request) {
    return ResponseEntity.accepted().body(workspace.execute(actor.require(request), command));
  }

  @GetMapping("/commands/{id}")
  public Object receipt(@PathVariable UUID id, HttpServletRequest request) {
    var authenticated = actor.require(request);
    return store.transact(
        authenticated.accountId(),
        tx -> tx.receipt(id).orElseThrow(WorkspaceFailure::missing).receipt());
  }

  @GetMapping("/snapshot")
  public Object snapshot(
      @RequestParam(required = false) String cursor,
      @RequestParam(defaultValue = "100") int limit,
      HttpServletRequest request) {
    return workspace.snapshot(actor.require(request).accountId(), cursor, limit);
  }

  @GetMapping(value = "/events", produces = "text/event-stream")
  public SseEmitter events(
      @RequestParam(defaultValue = "0") long after, HttpServletRequest request) {
    var authenticated = actor.require(request);
    if (after < 0
        || after > store.transact(authenticated.accountId(), V3Store.Transaction::sequence))
      throw new WorkspaceFailure(409, "replay_unavailable", "Получите актуальный snapshot");
    String token = actor.token(request);
    boolean local = actor.local(request);
    var emitter = new SseEmitter(0L);
    var closed = new AtomicBoolean();
    emitter.onCompletion(() -> closed.set(true));
    emitter.onTimeout(() -> closed.set(true));
    emitter.onError(error -> closed.set(true));
    Thread.startVirtualThread(
        () -> {
          long cursor = after;
          long heartbeat = 0;
          try {
            while (!closed.get()) {
              sessions.authenticate(token, local);
              long position = cursor;
              for (var event :
                  store.transact(authenticated.accountId(), tx -> tx.events(position, 200))) {
                emitter.send(
                    SseEmitter.event()
                        .id(Long.toString(event.sequence()))
                        .name("record")
                        .data(event));
                cursor = event.sequence();
              }
              if (System.currentTimeMillis() - heartbeat >= 15_000) {
                emitter.send(SseEmitter.event().comment("keepalive"));
                heartbeat = System.currentTimeMillis();
              }
              Thread.sleep(300);
            }
            emitter.complete();
          } catch (Exception failure) {
            emitter.completeWithError(failure);
          }
        });
    return emitter;
  }
}
