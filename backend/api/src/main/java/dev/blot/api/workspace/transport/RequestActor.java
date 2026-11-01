package dev.blot.api.workspace.transport;

import dev.blot.api.workspace.security.TlsConfiguration;
import dev.blot.application.workspace.*;
import dev.blot.application.workspace.WorkspaceFailure;
import dev.blot.application.workspace.conversation.SessionService;
import dev.blot.core.workspace.identity.Actor;
import jakarta.servlet.http.HttpServletRequest;
import java.net.InetAddress;
import org.springframework.stereotype.Component;

@Component
public final class RequestActor {
  private final SessionService sessions;
  private final org.springframework.beans.factory.ObjectProvider<TlsConfiguration.BleConnector> ble;

  public RequestActor(
      SessionService sessions,
      org.springframework.beans.factory.ObjectProvider<TlsConfiguration.BleConnector> ble) {
    this.ble = ble;
    this.sessions = sessions;
  }

  public Actor require(HttpServletRequest request) {
    return sessions.authenticate(token(request), local(request));
  }

  public String token(HttpServletRequest request) {
    String value = request.getHeader("Authorization");
    if (value == null || !value.startsWith("Bearer "))
      throw new WorkspaceFailure(401, "unauthenticated", "Войдите в аккаунт");
    return value.substring(7);
  }

  public boolean local(HttpServletRequest request) {
    try {
      return InetAddress.getByName(request.getRemoteAddr()).isLoopbackAddress()
          && (ble.getIfAvailable() == null
              || request.getLocalPort() != ble.getIfAvailable().port());
    } catch (java.net.UnknownHostException e) {
      return false;
    }
  }

  public void requireLocal(HttpServletRequest request) {
    if (!local(request))
      throw new WorkspaceFailure(403, "local_required", "Действие доступно только на Mac");
  }
}
