# Регистрация Google OAuth для Apple v1

Статус: реальные клиенты ещё не зарегистрированы. В репозитории Google OAuth выключен (`apps/shared/Resources/GoogleOAuth.plist`). Скрипт и PKCE/token-клиент подготовлены; наличие конфигурации не означает успешного подключения Gmail/Calendar. Токены нельзя помещать в этот файл, общую базу, fixtures или серверную очередь.

## 1. Google Cloud

1. Создать отдельный Google Cloud project для разработки. В API Library включить **Gmail API** и **Google Calendar API**.
2. В Google Auth Platform → Branding указать имя Blot, support email, developer contact, действующие страницы приложения и privacy policy. Использовать свои подтверждённые домены.
3. В Audience выбрать Internal только для собственного Workspace-домена; для обычных Gmail-аккаунтов — External. Начать с Testing, добавить конкретные тестовые ящики в Test users.
4. В Data Access добавить только области операций из таблицы ниже. Для опубликованного приложения Google может потребовать verification; Gmail readonly/compose относятся к restricted scopes. Проверить применимость проверки безопасности к фактическому способу обработки данных перед публикацией. В Testing повторная авторизация может требоваться чаще; это не доказательство ошибки синхронизации.

Официальные источники: [consent screen](https://developers.google.com/workspace/guides/configure-oauth-consent), [области Gmail](https://developers.google.com/workspace/gmail/api/auth/scopes), [области Calendar](https://developers.google.com/workspace/calendar/api/auth).

## 2. Два нативных клиента

В Clients → Create client создать **два** OAuth client ID. Для Apple-клиентов Google указывает тип **iOS**, в том числе для macOS. Использовать точный bundle ID из Xcode, а не имя приложения. [Инструкция Google для iOS/macOS](https://developers.google.com/identity/sign-in/ios/start-integrating).

| Клиент | Application type | Bundle ID |
|---|---|---|
| Blot iOS Development | iOS | `yaroslavstrelkov.blot-agent.ios` |
| Blot macOS Development | iOS | `yaroslavstrelkov.blot-agent` |

Если Google Console предлагает проверку владения приложением / Team ID, указать собственную команду подписи. Проверить настройки custom URL scheme для каждого клиента. Сохранить выданные **client ID**. Нативный PKCE-клиент не использует client secret. Web application client и серверный callback для этого прямого доступа к Gmail/Calendar не нужны: аккаунт Blot имеет отдельный вход.

Redirect URI строится так: перевернуть части client ID, разделённые точками, и добавить `:/oauthredirect`. Например, для синтетического `123456-demo.apps.googleusercontent.com` это `com.googleusercontent.apps.123456-demo:/oauthredirect`. Этот пример не рабочий ID. Один слеш после двоеточия обязателен. [Native OAuth: PKCE и redirect](https://developers.google.com/identity/protocols/oauth2/native-app).

## 3. Записать реальные публичные ID в проект

Из корня проекта выполнить, заменив значения собственными зарегистрированными ID:

```sh
python3 scripts/configure-google-oauth.py \
  --ios-client-id "$BLOT_GOOGLE_IOS_CLIENT_ID" \
  --macos-client-id "$BLOT_GOOGLE_MACOS_CLIENT_ID"
python3 scripts/configure-google-oauth.py --check
```

Скрипт запишет публичные ID, bundle IDs и redirect URI в `apps/shared/Resources/GoogleOAuth.plist`, добавит управляемую запись `dev.blot.google-oauth` в URL Types `apps/BackendInfo.plist`, сохранив другие записи. Оба targets включают shared resources. Приложение выбирает конфигурацию своей платформы и проверяет bundle ID. Повторный запуск скрипта заменяет только его запись URL Types. Для выключения: `python3 scripts/configure-google-oauth.py --disable`.

В новой конфигурации сборки или при смене bundle ID сначала зарегистрировать соответствующие клиенты в Google; синхронно изменить BUNDLES в скрипте. Для release рекомендуется отдельный Cloud project с отдельным набором зарегистрированных клиентов и разрешёнными пользователями.

## 4. Области по операциям

| Операция | OAuth scope suffix после `https://www.googleapis.com/auth/` |
|---|---|
| Поиск и чтение Gmail | `gmail.readonly` |
| Создание/редактирование черновиков Gmail | `gmail.compose` (Google также разрешает отправку; приложение всё равно требует подтверждение) |
| Только отправка Gmail | `gmail.send` |
| Список календарей | `calendar.calendarlist.readonly` |
| Чтение событий | `calendar.events.readonly` |
| Создание, изменение, удаление событий | `calendar.events` |
| Занятость | `calendar.freebusy` |

PKCE-запрос также включает `openid email` для идентификации выбранного Google-аккаунта. При расширении операций нужно запрашивать полный необходимый набор, включая уже используемые области: на incremental authorization installed apps полагаться нельзя. Не запрашивать `mail.google.com`, полный Calendar, Drive или domain-wide delegation для этих сценариев.

## 5. Проверка на Mac и iPhone

- Подписанные сборки открывают системное окно авторизации, выбирают тестовый аккаунт и возвращаются в приложение своей платформы.
- Отмена, несовпавший state, повторённый state/code, другая схема/path и redirect mismatch не создают подключение.
- Подключить два тестовых ящика. Перезапустить приложение, проверить обновление access token. Refresh token остаётся в Keychain текущего устройства с `ThisDeviceOnly`; Google subject и список доступных операций — в локальной записи подключения.
- Второе устройство получает только метаданные и показывает необходимость своего входа. Секретов в экспортированной базе и relay нет.
- Выполнить чтение Gmail, реальный черновик, подтверждённую отправку, чтение/создание/изменение/удаление события в тестовом календаре. Записать внешние IDs в acceptance; не сохранять токены и содержимое личной почты в журнал проверки.
- Изменение адресатов/текста/вложений/времени после подготовки сбрасывает подтверждение. Потеря ответа отправки оставляет UNKNOWN и требует сверки, а не повторного POST.
- Отозвать доступ в Google Account, увидеть необходимость нового подключения, пройти вход заново.

На текущем этапе этот список **не пройден**. Зарегистрированные ID снимают только конфигурационную зависимость; интеграционные проверки остаются обязательными.
