# `SecretController.java`

Принимает настройки ключа модельного провайдера и SMTP, а также выдаёт список доступных моделей. Делегирует хранение секретов серверным адаптерам.

[Исходник: `backend/api/src/main/java/dev/blot/api/workspace/security/SecretController.java`](../../../../../../../../../../backend/api/src/main/java/dev/blot/api/workspace/security/SecretController.java)

Модуль: [api](../../../../../../../../README.md). Раздел: [Транспорт и секреты](index.md).

## HTTP-маршруты

- `PUT /v2/provider/key`
- `GET /v2/provider/models`
- `PUT /v2/setup/smtp`

## Связанные файлы

- [ConfiguredSecretStore](../../../../../../../../../infrastructure/src/main/java/dev/blot/infrastructure/workspace/security/ConfiguredSecretStore.java.md)
- [InstallationConfiguration](../installation/InstallationConfiguration.java.md)
