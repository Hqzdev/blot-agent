package dev.blot.api.workspace.security;

import dev.blot.api.workspace.transport.RequestActor;
import dev.blot.application.workspace.providers.ProviderCertificateService;
import jakarta.servlet.http.HttpServletRequest;
import org.springframework.web.bind.annotation.*;

@RestController
public final class ProviderCertificateController {
  private final RequestActor actors;
  private final ProviderCertificateService certificates;

  public ProviderCertificateController(
      RequestActor actors, ProviderCertificateService certificates) {
    this.actors = actors;
    this.certificates = certificates;
  }

  record Certificate(String pem) {}

  @GetMapping("/v2/provider/certificate")
  public Object current(HttpServletRequest request) {
    return certificates.current(actors.require(request));
  }

  @PostMapping("/v2/provider/certificate/inspect")
  public Object inspect(@RequestBody Certificate body, HttpServletRequest request) {
    return certificates.inspect(actors.require(request), body.pem());
  }

  @PutMapping("/v2/provider/certificate")
  public Object save(@RequestBody Certificate body, HttpServletRequest request) {
    return certificates.save(actors.require(request), body.pem());
  }
}
