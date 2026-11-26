# `WorkspaceCleanupTest.java`

Проверяет повтор очистки рабочего каталога и сохранность исходного проекта и чужих запусков, включая случаи подмены каталога.

[Исходник: `backend/infrastructure/src/test/java/dev/blot/infrastructure/workspace/WorkspaceCleanupTest.java`](../../../../../../../../../backend/infrastructure/src/test/java/dev/blot/infrastructure/workspace/WorkspaceCleanupTest.java)

Модуль: [infrastructure](../../../../../../../README.md). Раздел: [Проверки адаптеров и сценариев](index.md).

## Проверки

- `deletionSurvivesRetryAndPreservesSourceAndOtherRuns`
- `refusesSubstitutedRunDirectory`
