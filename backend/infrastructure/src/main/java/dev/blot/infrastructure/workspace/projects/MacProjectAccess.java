package dev.blot.infrastructure.workspace.projects;

import dev.blot.application.ports.*;
import dev.blot.application.ports.ProjectAccess;
import dev.blot.application.ports.WorkspaceStore;
import dev.blot.application.workspace.WorkspaceFailure;
import dev.blot.infrastructure.workspace.execution.MacPlatformBridge;
import java.nio.file.*;
import java.util.*;

/** Bookmark разрешается в самом Java-процессе через небольшой Foundation JNI adapter. */
public final class MacProjectAccess implements ProjectAccess, AutoCloseable {
  private final MacPlatformBridge bridge;
  private final WorkspaceStore store;
  private final Set<String> opened = new HashSet<>();
  private boolean loaded;
  private final String library;

  public MacProjectAccess(MacPlatformBridge bridge, WorkspaceStore store, String library) {
    this.bridge = bridge;
    this.store = store;
    this.library = library;
  }

  public synchronized void authorize(Path directory) {
    String path = directory.toAbsolutePath().normalize().toString();
    if (opened.contains(path)) return;
    if (!loaded) {
      try {
        System.load(Path.of(library).toAbsolutePath().toString());
        loaded = true;
      } catch (LinkageError | RuntimeException failure) {
        throw unavailable();
      }
    }
    Object value = bridge.request("project.bookmark", Map.of("path", path));
    if (!(value instanceof String bookmark) || bookmark.length() > 100000) throw unavailable();
    try {
      byte[] bytes = Base64.getDecoder().decode(bookmark);
      if (bytes.length > 65536 || !openBookmark(bytes, path)) throw unavailable();
      opened.add(path);
    } catch (IllegalArgumentException failure) {
      throw unavailable();
    }
  }

  public void restore() {
    for (String path : store.transact(WorkspaceStore.Transaction::projectPaths)) {
      try {
        authorize(Path.of(path));
      } catch (WorkspaceFailure failure) {
        System.getLogger(MacProjectAccess.class.getName())
            .log(System.Logger.Level.WARNING, "Повторно выберите недоступную папку проекта на Mac");
      }
    }
  }

  public synchronized void close() {
    if (loaded) closeBookmarks();
    opened.clear();
  }

  private static native boolean openBookmark(byte[] data, String expectedPath);

  private static native void closeBookmarks();

  private static WorkspaceFailure unavailable() {
    return new WorkspaceFailure(
        403, "project_access_required", "Выберите папку проекта на Mac повторно");
  }
}
