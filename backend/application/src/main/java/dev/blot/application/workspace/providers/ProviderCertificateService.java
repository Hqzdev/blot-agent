package dev.blot.application.workspace.providers;

import dev.blot.application.ports.*;
import dev.blot.application.ports.CertificateInspector;
import dev.blot.application.ports.SecretStore;
import dev.blot.application.workspace.WorkspaceFailure;
import dev.blot.core.workspace.identity.Actor;
import java.util.List;

public final class ProviderCertificateService {
  private final SecretStore secrets;
  private final CertificateInspector inspector;

  public ProviderCertificateService(SecretStore secrets, CertificateInspector inspector) {
    this.secrets = secrets;
    this.inspector = inspector;
  }

  public List<CertificateInspector.CertificateInfo> inspect(Actor actor, String pem) {
    requireLocal(actor);
    return inspector.inspect(pem);
  }

  public List<CertificateInspector.CertificateInfo> save(Actor actor, String pem) {
    var certificates = inspect(actor, pem);
    secrets.put("provider.ca." + actor.accountId(), pem);
    return certificates;
  }

  public List<CertificateInspector.CertificateInfo> current(Actor actor) {
    requireLocal(actor);
    return secrets
        .get("provider.ca." + actor.accountId())
        .map(inspector::inspect)
        .orElse(List.of());
  }

  private void requireLocal(Actor actor) {
    if (!actor.local() || actor.deviceId() != null)
      throw new WorkspaceFailure(403, "local_required", "Выберите сертификат на Mac");
  }
}
