# `CloudRelayController.java`

Публикует маршруты загрузки и чтения зашифрованных изменений, квитанций, подтверждений и частей вложений. Передаёт запросы в `CloudRelay` и `CloudEncryptedBlobs`.

[Исходник: `backend/cloud/src/main/java/dev/blot/cloud/web/CloudRelayController.java`](../../../../../../../../../backend/cloud/src/main/java/dev/blot/cloud/web/CloudRelayController.java)

Модуль: [cloud](../../../../../../../README.md). Раздел: [Маршруты облачного API](index.md).

## HTTP-маршруты

- `POST /v1/relay/changes`
- `GET /v1/relay/changes/{id}/receipt`
- `GET /v1/relay/changes`
- `POST /v1/relay/ack`
- `PUT /v1/relay/blobs`
- `GET /v1/relay/blobs/{id}/{index}`
