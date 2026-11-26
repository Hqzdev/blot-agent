package dev.blot.cloud;

import static org.junit.jupiter.api.Assertions.*;

import dev.blot.cloud.collaboration.*;
import dev.blot.cloud.identity.*;
import dev.blot.cloud.storage.CloudDatabase;
import dev.blot.infrastructure.workspace.JacksonCodec;
import java.nio.file.Path;
import java.time.*;
import java.util.*;
import org.junit.jupiter.api.*;
import org.junit.jupiter.api.io.TempDir;

final class CloudCollaborationTest {
  @TempDir Path directory;
  private CloudDatabase database;
  private CloudTeams teams;
  private CloudPublishedContent content;
  private final Clock clock = Clock.fixed(Instant.parse("2026-11-18T00:00:00Z"), ZoneOffset.UTC);

  @BeforeEach
  void prepare() {
    database = new CloudDatabase(directory.resolve("cloud.sqlite"));
    CloudTokens tokens = new CloudTokens(new byte[32]);
    teams = new CloudTeams(database, tokens, new JacksonCodec(), clock);
    content = new CloudPublishedContent(database, tokens, clock, new JacksonCodec());
  }

  private CloudActor actor(String email) {
    UUID owner = UUID.randomUUID(), workspace = UUID.randomUUID(), device = UUID.randomUUID();
    database.transact(
        tx -> {
          tx.execute(
              "INSERT INTO accounts(id,email,password_hash,name,verified,created_at) VALUES(?,?,?,?,1,?)",
              owner,
              email,
              "unusable-test-hash",
              email,
              clock.instant());
          tx.execute("INSERT INTO workspaces(id,owner_id) VALUES(?,?)", workspace, owner);
          tx.execute(
              "INSERT INTO devices(id,owner_id,workspace_id,name,kind,signing_key,encryption_key,created_at) VALUES(?,?,?,?,?,?,?,?)",
              device,
              owner,
              workspace,
              "Mac",
              "DESKTOP",
              new byte[] {1},
              new byte[] {1},
              clock.instant());
          return null;
        });
    return new CloudActor(owner, workspace, UUID.randomUUID(), device, false);
  }

  @Test
  void invitationsBindVerifiedAccountAndMembersCannotEscalate() {
    var owner = actor("owner@example.org");
    var member = actor("member@example.org");
    var outsider = actor("other@example.org");
    var team = teams.create(owner, "Team");
    var invite = teams.invite(owner, team.id(), "member@example.org", "member");
    assertThrows(CloudFailure.class, () -> teams.accept(outsider, invite.token()));
    teams.accept(member, invite.token());
    assertEquals("member", teams.list(member).getFirst().role());
    assertThrows(
        CloudFailure.class, () -> teams.invite(member, team.id(), "other@example.org", "admin"));
    assertThrows(CloudFailure.class, () -> teams.accept(member, invite.token()));
    assertThrows(CloudFailure.class, () -> teams.removeMember(owner, team.id(), owner.ownerID()));
    teams.removeMember(owner, team.id(), member.ownerID());
    assertTrue(teams.list(member).isEmpty());
  }

  @Test
  void botUpdatesAreVersionedAndRequireOwnedPhysicalDesktop() {
    var owner = actor("owner@example.org");
    var other = actor("other@example.org");
    var team = teams.create(owner, "Team");
    UUID id = UUID.randomUUID();
    var config =
        new CloudTeams.BotConfiguration(
            "Bot",
            UUID.randomUUID(),
            owner.deviceID(),
            "Use assigned tools",
            List.of("page_read"),
            List.of(
                new CloudTeams.Channel(UUID.randomUUID().toString(), "slack", "T1", "C1", "@blot")),
            true);
    var saved = teams.saveBot(owner, team.id(), id, 0, config);
    assertEquals(1, saved.version());
    assertThrows(CloudFailure.class, () -> teams.saveBot(owner, team.id(), id, 0, config));
    assertThrows(CloudFailure.class, () -> teams.bots(other, team.id()));
    var invalid =
        new CloudTeams.BotConfiguration(
            "Bot", UUID.randomUUID(), other.deviceID(), "Instructions", List.of(), List.of(), true);
    assertThrows(
        CloudFailure.class, () -> teams.saveBot(owner, team.id(), UUID.randomUUID(), 0, invalid));
    teams.deleteBot(owner, team.id(), id, 1);
    assertTrue(teams.bots(owner, team.id()).isEmpty());
  }

  @Test
  void publishedSnapshotsExpireRevokeAndDoNotAllowAnotherOwnerToRevoke() {
    var owner = actor("owner@example.org");
    var other = actor("other@example.org");
    var link =
        content.publish(owner, "page", "Report", "{\"format\":\"blot.page.v1\",\"blocks\":[]}", 1);
    assertEquals("Report", content.read(link.token()).title());
    assertThrows(CloudFailure.class, () -> content.revoke(other, link.id()));
    assertThrows(
        CloudFailure.class,
        () ->
            new CloudPublishedContent(
                    database,
                    new CloudTokens(new byte[32]),
                    Clock.offset(clock, Duration.ofDays(2)),
                    new JacksonCodec())
                .read(link.token()));
    content.revoke(owner, link.id());
    assertThrows(CloudFailure.class, () -> content.read(link.token()));
  }
}
