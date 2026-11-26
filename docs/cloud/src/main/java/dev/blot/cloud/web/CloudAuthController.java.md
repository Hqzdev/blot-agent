# `CloudAuthController.java`

Предоставляет облачные маршруты регистрации, входа, восстановления пароля, управления сессией, привязки устройства и удаления аккаунта. Делегирует работу службам облачной идентификации.

[Исходник: `backend/cloud/src/main/java/dev/blot/cloud/web/CloudAuthController.java`](../../../../../../../../../backend/cloud/src/main/java/dev/blot/cloud/web/CloudAuthController.java)

Модуль: [cloud](../../../../../../../README.md). Раздел: [Маршруты облачного API](index.md).

## HTTP-маршруты

- `POST /v1/auth/register`
- `POST /v1/auth/verify`
- `POST /v1/auth/login`
- `POST /v1/auth/password/request`
- `POST /v1/auth/password/reset`
- `POST /v1/auth/refresh`
- `GET /v1/auth/me`
- `POST /v1/auth/device-challenge`
- `POST /v1/auth/device-bind`
- `POST /v1/auth/account/delete/request`
- `POST /v1/auth/account/delete`
- `POST /v1/auth/logout`
- `POST /v1/auth/revoke-sessions`
