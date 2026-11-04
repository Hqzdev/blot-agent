package dev.blot.application.workspace;

import static org.junit.jupiter.api.Assertions.*;

import org.junit.jupiter.api.Test;

class WorkspacePathsTest {
  @Test
  void allowsProjectGitFilesButProtectsMetadataAndParentDirectories() {
    assertTrue(WorkspacePaths.isSafeRelative(".github/workflows"));
    assertTrue(WorkspacePaths.isSafeRelative(".gitignore"));
    assertTrue(WorkspacePaths.isSafeRelative("."));
    assertFalse(WorkspacePaths.isSafeRelative(".GIT/config"));
    assertFalse(WorkspacePaths.isSafeRelative("src/.Git/config"));
    assertFalse(WorkspacePaths.isSafeRelative("../outside"));
    assertFalse(WorkspacePaths.isSafeRelative("src/../outside"));
    assertFalse(WorkspacePaths.isSafeRelative(""));
  }
}
