package dev.blot.api.workspace.transport;

import dev.blot.application.workspace.WorkspaceFailure;
import dev.blot.core.workspace.Entity;
import java.nio.charset.StandardCharsets;
import java.time.Instant;
import java.util.*;

/** Позиция страницы остаётся действительной после удаления предыдущей записи. */
public record RecordCursor(Instant createdAt, UUID id) {
  public static String encode(Entity<?> entity) {
    String value = entity.createdAt() + "\n" + entity.id();
    return Base64.getUrlEncoder()
        .withoutPadding()
        .encodeToString(value.getBytes(StandardCharsets.UTF_8));
  }

  public static RecordCursor decode(String value) {
    try {
      if (value.length() > 256) throw new IllegalArgumentException();
      String[] parts =
          new String(Base64.getUrlDecoder().decode(value), StandardCharsets.UTF_8).split("\n", -1);
      if (parts.length != 2) throw new IllegalArgumentException();
      return new RecordCursor(Instant.parse(parts[0]), UUID.fromString(parts[1]));
    } catch (RuntimeException failure) {
      throw WorkspaceFailure.invalid("Неверный курсор страницы");
    }
  }
}
