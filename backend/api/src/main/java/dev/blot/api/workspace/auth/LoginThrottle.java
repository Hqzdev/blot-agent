package dev.blot.api.workspace.auth;

import dev.blot.application.workspace.WorkspaceFailure;
import java.util.*;

/** Ограничение дорогостоящих проверок пароля до выполнения Argon2. */
final class LoginThrottle {
  private final Map<String, ArrayDeque<Long>> attempts = new HashMap<>();

  synchronized void check(String key) {
    long now = System.currentTimeMillis();
    attempts
        .entrySet()
        .removeIf(e -> e.getValue().isEmpty() || e.getValue().getLast() < now - 300000);
    if (attempts.size() > 10000)
      throw new WorkspaceFailure(429, "rate_limited", "Повторите позднее");
    var values = attempts.computeIfAbsent(key, k -> new ArrayDeque<>());
    while (!values.isEmpty() && values.getFirst() < now - 300000) values.removeFirst();
    if (values.size() >= 10)
      throw new WorkspaceFailure(429, "rate_limited", "Слишком много попыток входа");
    values.addLast(now);
  }
}
