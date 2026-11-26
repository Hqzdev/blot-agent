# `CloudGoogleAuthController.java`

Принимает запрос входа с Google ID token и nonce. Передаёт проверку личности и создание сессии в `CloudGoogleAccounts`.

[Исходник: `backend/cloud/src/main/java/dev/blot/cloud/web/CloudGoogleAuthController.java`](../../../../../../../../../backend/cloud/src/main/java/dev/blot/cloud/web/CloudGoogleAuthController.java)

Модуль: [cloud](../../../../../../../README.md). Раздел: [Маршруты облачного API](index.md).

## HTTP-маршруты

- `POST /v1/auth/google/login`
