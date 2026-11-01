package dev.blot.infrastructure.workspace.execution;

import dev.blot.application.workspace.WorkspaceFailure;
import java.io.IOException;
import java.nio.file.*;
import java.nio.file.attribute.BasicFileAttributes;
import java.security.*;
import java.util.*;

/** VM видит только копии обычных файлов; ссылки и служебный Git не передаются. */
public final class VmWorkspaceTransfer {
  private static final Set<String> EXCLUDED =
      Set.of(".git", ".build", ".gradle", "build", "DerivedData", "node_modules");
  private final Path workspace;
  private final Path staging;
  private final List<Path> scopes;
  private final Map<Path, String> original;

  public VmWorkspaceTransfer(Path workspace, Path staging, List<String> scopes) throws IOException {
    this.workspace = workspace.toRealPath();
    this.staging = staging;
    this.scopes = scopes.stream().map(Path::of).map(Path::normalize).toList();
    if (this.scopes.stream().anyMatch(p -> p.isAbsolute() || p.startsWith("..")))
      throw WorkspaceFailure.invalid("Неверная область процесса");
    original = inventory(this.workspace);
    Files.createDirectories(staging);
    for (Path relative : original.keySet()) {
      Path target = staging.resolve(relative);
      Files.createDirectories(target.getParent());
      Files.copy(this.workspace.resolve(relative), target, StandardCopyOption.COPY_ATTRIBUTES);
    }
  }

  public void importChanges() throws IOException {
    Map<Path, String> result = inventory(staging);
    var paths = new TreeSet<Path>(original.keySet());
    paths.addAll(result.keySet());
    if (scopes.isEmpty()
        && paths.stream().anyMatch(p -> !Objects.equals(original.get(p), result.get(p))))
      throw new WorkspaceFailure(
          409, "read_only_workspace_changed", "Проверка изменила исходные файлы внутри VM");
    var changed =
        paths.stream()
            .filter(p -> !Objects.equals(original.get(p), result.get(p)))
            .filter(this::allowed)
            .toList();
    // Проверяем весь набор до первого изменения: пользователь мог редактировать файлы во время
    // сборки.
    for (Path path : changed) {
      Path target = target(path);
      String current = Files.exists(target, LinkOption.NOFOLLOW_LINKS) ? hash(target) : null;
      if (!Objects.equals(current, original.get(path)))
        throw new WorkspaceFailure(
            409, "workspace_changed", "Рабочие файлы изменились во время выполнения VM");
    }
    for (Path path : changed) {
      Path target = target(path);
      if (!result.containsKey(path)) {
        Files.deleteIfExists(target);
        continue;
      }
      Files.createDirectories(target.getParent());
      Path temporary = Files.createTempFile(target.getParent(), ".blot-vm-", ".tmp");
      try {
        Files.copy(
            staging.resolve(path),
            temporary,
            StandardCopyOption.REPLACE_EXISTING,
            StandardCopyOption.COPY_ATTRIBUTES);
        Files.move(
            temporary, target, StandardCopyOption.ATOMIC_MOVE, StandardCopyOption.REPLACE_EXISTING);
      } finally {
        Files.deleteIfExists(temporary);
      }
    }
  }

  private Path target(Path relative) throws IOException {
    Path path = workspace.resolve(relative);
    Path ancestor = path;
    while (!Files.exists(ancestor, LinkOption.NOFOLLOW_LINKS)) ancestor = ancestor.getParent();
    if (!ancestor.toRealPath().startsWith(workspace) || Files.isSymbolicLink(ancestor))
      throw WorkspaceFailure.invalid("Изменённый путь выходит за рабочую область");
    // Не разрешаем даже внутреннюю ссылку: цель могла измениться после проверки.
    Path current = workspace;
    for (Path part : relative) {
      current = current.resolve(part);
      if (Files.isSymbolicLink(current)) throw WorkspaceFailure.invalid("Ссылка в изменённом пути");
    }
    return path;
  }

  private boolean allowed(Path relative) {
    return scopes.stream()
        .anyMatch(
            scope ->
                scope.toString().isEmpty()
                    || scope.toString().equals(".")
                    || relative.startsWith(scope));
  }

  private static boolean excluded(Path path) {
    String name = path.getFileName().toString();
    return EXCLUDED.stream().anyMatch(value -> value.equalsIgnoreCase(name));
  }

  private static Map<Path, String> inventory(Path root) throws IOException {
    var result = new LinkedHashMap<Path, String>();
    long[] total = {0};
    Files.walkFileTree(
        root,
        new SimpleFileVisitor<>() {
          @Override
          public FileVisitResult preVisitDirectory(Path dir, BasicFileAttributes attributes)
              throws IOException {
            if (!dir.equals(root) && excluded(dir)) return FileVisitResult.SKIP_SUBTREE;
            return FileVisitResult.CONTINUE;
          }

          @Override
          public FileVisitResult visitFile(Path file, BasicFileAttributes attributes)
              throws IOException {
            if (excluded(file)) return FileVisitResult.CONTINUE;
            if (!attributes.isRegularFile() || attributes.isSymbolicLink())
              throw WorkspaceFailure.invalid(
                  "Для VM разрешены только обычные файлы без символических ссылок");
            total[0] += attributes.size();
            if (attributes.size() > 33_554_432 || total[0] > 268_435_456 || result.size() >= 20_000)
              throw WorkspaceFailure.invalid("Превышен размер переноса файлов в VM");
            result.put(root.relativize(file), hash(file));
            return FileVisitResult.CONTINUE;
          }
        });
    return result;
  }

  private static String hash(Path file) throws IOException {
    if (!Files.isRegularFile(file, LinkOption.NOFOLLOW_LINKS))
      throw WorkspaceFailure.invalid("Ожидался обычный файл");
    try (var input = Files.newInputStream(file, LinkOption.NOFOLLOW_LINKS)) {
      var digest = MessageDigest.getInstance("SHA-256");
      byte[] buffer = new byte[65_536];
      int length;
      while ((length = input.read(buffer)) != -1) digest.update(buffer, 0, length);
      return HexFormat.of().formatHex(digest.digest());
    } catch (NoSuchAlgorithmException e) {
      throw new IllegalStateException(e);
    }
  }
}
