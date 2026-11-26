# `CommandDispatcher.java`

Находит зарегистрированный обработчик команды v2 и выполняет его в транзакции с квитанцией. Повтор с тем же ID и содержимым возвращает сохранённую квитанцию.

[Исходник: `backend/application/src/main/java/dev/blot/application/workspace/commands/CommandDispatcher.java`](../../../../../../../../../../backend/application/src/main/java/dev/blot/application/workspace/commands/CommandDispatcher.java)

Модуль: [application](../../../../../../../../README.md). Раздел: [Команды и каталог инструментов](index.md).

## Связанные файлы

- [WorkspaceStore](../../ports/WorkspaceStore.java.md)
- [Records](../Records.java.md)
- [WorkspaceController](../../../../../../../../../api/src/main/java/dev/blot/api/workspace/controllers/WorkspaceController.java.md)
