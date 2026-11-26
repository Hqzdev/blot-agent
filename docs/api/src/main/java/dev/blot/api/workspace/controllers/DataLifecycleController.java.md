# `DataLifecycleController.java`

Выдаёт экспорт проекта, диагностическую сводку, содержимое артефакта и сведения о сопряжении. На чтении проверяет текущую сессию и владельца данных.

[Исходник: `backend/api/src/main/java/dev/blot/api/workspace/controllers/DataLifecycleController.java`](../../../../../../../../../../backend/api/src/main/java/dev/blot/api/workspace/controllers/DataLifecycleController.java)

Модуль: [api](../../../../../../../../README.md). Раздел: [HTTP-контроллеры](index.md).

## HTTP-маршруты

- `GET /v2/projects/{id}/export`
- `GET /v2/diagnostics`
- `GET /v2/artifacts/{id}/content`
- `GET /v2/devices/pairings`
