# Вход через общую страницу сайта

Уточнено пользователем 4 ноября 2026: `https://blot-agent.vercel.app/login` — единая страница входа и регистрации на Mac/iPhone. Синхронизация выполняется напрямую по Wi-Fi/Bluetooth; сайт не является relay истории и не исполняет агента. SMTP нужен серверному обработчику сайта. SMTP-пароль не передаётся приложениям, браузерному JavaScript или в callback.

Последующее уточнение того же дня: аккаунты, чаты и проекты сохраняются в PostgreSQL через Vercel. С `DATABASE_URL` сайт исполняет account API сам; отдельный Java-хост не требуется. `WorkspaceCloudBackup` дополнительно передаёт снимки данных через `/v1/workspace/backups`. Прямой peer transport и локальное исполнение агента сохраняются. Подробности, ограничения хранения и серверная конфигурация: `landing/lib/auth/README.md`.

В `.env` Apple-сборок задан `BLOT_AUTH_URL`. API аккаунтов по умолчанию находится на том же HTTPS origin. Если обработчик размещён на другом origin, перед сборкой указывается `BLOT_ACCOUNT_SERVICE_URL`. Это адрес только аутентификации. Приложение не запрашивает эти значения у установленного пользователя.

## Запрос приложения

Системный `ASWebAuthenticationSession` открывает `/login` с параметрами:

```text
response_type=code
client_id=blot-ios | blot-macos
redirect_uri=blot-agent-ios:/oauth/account | blot-agent-macos:/oauth/account
state=<случайные 32 байта, base64url>
code_challenge=<base64url(SHA256(code_verifier))>
code_challenge_method=S256
intent=login | register
```

Страница сохраняет параметры только на время потока. Разрешены строго две пары client_id/redirect_uri, приведённые выше. Вход/регистрация/подтверждение/восстановление пароля проходят на сайте. После подтверждения почты сайт имеет свою серверную сессию. App verifier существует только в памяти приложения.

## Выдача кода сайтом

В реализованном Java account API:

```http
POST /v1/auth/browser/code
Authorization: Bearer <сессия вошедшего пользователя сайта>
Content-Type: application/json

{"clientID":"blot-ios","redirectURI":"blot-agent-ios:/oauth/account","codeChallenge":"<из запроса приложения>"}
```

Ответ: `{"code":"<43 символа base64url>","expiresAt":"<ISO-8601>"}`. Сервер хранит только хеш кода, идентификаторы native client и browser session, точный callback, PKCE challenge и срок 60 секунд. Выход на сайте отзывает связанные ещё не использованные коды. Страница возвращает управление по точному разрешённому адресу:

```text
blot-agent-ios:/oauth/account?code=<одноразовый код>&state=<исходный state>
```

Токены аккаунта никогда не помещаются в URL. Веб-реализация может использовать HttpOnly cookie вместо Bearer между страницей и собственным обработчиком, сохранив внешний native-контракт. При размещении обработчика на Vercel нужно постоянное транзакционное хранилище аккаунтов/сессий/кодов; память процесса и файл `/tmp` для этого не подходят.

## Обмен в приложении

```http
POST /v1/auth/browser/token
Content-Type: application/json

{"code":"<code>","codeVerifier":"<секрет приложения>","clientID":"blot-ios","redirectURI":"blot-agent-ios:/oauth/account"}
```

Сервер проверяет client/callback, срок, подтверждённый аккаунт, активность browser session и S256 verifier. Удаление кода и создание отдельной сессии приложения — одна транзакция. Повтор кода отклоняется. Ответ:

```json
{
  "sessionID": "<UUID>",
  "accessToken": "<opaque bearer token>",
  "refreshToken": "<opaque rotating token>",
  "expiresAt": "<ISO-8601>",
  "ownerID": "<UUID>",
  "workspaceID": "<UUID>",
  "deviceID": null,
  "bootstrapAllowed": true
}
```

`ownerID` и `workspaceID` постоянны для аккаунта. `deviceID` связывается с локально созданными ключами через сопряжение, а не переносится из URL. Сессию приложение хранит в ThisDeviceOnly Keychain. Последующие методы: `POST /v1/auth/refresh {refreshToken}`, `GET /v1/auth/me`, `POST /v1/auth/logout` с Bearer. Все ответы без кеширования; логи без body, code, verifier и токенов.

## Статус

Swift-клиент браузерного входа, callback/state/PKCE, Java выдача/обмен и миграция SQLite реализованы. На последней проверке `/login` отвечает 200, а `/v1/auth/me` — 503 `auth_service_unconfigured`. Native query/callback совпадают с опубликованной страницей. Наличие HTML само по себе не подтверждает работающие регистрацию, письма и обмен кода. Развёртывание сайта и настоящая сквозная приёмка ещё должны быть проверены. Не заменять их моком или локальным обходом авторизации.
