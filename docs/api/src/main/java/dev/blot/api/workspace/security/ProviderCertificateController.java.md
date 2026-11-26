# `ProviderCertificateController.java`

Даёт клиенту прочитать состояние доверия к сертификату провайдера, проверить PEM и подтвердить сохранение сертификата. Проверку и установку выполняет сервис провайдера.

[Исходник: `backend/api/src/main/java/dev/blot/api/workspace/security/ProviderCertificateController.java`](../../../../../../../../../../backend/api/src/main/java/dev/blot/api/workspace/security/ProviderCertificateController.java)

Модуль: [api](../../../../../../../../README.md). Раздел: [Транспорт и секреты](index.md).

## HTTP-маршруты

- `GET /v2/provider/certificate`
- `POST /v2/provider/certificate/inspect`
- `PUT /v2/provider/certificate`
