package dev.blot.cloud.collaboration;

import dev.blot.application.ports.JsonCodec;
import dev.blot.cloud.CloudFailure;
import dev.blot.cloud.identity.*;
import dev.blot.cloud.storage.CloudDatabase;
import java.time.*;
import java.util.*;

/** An explicit immutable publication, with expiring, revocable bearer links. */
public final class CloudPublishedContent {
  public record Publication(
      UUID id, String kind, String title, String payload, Instant expiresAt) {}

  public record Link(UUID id, String token, Instant expiresAt) {}

  public record Summary(UUID id, String kind, String title, Instant expiresAt, boolean revoked) {}

  private final CloudDatabase database;
  private final CloudTokens tokens;
  private final Clock clock;
  private final JsonCodec json;

  public CloudPublishedContent(
      CloudDatabase database, CloudTokens tokens, Clock clock, JsonCodec json) {
    this.database = database;
    this.tokens = tokens;
    this.clock = clock;
    this.json = json;
  }

  public Link publish(CloudActor actor, String kind, String title, String payload, int days) {
    if (kind == null
        || !Set.of("page", "skill").contains(kind)
        || title == null
        || title.isBlank()
        || title.length() > 800
        || payload == null
        || payload.getBytes(java.nio.charset.StandardCharsets.UTF_8).length > 128000
        || days < 1
        || days > 90) throw new CloudFailure(400, "invalid_publication");
    try {
      Map<?, ?> value = json.read(payload, Map.class);
      if (value == null
          || !(kind.equals("page") ? "blot.page.v1" : "blot.skill.v1").equals(value.get("format")))
        throw new IllegalArgumentException();
      if (kind.equals("page") && !(value.get("blocks") instanceof List<?>))
        throw new IllegalArgumentException();
      if (kind.equals("skill")
          && (!(value.get("instructions") instanceof String)
              || !(value.get("tools") instanceof List<?>))) throw new IllegalArgumentException();
    } catch (RuntimeException invalid) {
      throw new CloudFailure(400, "invalid_publication_payload");
    }
    UUID id = UUID.randomUUID();
    String token = tokens.random();
    Instant expires = clock.instant().plus(Duration.ofDays(days));
    return database.transact(
        tx -> {
          if (tx.one(
                      "SELECT COUNT(*) FROM published_content WHERE owner_id=? AND revoked=0 AND expires>?",
                      r -> r.getInt(1),
                      actor.ownerID(),
                      clock.instant())
                  .orElse(0)
              >= 100) throw new CloudFailure(409, "publication_limit");
          tx.execute(
              "INSERT INTO published_content(id,owner_id,token_hash,kind,title,payload,expires) VALUES(?,?,?,?,?,?,?)",
              id,
              actor.ownerID(),
              tokens.digest(token),
              kind,
              title,
              payload,
              expires);
          return new Link(id, token, expires);
        });
  }

  public Publication read(String token) {
    if (token == null || !token.matches("[A-Za-z0-9_-]{43}"))
      throw new CloudFailure(404, "publication_unavailable");
    return database.transact(
        tx ->
            tx.one(
                    "SELECT id,kind,title,payload,expires FROM published_content WHERE token_hash=? AND revoked=0 AND expires>?",
                    r ->
                        new Publication(
                            UUID.fromString(r.getString(1)),
                            r.getString(2),
                            r.getString(3),
                            r.getString(4),
                            Instant.ofEpochMilli(r.getLong(5))),
                    tokens.digest(token),
                    clock.instant())
                .orElseThrow(() -> new CloudFailure(404, "publication_unavailable")));
  }

  public List<Summary> list(CloudActor actor) {
    return database.transact(
        tx ->
            tx.query(
                "SELECT id,kind,title,expires,revoked FROM published_content WHERE owner_id=? ORDER BY expires DESC LIMIT 200",
                r ->
                    new Summary(
                        UUID.fromString(r.getString(1)),
                        r.getString(2),
                        r.getString(3),
                        Instant.ofEpochMilli(r.getLong(4)),
                        r.getBoolean(5)),
                actor.ownerID()));
  }

  public void revoke(CloudActor actor, UUID id) {
    database.transact(
        tx -> {
          if (tx.execute(
                  "UPDATE published_content SET revoked=1 WHERE id=? AND owner_id=?",
                  id,
                  actor.ownerID())
              != 1) throw new CloudFailure(404, "publication_unavailable");
          return null;
        });
  }
}
