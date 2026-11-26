# `BlotApplicationServiceTest.java`

Проверяет типизированные сценарии раннего API: создание данных, допустимые переходы, версии и ошибки.

[Исходник: `backend/application/src/test/java/dev/blot/application/BlotApplicationServiceTest.java`](../../../../../../../../backend/application/src/test/java/dev/blot/application/BlotApplicationServiceTest.java)

Модуль: [application](../../../../../../README.md). Раздел: [Проверки ранних сценариев](index.md).

## Проверки

- `createsAndReadsProjectAndRecordsEventWithTheStateChange`
- `returnsTypedNotFoundWithoutWritingStateOrEvents`
- `changesRunStatusWithOptimisticVersionAndRejectsIllegalTransitions`
- `appendsImmutableSpecificationHistoryInRevisionOrder`
- `createsTasksOnlyWithDependenciesFromTheSameRun`
- `returnsValidationErrorsForInvalidBoundaryInput`
- `rollsBackStateAndEventsWhenTheUnitOfWorkOperationThrows`
