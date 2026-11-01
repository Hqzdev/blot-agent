package dev.blot.infrastructure.workspace;

import dev.blot.application.workspace.*;
import dev.blot.application.workspace.WorkspaceFailure;
import dev.blot.application.workspace.identity.TokenGenerator;
import dev.blot.infrastructure.workspace.git.LocalGitGateway;
import java.nio.file.*;
import java.util.*;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.io.TempDir;
import static org.junit.jupiter.api.Assertions.*;

import static org.junit.jupiter.api.Assertions.*;

import static org.junit.jupiter.api.Assertions.*;

class LocalGitGatewayTest {
  @TempDir Path directory;

  @Test
  void freezesAcceptedTreeDisablesFiltersAndProtectsMain() throws Exception {
    Path repository = Files.createDirectory(directory.resolve("repo"));
    git(repository, "init", "-b", "main");
    git(repository, "config", "user.name", "Test");
    git(repository, "config", "user.email", "test@example.com");
    Files.writeString(repository.resolve("source.txt"), "original\n");
    git(repository, "add", "--all");
    git(repository, "commit", "-m", "Base");
    var gateway = new LocalGitGateway(directory.resolve("workspaces"));
    String base = gateway.inspect(repository).baseSha();
    assertThrows(
        WorkspaceFailure.class, () -> gateway.commit(repository, base, "hash", "Rejected"));
    Path workspace = gateway.createWorkspace(repository, UUID.randomUUID(), UUID.randomUUID());
    Path outside = Files.createDirectory(directory.resolve("outside"));
    Files.writeString(outside.resolve("private.txt"), "Must stay outside");
    git(repository, "config", "core.worktree", outside.toString());
    Path marker = directory.resolve("filter-ran");
    git(repository, "config", "filter.untrusted.clean", "touch '" + marker + "'; cat");
    git(repository, "config", "filter.untrusted.smudge", "touch '" + marker + "'; cat");
    git(repository, "config", "filter.untrusted.required", "true");
    Files.writeString(workspace.resolve(".gitattributes"), "*.txt filter=untrusted\n");
    Files.writeString(workspace.resolve("source.txt"), "accepted\n");
    String snapshot = gateway.snapshot(workspace);
    assertFalse(snapshot.contains("private.txt"));
    assertFalse(Files.exists(marker), "Repository filters must not execute on the host");
    Files.writeString(workspace.resolve("source.txt"), "later edit\n");
    String commit =
        gateway.commit(workspace, base, new TokenGenerator().digest(snapshot), "Approved");
    assertEquals("accepted", git(workspace, "show", commit + ":source.txt").strip());
    assertEquals("later edit\n", Files.readString(workspace.resolve("source.txt")));
    Path remote = directory.resolve("remote.git");
    git(directory, "init", "--bare", "--initial-branch=main", remote.toString());
    git(repository, "push", remote.toString(), "main:main");
    git(workspace, "remote", "add", "origin", remote.toString());
    git(workspace, "symbolic-ref", "refs/remotes/origin/HEAD", "refs/remotes/origin/main");
    String branch = git(workspace, "symbolic-ref", "HEAD").strip();
    String result =
        gateway.push(workspace, "origin", branch + ":refs/heads/codex/accepted", commit);
    assertTrue(result.startsWith(commit));
    git(remote, "symbolic-ref", "HEAD", "refs/heads/codex/accepted");
    assertThrows(
        WorkspaceFailure.class,
        () -> gateway.push(workspace, "origin", branch + ":refs/heads/codex/accepted", commit));
  }

  private String git(Path path, String... args) throws Exception {
    var command = new ArrayList<>(List.of("/usr/bin/git", "-C", path.toString()));
    command.addAll(List.of(args));
    var process = new ProcessBuilder(command).redirectErrorStream(true).start();
    String output =
        new String(
            process.getInputStream().readAllBytes(), java.nio.charset.StandardCharsets.UTF_8);
    assertEquals(0, process.waitFor(), output);
    return output;
  }
}
