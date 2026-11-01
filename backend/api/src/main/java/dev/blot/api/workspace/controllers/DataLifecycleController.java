package dev.blot.api.workspace.controllers;

import dev.blot.api.workspace.transport.RequestActor;
import dev.blot.application.ports.*;
import dev.blot.application.ports.ArtifactStore;
import dev.blot.application.ports.WorkspaceStore;
import dev.blot.application.workspace.*;
import dev.blot.application.workspace.Records;
import dev.blot.application.workspace.data.DataLifecycleService;
import dev.blot.core.workspace.*;
import dev.blot.core.workspace.EntityKind;
import dev.blot.core.workspace.artifact.ArtifactData;
import dev.blot.core.workspace.identity.PairingData;
import jakarta.servlet.http.HttpServletRequest;
import java.util.*;
import org.springframework.web.bind.annotation.*;

@RestController
public final class DataLifecycleController {
  private final DataLifecycleService service;
  private final RequestActor actor;
  private final WorkspaceStore store;
  private final ArtifactStore artifacts;

  public DataLifecycleController(
      DataLifecycleService service,
      RequestActor actor,
      WorkspaceStore store,
      ArtifactStore artifacts) {
    this.service = service;
    this.actor = actor;
    this.store = store;
    this.artifacts = artifacts;
  }

  @GetMapping("/v2/projects/{id}/export")
  public Object export(@PathVariable UUID id, HttpServletRequest req) {
    return service.exportProject(actor.require(req), id);
  }

  @GetMapping("/v2/diagnostics")
  public Object diagnostics(HttpServletRequest req) {
    return service.diagnostics(actor.require(req));
  }

  @GetMapping(value = "/v2/artifacts/{id}/content", produces = "application/octet-stream")
  public byte[] content(
      @PathVariable UUID id,
      @RequestParam(defaultValue = "0") int offset,
      @RequestParam(defaultValue = "262144") int length,
      HttpServletRequest req) {
    var a = actor.require(req);
    var e =
        store.transact(
            tx -> Records.require(tx, EntityKind.ARTIFACT, a.accountId(), id, ArtifactData.class));
    return artifacts.read(e.data().relativePath(), e.data().hash(), offset, length);
  }

  @GetMapping("/v2/devices/pairings")
  public Object pairings(HttpServletRequest req) {
    var a = actor.require(req);
    actor.requireLocal(req);
    return store.transact(
        tx ->
            tx.list(EntityKind.PAIRING, a.accountId(), null, null, PairingData.class, 100).stream()
                .map(
                    e -> {
                      var d = e.data();
                      var value = new LinkedHashMap<String, Object>();
                      value.put("id", e.id());
                      value.put("version", e.version());
                      value.put("expiresAt", d.expiresAt());
                      value.put("deviceName", d.deviceName());
                      value.put("platform", d.platform());
                      value.put("deviceId", d.deviceId());
                      value.put("approved", d.approved());
                      value.put("claimed", d.claimed());
                      return value;
                    })
                .toList());
  }
}
