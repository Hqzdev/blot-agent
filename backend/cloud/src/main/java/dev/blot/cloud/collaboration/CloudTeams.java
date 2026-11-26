package dev.blot.cloud.collaboration;

import dev.blot.application.ports.JsonCodec;
import dev.blot.cloud.CloudFailure;
import dev.blot.cloud.identity.*;
import dev.blot.cloud.storage.*;
import java.time.*;
import java.util.*;

/** Team membership is account authority. External channel messages never confer an admin role. */
public final class CloudTeams {
  public record Team(UUID id, String name, String role) {}

  public record Member(UUID accountID, String name, String email, String role) {}

  public record Invite(String token, Instant expiresAt) {}

  public record BotConfiguration(
      String name,
      UUID agentID,
      UUID executorDeviceID,
      String instructions,
      List<String> allowedTools,
      List<Channel> channels,
      boolean enabled) {}

  public record Channel(
      String connectionID, String provider, String workspace, String channel, String trigger) {}

  public record Bot(
      UUID id, UUID teamID, UUID ownerID, int version, BotConfiguration configuration) {}

  private final CloudDatabase database;
  private final CloudTokens tokens;
  private final JsonCodec json;
  private final Clock clock;

  public CloudTeams(CloudDatabase database, CloudTokens tokens, JsonCodec json, Clock clock) {
    this.database = database;
    this.tokens = tokens;
    this.json = json;
    this.clock = clock;
  }

  public List<Team> list(CloudActor actor) {
    return database.transact(
        tx ->
            tx.query(
                "SELECT t.id,t.name,m.role FROM collaboration_teams t JOIN collaboration_members m ON m.team_id=t.id WHERE m.account_id=? ORDER BY t.created_at",
                r -> new Team(UUID.fromString(r.getString(1)), r.getString(2), r.getString(3)),
                actor.ownerID()));
  }

  public Team create(CloudActor actor, String name) {
    text(name, 200);
    UUID id = UUID.randomUUID();
    return database.transact(
        tx -> {
          if (tx.one(
                      "SELECT COUNT(*) FROM collaboration_teams WHERE owner_id=?",
                      r -> r.getInt(1),
                      actor.ownerID())
                  .orElse(0)
              >= 20) throw new CloudFailure(409, "team_limit");
          tx.execute(
              "INSERT INTO collaboration_teams VALUES(?,?,?,?)",
              id,
              actor.ownerID(),
              name,
              clock.instant());
          tx.execute(
              "INSERT INTO collaboration_members VALUES(?,?,?)", id, actor.ownerID(), "owner");
          return new Team(id, name, "owner");
        });
  }

  public List<Member> members(CloudActor actor, UUID team) {
    return database.transact(
        tx -> {
          require(tx, actor, team, false);
          return tx.query(
              "SELECT a.id,a.name,a.email,m.role FROM collaboration_members m JOIN accounts a ON a.id=m.account_id WHERE m.team_id=?",
              r ->
                  new Member(
                      UUID.fromString(r.getString(1)),
                      r.getString(2),
                      r.getString(3),
                      r.getString(4)),
              team);
        });
  }

  public Invite invite(CloudActor actor, UUID team, String email, String role) {
    String normalized = CloudTokens.email(email);
    if (!Set.of("member", "admin").contains(role)) throw new CloudFailure(400, "invalid_role");
    String token = tokens.random();
    Instant expires = clock.instant().plus(Duration.ofDays(7));
    return database.transact(
        tx -> {
          require(tx, actor, team, true);
          tx.execute(
              "DELETE FROM collaboration_invites WHERE expires<? OR (team_id=? AND email=?)",
              clock.instant(),
              team,
              normalized);
          tx.execute(
              "INSERT INTO collaboration_invites VALUES(?,?,?,?,?)",
              tokens.digest(token),
              team,
              normalized,
              role,
              expires);
          return new Invite(token, expires);
        });
  }

  public void accept(CloudActor actor, String token) {
    text(token, 128);
    database.transact(
        tx -> {
          record Pending(String team, String email, String role) {}
          Pending pending =
              tx.one(
                      "SELECT team_id,email,role FROM collaboration_invites WHERE token_hash=? AND expires>?",
                      r -> new Pending(r.getString(1), r.getString(2), r.getString(3)),
                      tokens.digest(token),
                      clock.instant())
                  .orElseThrow(() -> new CloudFailure(404, "invite_unavailable"));
          String email =
              tx.one(
                      "SELECT email FROM accounts WHERE id=? AND verified=1",
                      r -> r.getString(1),
                      actor.ownerID())
                  .orElseThrow(() -> new CloudFailure(403, "verified_account_required"));
          if (!email.equals(pending.email)) throw new CloudFailure(403, "invite_wrong_account");
          tx.execute(
              "INSERT INTO collaboration_members VALUES(?,?,?) ON CONFLICT(team_id,account_id) DO NOTHING",
              pending.team,
              actor.ownerID(),
              pending.role);
          tx.execute("DELETE FROM collaboration_invites WHERE token_hash=?", tokens.digest(token));
          return null;
        });
  }

