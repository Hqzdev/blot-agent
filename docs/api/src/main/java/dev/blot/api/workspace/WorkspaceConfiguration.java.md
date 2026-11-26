# `WorkspaceConfiguration.java`

Связывает компоненты локального сервера: SQLite, системный мост, хранилище секретов, модельный провайдер и прикладные сервисы. Здесь выбираются конкретные реализации портов и подключаются фоновые обработчики.

[Исходник: `backend/api/src/main/java/dev/blot/api/workspace/WorkspaceConfiguration.java`](../../../../../../../../../backend/api/src/main/java/dev/blot/api/workspace/WorkspaceConfiguration.java)

Модуль: [api](../../../../../../../README.md). Раздел: [Сборка локального сервера](index.md).

## Связанные файлы

- [SqliteWorkspaceStore](../../../../../../../../infrastructure/src/main/java/dev/blot/infrastructure/workspace/database/SqliteWorkspaceStore.java.md)
- [GenerationWorker](../../../../../../../../application/src/main/java/dev/blot/application/workspace/execution/GenerationWorker.java.md)
- [CloudConfiguration](../../../../../../../../cloud/src/main/java/dev/blot/cloud/CloudConfiguration.java.md)
