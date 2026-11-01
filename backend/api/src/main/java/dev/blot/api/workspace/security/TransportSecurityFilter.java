package dev.blot.api.workspace.security;

import jakarta.servlet.*;
import jakarta.servlet.http.*;
import java.io.IOException;
import java.net.InetAddress;
import java.util.Set;
import org.springframework.core.Ordered;
import org.springframework.core.annotation.Order;
import org.springframework.stereotype.Component;
import org.springframework.web.filter.OncePerRequestFilter;

@Component
@Order(Ordered.HIGHEST_PRECEDENCE)
public final class TransportSecurityFilter extends OncePerRequestFilter {
  @Override
  protected void doFilterInternal(
      HttpServletRequest request, HttpServletResponse response, FilterChain chain)
      throws ServletException, IOException {
    response.setHeader("Cache-Control", "no-store");
    response.setHeader("X-Content-Type-Options", "nosniff");
    if (!request.isSecure()
        && !InetAddress.getByName(request.getRemoteAddr()).isLoopbackAddress()) {
      reject(response, 403, "tls_required", "Используйте защищённое подключение");
      return;
    }
    if (Set.of("POST", "PUT", "PATCH").contains(request.getMethod())) {
      long size = request.getContentLengthLong();
      if (size < 0) {
        reject(response, 411, "length_required", "Укажите длину JSON-команды");
        return;
      }
      if (size > 2_097_152) {
        reject(response, 413, "payload_too_large", "Команда превышает лимит 2 MiB");
        return;
      }
    }
    chain.doFilter(request, response);
  }

  private void reject(HttpServletResponse response, int status, String code, String message)
      throws IOException {
    response.setStatus(status);
    response.setContentType("application/json");
    response.setCharacterEncoding("UTF-8");
    response
        .getWriter()
        .write("{\"code\":\"" + code + "\",\"message\":\"" + message + "\",\"details\":{}}");
  }
}
