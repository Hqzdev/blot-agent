package dev.blot.infrastructure.workspace;

import static org.junit.jupiter.api.Assertions.*;

import dev.blot.application.workspace.*;
import dev.blot.application.workspace.Records;
import dev.blot.application.workspace.WorkspaceFailure;
import dev.blot.application.workspace.WorkspaceMaintenance;
import dev.blot.application.workspace.data.DataLifecycleService;
import dev.blot.core.workspace.*;
import dev.blot.core.workspace.Entity;
import dev.blot.core.workspace.EntityKind;
import dev.blot.core.workspace.identity.AccountData;
import dev.blot.core.workspace.identity.Actor;
import dev.blot.core.workspace.projects.ProjectData;
import dev.blot.core.workspace.projects.RunData;
import dev.blot.core.workspace.projects.WorkspaceCleanupData;
import dev.blot.infrastructure.workspace.database.SqliteWorkspaceStore;
import dev.blot.infrastructure.workspace.git.LocalGitGateway;
import dev.blot.infrastructure.workspace.git.LocalWorkspaceCleaner;
import java.nio.file.*;
import java.time.Clock;
import java.util.*;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.io.TempDir;

class WorkspaceCleanupTest {
  @TempDir Path directory;

  @Test
  void deletionSurvivesRetryAndPreservesSourceAndOtherRuns() throws Exception {
    Path repository = repository();
    Path managed = directory.resolve("workspaces");
    var git = new LocalGitGateway(managed);
    UUID removedRun = UUID.randomUUID();
    Path removed = git.createWorkspace(repository, removedRun, UUID.randomUUID());
    Path kept = git.createWorkspace(repository, UUID.randomUUID(), UUID.randomUUID());
    Files.writeString(repository.resolve("source.txt"), "User changes\n");
    Files.writeString(repository.resolve("untracked.txt"), "User file\n");
    Files.writeString(removed.resolve("source.txt"), "Agent changes\n");
    Path outside = Files.createDirectory(directory.resolve("outside"));
    Files.writeString(outside.resolve("private.txt"), "Keep\n");
    Files.createSymbolicLink(removed.getParent().resolve("outside-link"), outside);

    var clock = Clock.systemUTC();
    var json = new JacksonCodec();
    Path database = directory.resolve("data.db");
    var store = new SqliteWorkspaceStore(database, json, clock);
    var records = new Records(clock);
    UUID owner = UUID.randomUUID();
    var actor = new Actor(owner, null, null, true);
    var project =
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
              var created =
                  records.create(
                      tx,
                      EntityKind.PROJECT,
                      owner,
                      null,
                      null,
                      new ProjectData(
                          "Project",
                          repository.toString(),
                          git.inspect(repository).baseSha(),
                          "main",
                          false));
              tx.insert(
                  EntityKind.RUN,
                  new Entity<>(
                      removedRun,
                      owner,
                      created.id(),
                      null,
                      0,
                      clock.instant(),
                      clock.instant(),
                      new RunData("Done", "COMPLETED", null, 1, null)));
              return created;
            });
    var lifecycle = new DataLifecycleService(store, records);
    var preparation =
        store.transact(
            tx ->
                records.create(
                    tx,
                    EntityKind.WORKSPACE_CLEANUP,
                    owner,
                    project.id(),
                    removedRun,
                    new WorkspaceCleanupData(
                        project.id(), removedRun, repository.toString(), "PREPARING", null)));
    assertThrows(
        WorkspaceFailure.class,
        () ->
            store.transact(
                tx -> {
                  lifecycle.deleteProject(tx, actor, project.id(), project.version());
                  return null;
                }));
    store.transact(
        tx -> {
          tx.delete(EntityKind.WORKSPACE_CLEANUP, owner, preparation.id());
          lifecycle.deleteProject(tx, actor, project.id(), project.version());
          return null;
        });
    assertTrue(
        store
            .transact(tx -> tx.find(EntityKind.PROJECT, owner, project.id(), ProjectData.class))
            .isEmpty());
    assertTrue(Files.exists(removed));
    assertTrue(store.transact(tx -> tx.projectPaths()).contains(repository.toString()));
    try (var maintenance =
        new WorkspaceMaintenance(
            store,
            (repo, run) -> {
              throw new WorkspaceFailure(503, "unavailable", "Temporary failure");
            },
            records)) {
      maintenance.cleanup();
    }
    assertEquals(
        "RETRY",
        store
            .transact(
                tx ->
                    tx.all(
                        EntityKind.WORKSPACE_CLEANUP,
                        owner,
                        null,
                        null,
                        WorkspaceCleanupData.class))
            .getFirst()
            .data()
            .status());

    var reopened = new SqliteWorkspaceStore(database, json, clock);
    try (var maintenance =
        new WorkspaceMaintenance(reopened, new LocalWorkspaceCleaner(managed), records)) {
      maintenance.cleanup();
      maintenance.cleanup();
    }
    assertTrue(
        reopened
            .transact(
                tx ->
                    tx.all(
                        EntityKind.WORKSPACE_CLEANUP,
                        owner,
                        null,
                        null,
                        WorkspaceCleanupData.class))
            .isEmpty());
    assertFalse(Files.exists(removed.getParent()));
    assertFalse(reopened.transact(tx -> tx.projectPaths()).contains(repository.toString()));
    assertTrue(Files.exists(kept.resolve("source.txt")));
    assertEquals("Keep\n", Files.readString(outside.resolve("private.txt")));
    assertEquals("User changes\n", Files.readString(repository.resolve("source.txt")));
    assertEquals("User file\n", Files.readString(repository.resolve("untracked.txt")));
    assertEquals("main", git(repository, "branch", "--show-current").strip());
    assertFalse(git(repository, "worktree", "list", "--porcelain").contains(removed.toString()));
  }

  @Test
  void refusesSubstitutedRunDirectory() throws Exception {
    Path repository = repository();
    Path managed = Files.createDirectory(directory.resolve("workspaces"));
    UUID run = UUID.randomUUID();
    Files.createSymbolicLink(managed.resolve(run.toString()), repository);
    var cleaner = new LocalWorkspaceCleaner(managed);
    assertThrows(WorkspaceFailure.class, () -> cleaner.removeRun(repository, run));
    assertEquals("Base\n", Files.readString(repository.resolve("source.txt")));
  }

  private Path repository() throws Exception {
    Path repository = Files.createDirectory(directory.resolve("repository"));
    git(repository, "init", "-b", "main");
    git(repository, "config", "user.name", "Test");
    git(repository, "config", "user.email", "test@example.com");
    Files.writeString(repository.resolve("source.txt"), "Base\n");
    git(repository, "add", "--all");
    git(repository, "commit", "-m", "Base");
    return repository;
  }

  private String git(Path path, String... arguments) throws Exception {
    var command = new ArrayList<>(List.of("/usr/bin/git", "-C", path.toString()));
    command.addAll(List.of(arguments));
    var process = new ProcessBuilder(command).redirectErrorStream(true).start();
    String output =
        new String(
            process.getInputStream().readAllBytes(), java.nio.charset.StandardCharsets.UTF_8);
    assertEquals(0, process.waitFor(), output);
    return output;
  }
}
