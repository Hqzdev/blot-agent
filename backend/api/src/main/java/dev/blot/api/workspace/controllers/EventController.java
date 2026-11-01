package dev.blot.api.workspace.controllers;

import dev.blot.api.workspace.transport.RequestActor;
import dev.blot.application.ports.*;
import dev.blot.application.ports.WorkspaceStore;
import dev.blot.application.workspace.*;
import dev.blot.application.workspace.WorkspaceFailure;
import dev.blot.application.workspace.conversation.SessionService;
import jakarta.servlet.http.HttpServletRequest;
import java.util.*;
import java.util.concurrent.atomic.AtomicBoolean;
import org.springframework.web.bind.annotation.*;
import org.springframework.web.servlet.mvc.method.annotation.SseEmitter;

@RestController
public final class EventController {
  private final WorkspaceStore store;
  private final RequestActor actor;
  private final SessionService sessions;

  public EventController(WorkspaceStore store, RequestActor actor, SessionService sessions) {
    this.store = store;
    this.actor = actor;
    this.sessions = sessions;
  }

  @GetMapping(value = "/v2/events", produces = "text/event-stream")
  public SseEmitter events(@RequestParam(defaultValue = "0") long after, HttpServletRequest req) {
    var a = actor.require(req);
    String token = actor.token(req);
    boolean local = actor.local(req);
    var emitter = new SseEmitter(0L);
    var closed = new AtomicBoolean();
    if (after < 0 || after > store.transact(tx -> tx.watermark(a.accountId())))
      throw new WorkspaceFailure(409, "replay_unavailable", "Получите актуальный snapshot");
    emitter.onCompletion(() -> closed.set(true));
    emitter.onTimeout(() -> closed.set(true));
    emitter.onError(e -> closed.set(true));
    Thread.startVirtualThread(
        () -> {
          long cursor = after;
          long heartbeat = 0;
          try {
            while (!closed.get()) {
              sessions.authenticate(token, local);
              long current = cursor;
              var events = store.transact(tx -> tx.events(a.accountId(), current, 200));
              for (var e : events) {
                var data = new LinkedHashMap<String, Object>();
                data.put("schemaVersion", 2);
                data.put("seq", Long.toString(e.seq()));
                data.put("eventId", e.eventId());
                data.put("projectId", e.projectId());
                data.put("type", e.type());
                data.put("occurredAt", e.occurredAt());
                data.put("payload", e.payload());
                emitter.send(
                    SseEmitter.event().id(Long.toString(e.seq())).name("project").data(data));
                cursor = e.seq();
              }
              if (System.currentTimeMillis() - heartbeat > 15000) {
                emitter.send(SseEmitter.event().comment("keepalive"));
                heartbeat = System.currentTimeMillis();
              }
              Thread.sleep(300);
            }
            emitter.complete();
          } catch (Exception e) {
            emitter.completeWithError(e);
          }
        });
    return emitter;
  }
}
