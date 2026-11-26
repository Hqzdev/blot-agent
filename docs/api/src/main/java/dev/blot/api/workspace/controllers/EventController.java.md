# `EventController.java`

Передаёт клиенту события v2 по SSE после указанного курсора. Проверяет сессию на протяжении подписки и возвращает ошибку для позиции, с которой воспроизведение недоступно.

[Исходник: `backend/api/src/main/java/dev/blot/api/workspace/controllers/EventController.java`](../../../../../../../../../../backend/api/src/main/java/dev/blot/api/workspace/controllers/EventController.java)

Модуль: [api](../../../../../../../../README.md). Раздел: [HTTP-контроллеры](index.md).

## HTTP-маршруты

- `GET /v2/events`

## Связанные файлы

- [WorkspaceStore](../../../../../../../../../application/src/main/java/dev/blot/application/ports/WorkspaceStore.java.md)
- [WorkspaceController](WorkspaceController.java.md)
- [SessionService](../../../../../../../../../application/src/main/java/dev/blot/application/workspace/conversation/SessionService.java.md)
