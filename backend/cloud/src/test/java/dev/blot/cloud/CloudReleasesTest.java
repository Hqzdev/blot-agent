package dev.blot.cloud;

import static org.junit.jupiter.api.Assertions.*;
import dev.blot.cloud.web.CloudReleasesController;
import dev.blot.infrastructure.workspace.JacksonCodec;
import java.util.Map;
import org.junit.jupiter.api.Test;

final class CloudReleasesTest {
  @Test void noReleaseIsAdvertisedUntilPublished() {
    var controller=new CloudReleasesController(new CloudSecrets(Map.of()),new JacksonCodec());
    assertEquals(204,controller.latest("macos","stable").getStatusCode().value());
    assertThrows(CloudFailure.class,() -> controller.latest("android","stable"));
  }
  @Test void configuredReleaseMustHaveAValidHTTPSDownload() {
    String metadata="{\"version\":\"1.2.3\",\"build\":123,\"minimumOS\":\"26.0\",\"downloadURL\":\"https://example.org/Blot.dmg\",\"notes\":\"Release notes\",\"publishedAt\":\"2026-11-18T00:00:00Z\"}";
    var valid=new CloudReleasesController(new CloudSecrets(Map.of("BLOT_RELEASE_MACOS_STABLE_JSON",metadata)),new JacksonCodec());
    assertEquals("1.2.3",valid.latest("macos","stable").getBody().version());
    var invalid=new CloudReleasesController(new CloudSecrets(Map.of("BLOT_RELEASE_MACOS_STABLE_JSON",metadata.replace("https://example.org/Blot.dmg","javascript:alert(1)"))),new JacksonCodec());
    assertThrows(CloudFailure.class,() -> invalid.latest("macos","stable"));
  }
}