  public void removeMember(CloudActor actor, UUID team, UUID account) {
    database.transact(
        tx -> {
          String role = require(tx, actor, team, true);
          String target =
              tx.one(
                      "SELECT role FROM collaboration_members WHERE team_id=? AND account_id=?",
                      r -> r.getString(1),
                      team,
                      account)
                  .orElseThrow(() -> new CloudFailure(404, "member_unavailable"));
          if (target.equals("owner") || target.equals("admin") && !role.equals("owner"))
            throw new CloudFailure(403, "owner_required");
          tx.execute(
              "DELETE FROM collaboration_members WHERE team_id=? AND account_id=?", team, account);
          tx.execute(
              "DELETE FROM collaboration_bots WHERE team_id=? AND owner_id=?", team, account);
          return null;
        });
  }

  public List<Bot> bots(CloudActor actor, UUID team) {
    return database.transact(
        tx -> {
          require(tx, actor, team, false);
          return tx.query(
              "SELECT id,owner_id,version,configuration FROM collaboration_bots WHERE team_id=?",
              r ->
                  new Bot(
                      UUID.fromString(r.getString(1)),
                      team,
                      UUID.fromString(r.getString(2)),
                      r.getInt(3),
                      json.read(r.getString(4), BotConfiguration.class)),
              team);
        });
  }

  public Bot saveBot(
      CloudActor actor, UUID team, UUID id, int version, BotConfiguration configuration) {
    validate(configuration);
    String encoded = json.write(configuration);
    return database.transact(
        tx -> {
          require(tx, actor, team, true);
          Bot old =
              tx.one(
                      "SELECT owner_id,version FROM collaboration_bots WHERE id=? AND team_id=?",
                      r -> new Bot(id, team, UUID.fromString(r.getString(1)), r.getInt(2), null),
                      id,
                      team)
                  .orElse(null);
          if ((old == null ? 0 : old.version) != version)
            throw new CloudFailure(409, "version_conflict");
          if (old != null && !old.ownerID.equals(actor.ownerID()))
            throw new CloudFailure(403, "bot_owner_required");
          boolean device =
              tx.one(
                      "SELECT id FROM devices WHERE id=? AND owner_id=? AND kind='DESKTOP' AND revoked=0",
                      r -> r.getString(1),
                      configuration.executorDeviceID,
                      actor.ownerID())
                  .isPresent();
          if (!device) throw new CloudFailure(400, "desktop_required");
          Bot saved = new Bot(id, team, actor.ownerID(), version + 1, configuration);
          tx.execute(
              "INSERT INTO collaboration_bots VALUES(?,?,?,?,?,?) ON CONFLICT(id) DO UPDATE SET version=excluded.version,configuration=excluded.configuration,updated_at=excluded.updated_at",
              id,
              team,
              actor.ownerID(),
              version + 1,
              encoded,
              clock.instant());
          return saved;
        });
  }

  public void deleteBot(CloudActor actor, UUID team, UUID id, int version) {
    database.transact(
        tx -> {
          require(tx, actor, team, true);
          if (tx.execute(
                  "DELETE FROM collaboration_bots WHERE id=? AND team_id=? AND version=?",
                  id,
                  team,
                  version)
              != 1) throw new CloudFailure(409, "version_conflict");
          return null;
        });
  }

  private static void validate(BotConfiguration c) {
    if (c == null
        || c.agentID == null
        || c.executorDeviceID == null
        || c.allowedTools == null
        || c.channels == null) throw new CloudFailure(400, "invalid_bot");
    text(c.name, 200);
    text(c.instructions, 16000);
    if (c.allowedTools.size() > 100
        || c.channels.size() > 30
        || new HashSet<>(c.allowedTools).size() != c.allowedTools.size())
      throw new CloudFailure(400, "invalid_bot");
    c.allowedTools.forEach(t -> text(t, 200));
    for (Channel channel : c.channels) {
      if (channel == null || !Set.of("slack", "teams").contains(channel.provider))
        throw new CloudFailure(400, "invalid_channel");
      try {
        UUID.fromString(channel.connectionID);
      } catch (RuntimeException failure) {
        throw new CloudFailure(400, "invalid_connection");
      }
      text(channel.workspace, 400);
      text(channel.channel, 400);
      text(channel.trigger, 100);
    }
  }

  private static String require(CloudTransaction tx, CloudActor actor, UUID team, boolean admin) {
    String role =
        tx.one(
                "SELECT role FROM collaboration_members WHERE team_id=? AND account_id=?",
                r -> r.getString(1),
                team,
                actor.ownerID())
            .orElseThrow(() -> new CloudFailure(403, "team_access_denied"));
    if (admin && !Set.of("owner", "admin").contains(role))
      throw new CloudFailure(403, "team_admin_required");
    return role;
  }

  private static void text(String text, int maximum) {
    if (text == null || text.isBlank() || text.length() > maximum || text.indexOf('\0') >= 0)
      throw new CloudFailure(400, "invalid_field");
  }
}
