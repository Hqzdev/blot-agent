package dev.blot.cloud.relay;

import dev.blot.cloud.CloudFailure;
import dev.blot.cloud.identity.*;
import dev.blot.cloud.storage.*;
import java.time.*;
import java.util.*;

public final class CloudEncryptedBlobs {
  public record Chunk(UUID blobID, int index, int count, byte[] ciphertext) {
    public Chunk {
      ciphertext = ciphertext == null ? null : ciphertext.clone();
    }

    @Override
    public byte[] ciphertext() {
      return ciphertext == null ? null : ciphertext.clone();
    }
  }

  private final CloudDatabase database;
  private final CloudTokens tokens;
  private final Clock clock;

  public CloudEncryptedBlobs(CloudDatabase database, CloudTokens tokens, Clock clock) {
    this.database = database;
    this.tokens = tokens;
    this.clock = clock;
  }

  public void put(CloudActor actor, Chunk chunk) {
    if (chunk == null
        || chunk.blobID() == null
        || chunk.index() < 0
        || chunk.count() < 1
        || chunk.count() > 512
        || chunk.index() >= chunk.count()
        || chunk.ciphertext() == null
        || chunk.ciphertext().length == 0
        || chunk.ciphertext().length > 262_144) throw new CloudFailure(400, "invalid_blob_chunk");
    String digest = tokens.digest(chunk.ciphertext());
    database.transact(
        tx -> {
          CloudDevices.requireActive(tx, actor);
          var old =
              tx.one(
                  "SELECT digest, chunk_count FROM encrypted_blobs WHERE workspace_id = ? AND blob_id = ? AND chunk_index = ?",
                  r -> new String[] {r.getString(1), r.getString(2)},
                  actor.workspaceID(),
                  chunk.blobID(),
                  chunk.index());
          if (old.isPresent()) {
            if (!old.get()[0].equals(digest) || Integer.parseInt(old.get()[1]) != chunk.count())
              throw new CloudFailure(409, "blob_conflict");
            tx.execute(
                "UPDATE encrypted_blobs SET created_at = ? WHERE workspace_id = ? AND blob_id = ? AND chunk_index = ?",
                clock.instant(),
                actor.workspaceID(),
                chunk.blobID(),
                chunk.index());
            return null;
          }
          var count =
              tx.one(
                  "SELECT chunk_count FROM encrypted_blobs WHERE workspace_id = ? AND blob_id = ? LIMIT 1",
                  r -> r.getInt(1),
                  actor.workspaceID(),
                  chunk.blobID());
          if (count.isPresent() && count.get() != chunk.count())
            throw new CloudFailure(409, "blob_conflict");
          long total =
              tx.one(
                      "SELECT COALESCE(SUM(length(ciphertext)), 0) FROM encrypted_blobs WHERE workspace_id = ?",
                      r -> r.getLong(1),
                      actor.workspaceID())
                  .orElse(0L);
          if (total > 536_870_912L - chunk.ciphertext().length)
            throw new CloudFailure(429, "blob_quota");
          tx.execute(
              "INSERT INTO encrypted_blobs(workspace_id, blob_id, chunk_index, chunk_count, creator_id, ciphertext, digest, created_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?)",
              actor.workspaceID(),
              chunk.blobID(),
              chunk.index(),
              chunk.count(),
              actor.deviceID(),
              chunk.ciphertext(),
              digest,
              clock.instant());
          return null;
        });
  }

  public Chunk get(CloudActor actor, UUID blob, int index) {
    return database.transact(
        tx -> {
          CloudDevices.requireActive(tx, actor);
          return tx.one(
                  "SELECT chunk_count, ciphertext FROM encrypted_blobs WHERE workspace_id = ? AND blob_id = ? AND chunk_index = ? AND created_at >= ?",
                  r -> new Chunk(blob, index, r.getInt(1), r.getBytes(2)),
                  actor.workspaceID(),
                  blob,
                  index,
                  clock.instant().minus(Duration.ofDays(30)))
              .orElseThrow(() -> new CloudFailure(404, "blob_unavailable"));
        });
  }

  public void purgeExpired() {
    database.transact(
        tx -> {
          tx.execute(
              "DELETE FROM encrypted_blobs WHERE created_at < ?",
              clock.instant().minus(Duration.ofDays(30)));
          return null;
        });
  }
}
