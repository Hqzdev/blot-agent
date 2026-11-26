# `VmWorkspaceTransferTest.java`

Проверяет перенос файлов, ограничения области, обработку подмены пути и конфликтов между хостом и гостем.

[Исходник: `backend/infrastructure/src/test/java/dev/blot/infrastructure/workspace/VmWorkspaceTransferTest.java`](../../../../../../../../../backend/infrastructure/src/test/java/dev/blot/infrastructure/workspace/VmWorkspaceTransferTest.java)

Модуль: [infrastructure](../../../../../../../README.md). Раздел: [Проверки адаптеров и сценариев](index.md).

## Проверки

- `copiesFilesWithoutGitAndImportsOnlyAssignedPaths`
- `readonlyCheckCannotImportModifiedSources`
- `rejectsGuestSymlinkWithoutTouchingWorkspace`
- `detectsConcurrentEditBeforeImportingAnyFile`
- `guestCannotReplaceGitMetadataThroughDifferentLetterCase`
