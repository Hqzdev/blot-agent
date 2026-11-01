package dev.blot.infrastructure.workspace;

import dev.blot.application.workspace.WorkspaceFailure;
import dev.blot.infrastructure.workspace.execution.VmWorkspaceTransfer;
import java.nio.file.*;
import java.util.List;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.io.TempDir;
import static org.junit.jupiter.api.Assertions.*;

import static org.junit.jupiter.api.Assertions.*;

import static org.junit.jupiter.api.Assertions.*;

class VmWorkspaceTransferTest {
  @TempDir Path directory;

  @Test
  void copiesFilesWithoutGitAndImportsOnlyAssignedPaths() throws Exception {
    Path source = Files.createDirectory(directory.resolve("source"));
    Files.createDirectories(source.resolve("src"));
    Files.writeString(source.resolve("src/code.txt"), "before");
    Files.writeString(source.resolve("other.txt"), "keep");
    Files.writeString(source.resolve(".git"), "gitdir: /private/user/repo");
    Path copy = directory.resolve("copy");
    var transfer = new VmWorkspaceTransfer(source, copy, List.of("src"));
    assertFalse(Files.exists(copy.resolve(".git")));
    Files.writeString(copy.resolve("src/code.txt"), "after");
    Files.writeString(copy.resolve("other.txt"), "unauthorized");
    transfer.importChanges();
    assertEquals("after", Files.readString(source.resolve("src/code.txt")));
    assertEquals("keep", Files.readString(source.resolve("other.txt")));
  }

  @Test
  void readonlyCheckCannotImportModifiedSources() throws Exception {
    Path source = Files.createDirectory(directory.resolve("source"));
    Files.writeString(source.resolve("code.txt"), "before");
    Path copy = directory.resolve("copy");
    var transfer = new VmWorkspaceTransfer(source, copy, List.of());
    Files.writeString(copy.resolve("code.txt"), "changed by check");
    assertThrows(WorkspaceFailure.class, transfer::importChanges);
    assertEquals("before", Files.readString(source.resolve("code.txt")));
  }

  @Test
  void rejectsGuestSymlinkWithoutTouchingWorkspace() throws Exception {
    Path source = Files.createDirectory(directory.resolve("source"));
    Files.writeString(source.resolve("code.txt"), "before");
    Path copy = directory.resolve("copy");
    var transfer = new VmWorkspaceTransfer(source, copy, List.of("."));
    Files.delete(copy.resolve("code.txt"));
    Files.createSymbolicLink(copy.resolve("code.txt"), directory.resolve("secret"));
    assertThrows(WorkspaceFailure.class, transfer::importChanges);
    assertEquals("before", Files.readString(source.resolve("code.txt")));
  }

  @Test
  void detectsConcurrentEditBeforeImportingAnyFile() throws Exception {
    Path source = Files.createDirectory(directory.resolve("source"));
    Files.writeString(source.resolve("a.txt"), "before");
    Files.writeString(source.resolve("b.txt"), "before");
    Path copy = directory.resolve("copy");
    var transfer = new VmWorkspaceTransfer(source, copy, List.of("."));
    Files.writeString(copy.resolve("a.txt"), "guest");
    Files.writeString(copy.resolve("b.txt"), "guest");
    Files.writeString(source.resolve("b.txt"), "user");
    assertThrows(WorkspaceFailure.class, transfer::importChanges);
    assertEquals("before", Files.readString(source.resolve("a.txt")));
    assertEquals("user", Files.readString(source.resolve("b.txt")));
  }

  @Test
  void guestCannotReplaceGitMetadataThroughDifferentLetterCase() throws Exception {
    Path source = Files.createDirectory(directory.resolve("source"));
    Files.writeString(source.resolve(".git"), "gitdir: original");
    Files.writeString(source.resolve("code.txt"), "before");
    Path copy = directory.resolve("copy");
    var transfer = new VmWorkspaceTransfer(source, copy, List.of("."));
    Files.writeString(copy.resolve(".GIT"), "gitdir: unauthorized");
    Files.createDirectories(copy.resolve("nested/.GiT"));
    Files.writeString(copy.resolve("nested/.GiT/config"), "unauthorized");
    transfer.importChanges();
    assertEquals("gitdir: original", Files.readString(source.resolve(".git")));
    assertFalse(Files.exists(source.resolve("nested/.GiT/config")));
  }
}
