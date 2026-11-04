package dev.blot.infrastructure.workspace.git;

import dev.blot.application.ports.GitGateway;
import dev.blot.application.workspace.WorkspaceFailure;
import java.nio.file.*;
import java.util.*;

/** Только фиксированные операции Git. Произвольный shell здесь отсутствует. */
public final class LocalGitGateway implements GitGateway {
  private final Path workspaces;
  private final GitCommandRunner commands = new GitCommandRunner();

  public LocalGitGateway(Path workspaces) {
    this.workspaces = workspaces.toAbsolutePath().normalize();
  }

  public Repository inspect(Path root) {
    String sha = git(root, null, "rev-parse", "HEAD").strip();
    String branch;
    try {
      branch =
          git(root, null, "symbolic-ref", "refs/remotes/origin/HEAD")
              .strip()
              .replace("refs/remotes/origin/", "");
    } catch (WorkspaceFailure e) {
      branch = "main";
    }
    return new Repository(
        sha,
        branch,
        !git(root, null, "status", "--porcelain").isBlank(),
        git(root, null, "log", "-1", "--format=%P").strip(),
        git(root, null, "log", "-1", "--format=%B").strip());
  }

  public Path createWorkspace(Path repository, UUID run, UUID session) {
    try {
      Path dir = workspaces.resolve(run.toString());
      Files.createDirectories(dir);
      Path target = dir.resolve(session.toString());
      String branch = "codex/blot-" + session;
      git(repository, null, "worktree", "add", "-b", branch, target.toString(), "HEAD");
      String dirty =
          git(repository, null, "diff", "--no-ext-diff", "--no-textconv", "--binary", "HEAD");
      if (!dirty.isBlank()) integrate(target, dirty);
      String untracked = git(repository, null, "ls-files", "--others", "--exclude-standard", "-z");
      for (String name : untracked.split("\u0000")) {
        if (name.isBlank()) continue;
        Path source = repository.resolve(name).normalize();
        if (!source.toRealPath().startsWith(repository.toRealPath())
            || Files.isSymbolicLink(source))
          throw WorkspaceFailure.invalid("Небезопасный путь исходного файла");
        Path destination = target.resolve(name).normalize();
        if (!destination.startsWith(target)) throw WorkspaceFailure.invalid("Небезопасный путь");
        Files.createDirectories(destination.getParent());
        Files.copy(source, destination, StandardCopyOption.COPY_ATTRIBUTES);
      }
      return target;
    } catch (java.io.IOException e) {
      throw new WorkspaceFailure(
          503, "workspace_unavailable", "Не удалось создать рабочую область");
    }
  }

  public String snapshot(Path workspace) {
    git(workspace, null, "add", "--all");
    return git(
        workspace, null, "diff", "--no-ext-diff", "--no-textconv", "--cached", "--binary", "HEAD");
  }

  public void integrate(Path workspace, String patch) {
    if (patch.isBlank()) return;
    git(workspace, null, "add", "--all");
    git(workspace, patch, "apply", "--3way", "--binary", "--whitespace=nowarn", "-");
  }

  public String commit(
      Path workspace, String expectedBase, String expectedSnapshotHash, String message) {
    protect(workspace);
    if (!inspect(workspace).baseSha().equals(expectedBase))
      throw new WorkspaceFailure(409, "action_invalidated", "Исходный коммит изменился");
    String branch = git(workspace, null, "symbolic-ref", "HEAD").strip();
    String tree = git(workspace, null, "write-tree").strip();
    String patch =
        git(
            workspace,
            null,
            "diff",
            "--no-ext-diff",
            "--no-textconv",
            "--binary",
            expectedBase,
            tree);
    if (!new dev.blot.application.workspace.identity.TokenGenerator()
        .digest(patch)
        .equals(expectedSnapshotHash))
      throw new WorkspaceFailure(
          409, "action_invalidated", "Подготовленный tree изменился после ревью");
    String commit = git(workspace, message, "commit-tree", tree, "-p", expectedBase).strip();
    // update-ref сравнивает старый SHA атомарно. Новые файлы после подготовки не попадают в tree.
    git(workspace, null, "update-ref", branch, commit, expectedBase);
    return commit;
  }

