# `SqliteUnitOfWorkTest.java`

Проверяет сохранение ранних сущностей и outbox, полный откат транзакции при исключении и ограничения связей между записями.

[Исходник: `backend/infrastructure/src/test/java/dev/blot/infrastructure/SqliteUnitOfWorkTest.java`](../../../../../../../../backend/infrastructure/src/test/java/dev/blot/infrastructure/SqliteUnitOfWorkTest.java)

Модуль: [infrastructure](../../../../../../README.md). Раздел: [Проверки ранней SQLite](index.md).

## Проверки

- `roundTripAndDurableOutbox`
- `exceptionRollsBackStateAndEvents`
- `schemaRejectsOrphanRun`
