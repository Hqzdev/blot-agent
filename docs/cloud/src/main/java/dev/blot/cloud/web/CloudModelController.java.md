# `CloudModelController.java`

Публикует сведения о квоте и потоковый маршрут генерации. Передаёт клиенту модельные порции через SSE после подготовки запроса.

[Исходник: `backend/cloud/src/main/java/dev/blot/cloud/web/CloudModelController.java`](../../../../../../../../../backend/cloud/src/main/java/dev/blot/cloud/web/CloudModelController.java)

Модуль: [cloud](../../../../../../../README.md). Раздел: [Маршруты облачного API](index.md).

## HTTP-маршруты

- `GET /v1/model/usage`
- `POST /v1/model/chat/completions`
