# `SerializedProvider.java`

Ставит модельные запросы в очередь по группе конкуренции и фиксирует состояние каждого запроса. Восстанавливает записи очереди после перезапуска.

[Исходник: `backend/application/src/main/java/dev/blot/application/workspace/execution/SerializedProvider.java`](../../../../../../../../../../backend/application/src/main/java/dev/blot/application/workspace/execution/SerializedProvider.java)

Модуль: [application](../../../../../../../../README.md). Раздел: [Выполнение и восстановление](index.md).

## Связанные файлы

- [ModelRequestData](../../../../../../../../../core/src/main/java/dev/blot/core/workspace/execution/ModelRequestData.java.md)
- [RetryingProvider](RetryingProvider.java.md)
- [BudgetedProvider](../billing/BudgetedProvider.java.md)
