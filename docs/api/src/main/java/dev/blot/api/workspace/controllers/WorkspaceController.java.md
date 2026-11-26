# `WorkspaceController.java`

Принимает v2-команды и возвращает квитанции, списки записей и согласованный снимок. Также публикует справочник ролей, сведения о совместимости и маршруты сопряжения.

[Исходник: `backend/api/src/main/java/dev/blot/api/workspace/controllers/WorkspaceController.java`](../../../../../../../../../../backend/api/src/main/java/dev/blot/api/workspace/controllers/WorkspaceController.java)

Модуль: [api](../../../../../../../../README.md). Раздел: [HTTP-контроллеры](index.md).

## HTTP-маршруты

- `POST /v2/commands`
- `GET /v2/commands/{id}`
- `GET /v2/records/{kind}`
- `GET /v2/records/{kind}/{id}`
- `GET /v2/snapshot`
- `GET /v2/pairing/{id}/ticket`
- `POST /v2/pairing/request`
- `POST /v2/pairing/claim`
- `GET /v2/roles`
- `GET /v2/compatibility`

## Связанные файлы

- [RequestActor](../transport/RequestActor.java.md)
- [CommandDispatcher](../../../../../../../../../application/src/main/java/dev/blot/application/workspace/commands/CommandDispatcher.java.md)
- [EventController](EventController.java.md)
- [RecordCursor](../transport/RecordCursor.java.md)
