package dev.blot.infrastructure.workspace.artifacts;

import dev.blot.application.ports.ArtifactStore;
import dev.blot.application.workspace.*;
import dev.blot.application.workspace.WorkspaceFailure;
import java.nio.*;
import java.nio.channels.FileChannel;
import java.nio.file.*;
import java.nio.file.attribute.FileTime;
import java.security.*;
import java.time.Instant;
import java.util.*;

public final class LocalArtifactStore implements ArtifactStore {
  private final Path root;

  public LocalArtifactStore(Path root) {
    this.root = root.toAbsolutePath().normalize();
    try {
      Files.createDirectories(this.root);
    } catch (java.io.IOException e) {
      throw new IllegalStateException(e);
    }
  }

  public synchronized Stored write(byte[] bytes) {
    String hash = hash(bytes);
    try {
      Path path = root.resolve(hash);
      if (!Files.exists(path)) {
        Path temp = Files.createTempFile(root, "artifact-", ".tmp");
        try {
          Files.write(temp, bytes);
          Files.move(temp, path, StandardCopyOption.ATOMIC_MOVE);
        } finally {
          Files.deleteIfExists(temp);
        }
      }
      // Недавно переиспользованный blob нельзя удалить по снимку ссылок, полученному до записи.
      Files.setLastModifiedTime(path, FileTime.from(Instant.now()));
      return new Stored(hash, hash);
    } catch (java.io.IOException e) {
      throw unavailable();
    }
  }

  public synchronized byte[] read(String path, String expected, int offset, int length) {
    if (!path.matches("[a-f0-9]{64}")
        || !path.equals(expected)
        || offset < 0
        || length < 1
        || length > 1_048_576) throw WorkspaceFailure.invalid("Неверный диапазон артефакта");
    try (var file =
        FileChannel.open(root.resolve(path), StandardOpenOption.READ, LinkOption.NOFOLLOW_LINKS)) {
      if (offset > file.size()) throw WorkspaceFailure.invalid("Диапазон вне артефакта");
      var digest = sha256();
      var buffer = ByteBuffer.allocate(65_536);
      while (file.read(buffer) != -1) {
        buffer.flip();
        digest.update(buffer);
        buffer.clear();
      }
      if (!HexFormat.of().formatHex(digest.digest()).equals(expected))
        throw new WorkspaceFailure(409, "artifact_corrupt", "Контрольная сумма не совпадает");
      file.position(offset);
      var part = ByteBuffer.allocate((int) Math.min(length, file.size() - offset));
      while (part.hasRemaining() && file.read(part) != -1) {}
      return Arrays.copyOf(part.array(), part.position());
    } catch (java.io.IOException e) {
      throw unavailable();
    }
  }

  public synchronized void removeUnused(Set<String> referenced, Instant olderThan) {
    try (var paths = Files.list(root)) {
      for (var path : paths.toList()) {
        String name = path.getFileName().toString();
        if (!name.matches("[a-f0-9]{64}") && !name.startsWith("artifact-")) continue;
        if (!referenced.contains(name)
            && Files.isRegularFile(path, LinkOption.NOFOLLOW_LINKS)
            && Files.getLastModifiedTime(path, LinkOption.NOFOLLOW_LINKS)
                .toInstant()
                .isBefore(olderThan)) Files.deleteIfExists(path);
      }
    } catch (java.io.IOException e) {
      throw unavailable();
    }
  }

  private static String hash(byte[] bytes) {
    return HexFormat.of().formatHex(sha256().digest(bytes));
  }

  private static MessageDigest sha256() {
    try {
      return MessageDigest.getInstance("SHA-256");
    } catch (NoSuchAlgorithmException e) {
      throw new IllegalStateException(e);
    }
  }

  private static WorkspaceFailure unavailable() {
    return new WorkspaceFailure(503, "artifact_unavailable", "Хранилище результатов недоступно");
  }
}
