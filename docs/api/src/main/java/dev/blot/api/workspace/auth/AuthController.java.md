# `AuthController.java`

Реализует локальную авторизацию v2: регистрацию, проверку почты, вход, выход и восстановление пароля. Передаёт правила аккаунтов и сессий прикладным сервисам.

[Исходник: `backend/api/src/main/java/dev/blot/api/workspace/auth/AuthController.java`](../../../../../../../../../../backend/api/src/main/java/dev/blot/api/workspace/auth/AuthController.java)

Модуль: [api](../../../../../../../../README.md). Раздел: [Локальный вход](index.md).

## HTTP-маршруты

- `POST /v2/auth/register`
- `POST /v2/auth/verify`
- `POST /v2/auth/resend`
- `POST /v2/auth/login`
- `POST /v2/auth/logout`
- `GET /v2/auth/me`
- `POST /v2/auth/password/request`
- `POST /v2/auth/password/reset`

## Связанные файлы

- [AccountService](../../../../../../../../../application/src/main/java/dev/blot/application/workspace/identity/AccountService.java.md)
- [EmailChallengeService](../../../../../../../../../application/src/main/java/dev/blot/application/workspace/identity/EmailChallengeService.java.md)
- [SessionService](../../../../../../../../../application/src/main/java/dev/blot/application/workspace/conversation/SessionService.java.md)