  public String push(Path workspace, String remote, String refspec, String expectedCommit) {
    protect(workspace);
    if (!remote.matches("[A-Za-z0-9][A-Za-z0-9._-]*")
        || !refspec.matches("refs/heads/codex/[A-Za-z0-9._/-]+:refs/heads/codex/[A-Za-z0-9._/-]+"))
      throw new WorkspaceFailure(
          403, "protected_ref", "Разрешён только точный push рабочей ветки codex");
    String destination = refspec.substring(refspec.indexOf(':') + 1);
    if (destination.equals("refs/heads/" + inspect(workspace).defaultBranch()))
      throw new WorkspaceFailure(403, "protected_ref", "Основная ветка защищена");
    String source = refspec.substring(0, refspec.indexOf(':'));
    if (!git(workspace, null, "rev-parse", source).strip().equals(inspect(workspace).baseSha()))
      throw new WorkspaceFailure(
          403, "scope_violation", "Источник push не совпадает с принятой веткой");
    Remote info = remote(workspace, remote);
    if (!inspect(workspace).baseSha().equals(expectedCommit) || info.pushUrls().size() != 1)
      throw new WorkspaceFailure(
          409, "action_invalidated", "Коммит изменился или remote содержит несколько адресов push");
    String endpoint = info.pushUrls().getFirst();
    String remoteDefault =
        git(workspace, null, "ls-remote", "--symref", endpoint, "HEAD")
            .lines()
            .filter(line -> line.startsWith("ref: ") && line.indexOf(9) > 5)
            .map(line -> line.substring(5, line.indexOf(9)))
            .findFirst()
            .orElseThrow(
                () -> WorkspaceFailure.invalid("Не удалось определить основную ветку remote"));
    if (destination.equals(remoteDefault))
      throw new WorkspaceFailure(403, "protected_ref", "Удалённая основная ветка защищена");
    if (destination.equals("refs/heads/" + info.defaultBranch()))
      throw new WorkspaceFailure(403, "protected_ref", "Удалённая основная ветка защищена");
    git(workspace, null, "push", "--porcelain", "--", endpoint, expectedCommit + ":" + destination);
    return git(workspace, null, "ls-remote", endpoint, destination).strip();
  }

  public Remote remote(Path workspace, String name) {
    if (name == null || !name.matches("[A-Za-z0-9][A-Za-z0-9._-]*"))
      throw WorkspaceFailure.invalid("Неверное имя remote");
    String branch =
        git(workspace, null, "symbolic-ref", "refs/remotes/" + name + "/HEAD")
            .strip()
            .replace("refs/remotes/" + name + "/", "");
    var urls =
        git(workspace, null, "remote", "get-url", "--push", "--all", name)
            .lines()
            .filter(u -> !u.isBlank())
            .toList();
    if (urls.isEmpty()
        || urls.stream()
            .anyMatch(u -> u.startsWith("-") || u.contains("ext::") || u.startsWith("git://")))
      throw new WorkspaceFailure(403, "remote_forbidden", "Небезопасный адрес remote");
    return new Remote(branch, urls);
  }

  public String remoteHead(Path workspace, String name, String fullRef) {
    remote(workspace, name);
    if (!fullRef.matches("refs/heads/codex/[A-Za-z0-9._/-]+"))
      throw WorkspaceFailure.invalid("Неверная ссылка Git");
    return git(workspace, null, "ls-remote", name, fullRef).strip();
  }

  private void protect(Path workspace) {
    String branch = git(workspace, null, "symbolic-ref", "--short", "HEAD").strip();
    if (!branch.startsWith("codex/") || branch.equals(inspect(workspace).defaultBranch()))
      throw new WorkspaceFailure(403, "protected_ref", "Изменение защищённой ветки запрещено");
  }

  private String git(Path root, String input, String... args) {
    return commands.run(root, input, args);
  }
}
