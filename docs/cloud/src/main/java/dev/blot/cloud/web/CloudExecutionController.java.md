# `CloudExecutionController.java`

Принимает запросы на регистрацию задач, получение и продление аренды исполнителя, отмену и учёт внешних действий. Проверку полномочий выполняет `CloudLeases`.

[Исходник: `backend/cloud/src/main/java/dev/blot/cloud/web/CloudExecutionController.java`](../../../../../../../../../backend/cloud/src/main/java/dev/blot/cloud/web/CloudExecutionController.java)

Модуль: [cloud](../../../../../../../README.md). Раздел: [Маршруты облачного API](index.md).

## HTTP-маршруты

- `POST /v1/execution/tasks`
- `POST /v1/execution/acquire`
- `POST /v1/execution/renew`
- `POST /v1/execution/check`
- `POST /v1/execution/release`
- `POST /v1/execution/cancel`
- `POST /v1/execution/actions/begin`
- `POST /v1/execution/actions/finish`
