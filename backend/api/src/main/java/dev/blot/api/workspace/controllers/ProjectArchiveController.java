package dev.blot.api.workspace.controllers;

import dev.blot.api.workspace.transport.RequestActor;
import dev.blot.application.ports.*;
import dev.blot.application.ports.ArtifactStore;
import dev.blot.application.ports.JsonCodec;
import dev.blot.application.workspace.*;
import dev.blot.application.workspace.data.DataLifecycleService;
import dev.blot.core.workspace.*;
import dev.blot.core.workspace.Entity;
import dev.blot.core.workspace.artifact.ArtifactData;
import jakarta.servlet.http.HttpServletRequest;
import java.nio.charset.StandardCharsets;
import java.util.*;
import java.util.zip.*;
import org.springframework.http.*;
import org.springframework.web.bind.annotation.*;
import org.springframework.web.servlet.mvc.method.annotation.StreamingResponseBody;

/** Манифест и фактические артефакты передаются частями, без большого буфера в памяти. */
@RestController
public final class ProjectArchiveController {
  private final DataLifecycleService lifecycle;
  private final RequestActor actors;
  private final ArtifactStore artifacts;
  private final JsonCodec json;

  public ProjectArchiveController(
      DataLifecycleService lifecycle,
      RequestActor actors,
      ArtifactStore artifacts,
      JsonCodec json) {
    this.lifecycle = lifecycle;
    this.actors = actors;
    this.artifacts = artifacts;
    this.json = json;
  }

  @GetMapping(value = "/v2/projects/{id}/export.zip", produces = "application/zip")
  public ResponseEntity<StreamingResponseBody> export(
      @PathVariable UUID id, HttpServletRequest request) {
    var snapshot = lifecycle.exportProject(actors.require(request), id);
    var metadata = (List<?>) snapshot.getOrDefault("ARTIFACT", List.of());
    StreamingResponseBody body =
        output -> {
          try (var archive = new ZipOutputStream(output, StandardCharsets.UTF_8)) {
            archive.putNextEntry(new ZipEntry("manifest.json"));
            archive.write(json.write(snapshot).getBytes(StandardCharsets.UTF_8));
            archive.closeEntry();
            var included = new HashSet<String>();
            for (Object value : metadata) {
              var entity = (Entity<?>) value;
              var artifact = json.convert(entity.data(), ArtifactData.class);
              if (!included.add(artifact.hash())) continue;
              archive.putNextEntry(new ZipEntry("artifacts/" + artifact.hash()));
              for (int offset = 0; ; offset += 1_048_576) {
                byte[] part =
                    artifacts.read(artifact.relativePath(), artifact.hash(), offset, 1_048_576);
                archive.write(part);
                if (part.length < 1_048_576) break;
              }
              archive.closeEntry();
            }
          }
        };
    return ResponseEntity.ok()
        .header(
            HttpHeaders.CONTENT_DISPOSITION, "attachment; filename=\"blot-project-" + id + ".zip\"")
        .body(body);
  }
}
