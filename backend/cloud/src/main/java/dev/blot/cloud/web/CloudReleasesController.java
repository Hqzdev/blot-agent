package dev.blot.cloud.web;

import dev.blot.application.ports.JsonCodec;
import dev.blot.cloud.*;
import java.net.URI;
import java.time.Instant;
import java.util.Set;
import org.springframework.http.*;
import org.springframework.web.bind.annotation.*;

/**
 * Only release metadata explicitly published by the deployer is advertised as an available update.
 */
@RestController
public final class CloudReleasesController {
  public record Release(
      String version,
      int build,
      String minimumOS,
      String downloadURL,
      String notes,
      Instant publishedAt) {}

  private final CloudSecrets secrets;
  private final JsonCodec json;

  public CloudReleasesController(CloudSecrets secrets, JsonCodec json) {
    this.secrets = secrets;
    this.json = json;
  }

  @GetMapping("/v1/releases/latest")
  public ResponseEntity<Release> latest(
      @RequestParam String platform, @RequestParam String channel) {
    if (!Set.of("macos", "ios").contains(platform) || !Set.of("stable", "beta").contains(channel))
      throw new CloudFailure(400, "invalid_release_channel");
    var metadata = secrets.get("release." + platform + "." + channel + ".json");
    if (metadata.isEmpty())
      return ResponseEntity.noContent().header("Cache-Control", "no-store").build();
    try {
      Release release = json.read(metadata.get(), Release.class);
      URI uri = URI.create(release.downloadURL);
      if (!release.version.matches("[0-9]+(\\.[0-9]+){1,3}")
          || release.build < 1
          || !"https".equals(uri.getScheme())
          || uri.getHost() == null
          || uri.getUserInfo() != null
          || release.notes == null
          || release.notes.length() > 32000
          || release.minimumOS == null
          || release.publishedAt == null) throw new IllegalArgumentException();
      return ResponseEntity.ok().header("Cache-Control", "no-store").body(release);
    } catch (RuntimeException invalid) {
      throw new CloudFailure(503, "release_metadata_invalid");
    }
  }
}
