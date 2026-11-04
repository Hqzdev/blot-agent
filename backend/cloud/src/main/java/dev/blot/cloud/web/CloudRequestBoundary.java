package dev.blot.cloud.web;

import jakarta.servlet.*;
import jakarta.servlet.http.*;
import java.io.*;
import org.springframework.stereotype.Component;
import org.springframework.web.filter.OncePerRequestFilter;

/** No request bodies or credentials are logged. Bound even chunked JSON before deserialization. */
@Component
public final class CloudRequestBoundary extends OncePerRequestFilter {
  @Override
  protected void doFilterInternal(
      HttpServletRequest request, HttpServletResponse response, FilterChain chain)
      throws ServletException, IOException {
    response.setHeader("Cache-Control", "no-store");
    response.setHeader("X-Content-Type-Options", "nosniff");
    final int limit = 1_048_576;
    if (request.getContentLengthLong() > limit) {
      tooLarge(response);
      return;
    }
    byte[] body = request.getInputStream().readNBytes(limit + 1);
    if (body.length > limit) {
      tooLarge(response);
      return;
    }
    chain.doFilter(
        new HttpServletRequestWrapper(request) {
          @Override
          public ServletInputStream getInputStream() {
            var input = new ByteArrayInputStream(body);
            return new ServletInputStream() {
              public int read() {
                return input.read();
              }

              public int read(byte[] bytes, int offset, int length) {
                return input.read(bytes, offset, length);
              }

              public boolean isFinished() {
                return input.available() == 0;
              }

              public boolean isReady() {
                return true;
              }

              public void setReadListener(ReadListener listener) {
                throw new IllegalStateException("Asynchronous request body reading is not enabled");
              }
            };
          }

          @Override
          public BufferedReader getReader() {
            return new BufferedReader(
                new InputStreamReader(getInputStream(), java.nio.charset.StandardCharsets.UTF_8));
          }

          @Override
          public int getContentLength() {
            return body.length;
          }

          @Override
          public long getContentLengthLong() {
            return body.length;
          }
        },
        response);
  }

  private void tooLarge(HttpServletResponse response) throws IOException {
    response.setStatus(413);
    response.setContentType("application/json");
    response.getWriter().write("{\"code\":\"request_too_large\"}");
  }
}
