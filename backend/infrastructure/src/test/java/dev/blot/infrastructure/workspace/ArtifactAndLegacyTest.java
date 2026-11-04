package dev.blot.infrastructure.workspace;

import static org.junit.jupiter.api.Assertions.*;

import dev.blot.application.*;
import dev.blot.application.ApplicationResult;
import dev.blot.application.BlotApplicationService;
import dev.blot.application.ports.*;
import dev.blot.application.workspace.*;
import dev.blot.application.workspace.Records;
import dev.blot.application.workspace.WorkspaceFailure;
import dev.blot.application.workspace.library.LegacyImportService;
import dev.blot.application.workspace.projects.ProjectService;
import dev.blot.core.workspace.*;
import dev.blot.core.workspace.Entity;
import dev.blot.core.workspace.EntityKind;
import dev.blot.core.workspace.artifact.ArtifactData;
import dev.blot.core.workspace.identity.AccountData;
import dev.blot.core.workspace.identity.Actor;
import dev.blot.core.workspace.projects.RunData;
import dev.blot.infrastructure.database.SqliteUnitOfWork;
import dev.blot.infrastructure.workspace.artifacts.LocalArtifactStore;
import dev.blot.infrastructure.workspace.database.SqliteWorkspaceStore;
import dev.blot.infrastructure.workspace.git.LocalGitGateway;
import dev.blot.infrastructure.workspace.projects.LocalProjectAccess;
import java.nio.file.*;
import java.nio.file.attribute.FileTime;
import java.time.*;
import java.util.*;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.io.TempDir;

class ArtifactAndLegacyTest {
  @TempDir Path directory;

  @Test
  void readsRangesAndCollectsOnlyOldUnreferencedBlobs() throws Exception {
    var artifacts = new LocalArtifactStore(directory.resolve("artifacts"));
    byte[] bytes = new byte[2_200_000];
    new Random(1).nextBytes(bytes);
    var kept = artifacts.write(bytes);
    var unused = artifacts.write(new byte[] {1, 2, 3});
    assertArrayEquals(
        Arrays.copyOfRange(bytes, 1_048_576, 1_548_576),
        artifacts.read(kept.relativePath(), kept.hash(), 1_048_576, 500_000));
    var old = FileTime.from(Instant.now().minus(Duration.ofDays(2)));
    Files.setLastModifiedTime(directory.resolve("artifacts").resolve(kept.relativePath()), old);
    Files.setLastModifiedTime(directory.resolve("artifacts").resolve(unused.relativePath()), old);
    artifacts.removeUnused(Set.of(kept.relativePath()), Instant.now().minus(Duration.ofDays(1)));
    assertTrue(Files.exists(directory.resolve("artifacts").resolve(kept.relativePath())));
    assertFalse(Files.exists(directory.resolve("artifacts").resolve(unused.relativePath())));
    Files.write(directory.resolve("artifacts").resolve(kept.relativePath()), new byte[] {9});
    assertEquals(
        "artifact_corrupt",
        assertThrows(
                WorkspaceFailure.class,
                () -> artifacts.read(kept.relativePath(), kept.hash(), 0, 1))
            .code());
  }

  @Test
  void oldDataNeedsLocalConfirmationAndCanBeClaimedOnlyOnce() throws Exception {
    var clock = Clock.systemUTC();
    var database = directory.resolve("data.db");
    Path repo = Files.createDirectory(directory.resolve("repository"));
    git(repo, "init", "-b", "main");
    git(
        repo,
        "-c",
        "user.name=Test",
        "-c",
        "user.email=test@example.com",
        "commit",
        "--allow-empty",
        "-m",
        "Base");
    var oldStore = new SqliteUnitOfWork(database);
    var old = new BlotApplicationService(oldStore, clock, UUID::randomUUID);
    var project = success(old.createProject(new BlotApplicationService.CreateProject("Old", repo)));
    var run =
        success(old.createRun(new BlotApplicationService.CreateRun(project.id(), "Previous goal")));
    old.addSpecificationRevision(
        new BlotApplicationService.AddSpecificationRevision(run.id(), "Original requirements"));
    var json = new JacksonCodec();
    var store = new SqliteWorkspaceStore(database, json, clock);
    var records = new Records(clock);
    UUID owner = UUID.randomUUID();
    store.transact(
        tx -> {
          tx.insert(
              EntityKind.ACCOUNT,
              new Entity<>(
                  owner,
                  owner,
                  null,
                  null,
                  0,
                  clock.instant(),
                  clock.instant(),
                  new AccountData("owner@example.com", "hash", true, "Owner")));
          return null;
        });
    var actor = new Actor(owner, null, null, true);
    assertEquals(1, store.transact(tx -> tx.unclaimedProjects(0, 100)).size());
    String archive = store.transact(tx -> tx.legacyArchive(project.id()));
    assertTrue(archive.contains("Original requirements"));
    var service =
        new LegacyImportService(
            new ProjectService(
                new LocalGitGateway(directory.resolve("workspaces")),
                records,
                new LocalProjectAccess()),
            new LocalArtifactStore(directory.resolve("artifacts")),
            records,
            json);
    assertThrows(
        WorkspaceFailure.class,
        () -> store.transact(tx -> service.adopt(tx, actor, project.id(), false)));
    assertThrows(
        WorkspaceFailure.class,
        () ->
            store.transact(
                tx ->
                    service.adopt(
                        tx, new Actor(owner, null, UUID.randomUUID(), false), project.id(), true)));
    var imported = store.transact(tx -> service.adopt(tx, actor, project.id(), true));
    assertEquals("Old", imported.data().name());
    var artifacts =
        store.transact(
            tx -> tx.all(EntityKind.ARTIFACT, owner, imported.id(), null, ArtifactData.class));
    assertEquals(1, artifacts.size());
    assertTrue(
        store
            .transact(tx -> tx.all(EntityKind.RUN, owner, imported.id(), null, RunData.class))
            .isEmpty(),
        "Legacy statuses must not start a new workflow");
    assertTrue(store.transact(tx -> tx.unclaimedProjects(0, 100)).isEmpty());
    assertThrows(
        WorkspaceFailure.class,
        () ->
            store.transact(
                tx -> {
                  tx.claimLegacy(project.id(), owner, UUID.randomUUID());
                  return null;
                }));
    try (var files = Files.list(directory)) {
      var backup =
          files
              .filter(
                  path ->
                      path.getFileName().toString().startsWith("data.db.before-v8-")
                          && !path.toString().endsWith(".tmp"))
              .findFirst()
              .orElseThrow();
      try (var connection = java.sql.DriverManager.getConnection("jdbc:sqlite:" + backup);
          var statement = connection.createStatement()) {
        try (var check = statement.executeQuery("PRAGMA quick_check")) {
          assertEquals("ok", check.getString(1));
        }
        try (var projects = statement.executeQuery("SELECT COUNT(*) FROM projects")) {
          assertEquals(1, projects.getInt(1));
        }
      }
    }
  }

  private void git(Path path, String... args) throws Exception {
    var command = new ArrayList<>(List.of("/usr/bin/git", "-C", path.toString()));
    command.addAll(List.of(args));
    var process = new ProcessBuilder(command).redirectErrorStream(true).start();
    String output =
        new String(
            process.getInputStream().readAllBytes(), java.nio.charset.StandardCharsets.UTF_8);
    assertEquals(0, process.waitFor(), output);
  }

  private <T> T success(ApplicationResult<T> result) {
    return ((ApplicationResult.Success<T>) result).value();
  }
}
