package dev.blot.core.v3;

import java.util.Objects;
import java.util.UUID;

public record MessageMention(UUID agentId, long startUTF16, long lengthUTF16) {
  public MessageMention {
    Objects.requireNonNull(agentId, "agentId");
    if (startUTF16 < 0) throw new IllegalArgumentException("startUTF16 must be nonnegative");
    if (lengthUTF16 < 0) throw new IllegalArgumentException("lengthUTF16 must be nonnegative");
  }
}
