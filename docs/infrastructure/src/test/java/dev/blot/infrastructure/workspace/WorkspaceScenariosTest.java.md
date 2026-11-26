# `WorkspaceScenariosTest.java`

Проверяет локальные сценарии аккаунта, транзакции команд, изоляцию владельцев, разрешения, курсоры, изменения контекста и восстановление планирования.

[Исходник: `backend/infrastructure/src/test/java/dev/blot/infrastructure/workspace/WorkspaceScenariosTest.java`](../../../../../../../../../backend/infrastructure/src/test/java/dev/blot/infrastructure/workspace/WorkspaceScenariosTest.java)

Модуль: [infrastructure](../../../../../../../README.md). Раздел: [Проверки адаптеров и сценариев](index.md).

## Проверки

- `verificationSessionsAndResetAreReal`
- `invalidCodeAttemptsRemainCommitted`
- `commandRetryReturnsSameReceiptAndRollsBackFailure`
- `memoryAndEventsAreIsolatedByOwner`
- `grantIsConsumedOnceAndVersionConflictsDoNotOverwrite`
- `keysetPageDoesNotSkipRecordsAfterEarlierDeletion`
- `deletingSourceInvalidatesSummaryAndStopsUsingDerivedFact`
- `failedPlanningWaitsAndCanResumeAfterConfigurationIsFixed`
- `commandReadPreparationRunsBeforeTransactionAndIsSkippedOnRetry`
