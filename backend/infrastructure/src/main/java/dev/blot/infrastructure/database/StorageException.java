package dev.blot.infrastructure.database;

public final class StorageException extends RuntimeException {
  public enum Kind {
    CONSTRAINT,
    CORRUPT_DATA,
    CONNECTION
  }

  private final Kind kind;

  public StorageException(Kind kind, Throwable cause) {
    super("Storage failure: " + kind, cause);
    this.kind = kind;
  }

  public Kind kind() {
    return kind;
  }
}
