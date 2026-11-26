# `CloudSnapshotController.java`

Предоставляет HTTP-обмен запросами и предложениями зашифрованного снимка. Обращается к `CloudSnapshots` от имени проверенного устройства.

[Исходник: `backend/cloud/src/main/java/dev/blot/cloud/web/CloudSnapshotController.java`](../../../../../../../../../backend/cloud/src/main/java/dev/blot/cloud/web/CloudSnapshotController.java)

Модуль: [cloud](../../../../../../../README.md). Раздел: [Маршруты облачного API](index.md).

## HTTP-маршруты

- `POST /v1/relay/snapshots`
- `GET /v1/relay/snapshots`
- `GET /v1/relay/snapshots/{id}`
- `POST /v1/relay/snapshots/offers`
