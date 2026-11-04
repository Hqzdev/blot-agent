package dev.blot.cloud.web;

import java.util.Map;
import org.springframework.web.bind.annotation.*;

@RestController
public final class CloudHealthController {
  @GetMapping("/v1/health")
  public Map<String, String> health() {
    return Map.of("status", "ok", "service", "blot-cloud", "protocol", "apple-v1");
  }
}
