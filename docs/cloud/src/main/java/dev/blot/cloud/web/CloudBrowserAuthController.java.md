# `CloudBrowserAuthController.java`

Обрабатывает выдачу и обмен одноразового кода для браузерного входа. Применяет ограничения HTTP-границы и передаёт проверку PKCE в сервис авторизации.

[Исходник: `backend/cloud/src/main/java/dev/blot/cloud/web/CloudBrowserAuthController.java`](../../../../../../../../../backend/cloud/src/main/java/dev/blot/cloud/web/CloudBrowserAuthController.java)

Модуль: [cloud](../../../../../../../README.md). Раздел: [Маршруты облачного API](index.md).

## HTTP-маршруты

- `POST /v1/auth/browser/code`
- `POST /v1/auth/browser/token`
