# `GenerationWorker.java`

Забирает генерации из очереди и ведёт их до результата. Выбирает между ответом Work, формированием плана и запуском агентской сессии.

[Исходник: `backend/application/src/main/java/dev/blot/application/workspace/execution/GenerationWorker.java`](https://github.com/Hqzdev/kiln-agent/blob/4e6c47f65e0e734dedc122d586c7bb67d37395a3/backend/application/src/main/java/dev/blot/application/workspace/execution/GenerationWorker.java)

Модуль: [application](../../../../../../../../README.md). Раздел: [Выполнение и восстановление](index.md).

## Связанные файлы

- [GenerationStateService](GenerationStateService.java.md)
- [ModelStreamingService](../providers/ModelStreamingService.java.md)
- [AgentExecutionService](../agent/AgentExecutionService.java.md)
- [RunService](RunService.java.md)
