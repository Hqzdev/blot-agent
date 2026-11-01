package dev.blot.infrastructure.workspace.execution;

import dev.blot.application.ports.JsonCodec;
import dev.blot.application.workspace.WorkspaceFailure;
import java.io.*;
import java.nio.charset.StandardCharsets;
import java.util.*;

/** Унаследованные anonymous pipes доступны только запущенному приложением backend. */
public final class MacPlatformBridge {
  private final JsonCodec json;
  private final boolean enabled;
  private final BufferedReader input;

  public MacPlatformBridge(JsonCodec json, boolean enabled) {
    this.json = json;
    this.enabled = enabled;
    input = new BufferedReader(new InputStreamReader(System.in, StandardCharsets.UTF_8));
  }

  public synchronized Object request(String method, Map<String, Object> arguments) {
    if (!enabled)
      throw new WorkspaceFailure(
          503, "platform_unavailable", "Запустите backend из приложения Mac");
    String id = UUID.randomUUID().toString();
    try {
      System.out.println(json.write(Map.of("id", id, "method", method, "arguments", arguments)));
      System.out.flush();
      String line = input.readLine();
      if (line == null || line.length() > 1_048_576) throw new IOException("Platform disconnected");
      Map<?, ?> response = json.read(line, Map.class);
      if (!id.equals(response.get("id")) || !Boolean.TRUE.equals(response.get("ok")))
        throw new IOException("Platform request failed");
      return response.get("value");
    } catch (IOException | IllegalArgumentException e) {
      throw new WorkspaceFailure(503, "platform_unavailable", "Системный компонент Mac недоступен");
    }
  }
}
