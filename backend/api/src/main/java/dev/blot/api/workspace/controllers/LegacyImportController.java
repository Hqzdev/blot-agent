package dev.blot.api.workspace.controllers;

import dev.blot.api.workspace.transport.RequestActor;
import dev.blot.application.ports.*;
import dev.blot.application.ports.WorkspaceStore;
import dev.blot.application.workspace.WorkspaceFailure;
import jakarta.servlet.http.HttpServletRequest;
import org.springframework.web.bind.annotation.*;

@RestController
public final class LegacyImportController {
  private final WorkspaceStore store;
  private final RequestActor actors;

  public LegacyImportController(WorkspaceStore store, RequestActor actors) {
    this.store = store;
    this.actors = actors;
  }

  @GetMapping("/v2/legacy/projects")
  public Object projects(@RequestParam(defaultValue = "0") int offset, HttpServletRequest request) {
    actors.require(request);
    actors.requireLocal(request);
    if (offset < 0)
      throw dev.blot.application.workspace.WorkspaceFailure.invalid("Неверная страница");
    return store.transact(tx -> tx.unclaimedProjects(offset, 100));
  }
}
