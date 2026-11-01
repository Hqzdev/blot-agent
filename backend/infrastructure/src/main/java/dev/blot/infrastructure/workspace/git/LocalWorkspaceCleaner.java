package dev.blot.infrastructure.workspace.git;

import dev.blot.application.ports.WorkspaceCleaner;
import dev.blot.application.workspace.WorkspaceFailure;
import java.io.IOException;
import java.nio.file.*;
import java.nio.file.attribute.BasicFileAttributes;
import java.util.*;

/** Удаляет только каталоги заданного запуска внутри служебной папки Blot. */
public final class LocalWorkspaceCleaner implements WorkspaceCleaner {
  private final Path root;
  private final GitCommandRunner git = new GitCommandRunner();

  public LocalWorkspaceCleaner(Path root) {
    this.root = root.toAbsolutePath().normalize();
  }

  public void removeRun(Path repository, UUID runId) {
    try {
      if (!Files.exists(root, LinkOption.NOFOLLOW_LINKS)) return;
      Path directory = root.toRealPath().resolve(runId.toString());
      if (Files.isSymbolicLink(root) || Files.isSymbolicLink(directory))
        throw WorkspaceFailure.invalid("Служебная папка заменена символической ссылкой");
      Path source = repository.toRealPath();
      if (source.startsWith(directory))
        throw WorkspaceFailure.invalid("Исходный репозиторий не может быть удалён");

      String registered = git.run(source, null, "worktree", "list", "--porcelain", "-z");
      for (String field : registered.split("\u0000")) {
        if (!field.startsWith("worktree ")) continue;
        Path workspace = Path.of(field.substring(9)).toAbsolutePath().normalize();
        if (!directory.equals(workspace.getParent())) continue;
        // Имена исполнителей генерирует сервер. Другие каталоги не передаём Git.
        UUID.fromString(workspace.getFileName().toString());
        git.run(source, null, "worktree", "remove", "--force", workspace.toString());
      }
      if (!Files.exists(directory, LinkOption.NOFOLLOW_LINKS)) return;
      // walkFileTree не следует по symlink: удаляется сама ссылка, не её цель.
      Files.walkFileTree(
          directory,
          new SimpleFileVisitor<>() {
            public FileVisitResult visitFile(Path file, BasicFileAttributes attributes)
                throws IOException {
              Files.delete(file);
              return FileVisitResult.CONTINUE;
            }

            public FileVisitResult postVisitDirectory(Path path, IOException failure)
                throws IOException {
              if (failure != null) throw failure;
              Files.delete(path);
              return FileVisitResult.CONTINUE;
            }
          });
    } catch (IOException failure) {
      throw new WorkspaceFailure(503, "workspace_cleanup_failed", "Рабочая область недоступна");
    }
  }
}
