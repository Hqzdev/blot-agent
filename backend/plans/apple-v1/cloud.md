# Отдельный сервер Apple v1

`backend/cloud` — самостоятельный Spring Boot-процесс, `dev.blot.cloud.CloudServer`. Он зависит от общих ports/infrastructure, но не от `:api`; component scan ограничен `dev.blot.cloud`. Старые desktop HTTP controllers и agent workers в этом процессе не запускаются.

Сейчас реализованы аккаунты с Argon2id и email-кодом, поворот access/refresh sessions, доказательство ключа устройства, подтверждённое сопряжение, подписанный отзыв с новым epoch, ciphertext relay с receipt/ACK/TTL, хранилище зашифрованных chunks, поколения полномочий исполнителя и шлюз текстового GigaChat с дневной квотой. Это компонентный сервер; native keyring/ECDH/цепочка доверия и files проверены HTTP harness; account/pairing UI, композиция snapshot/cloud в приложениях ещё не завершена. Физическая приёмка не пройдена.

## Локальная сборка и запуск

Из корня проекта, с JDK 25:

```sh
backend/gradlew -p backend :cloud:test :cloud:bootJar
java --enable-native-access=ALL-UNNAMED -jar backend/cloud/build/libs/blot-cloud.jar
```

Перед запуском требуется постоянный ключ HMAC для email-кодов: файл с base64 от не менее 32 случайных байтов; путь задаётся `BLOT_CLOUD_CHALLENGE_KEY_FILE`. Сгенерировать его один раз через `openssl rand -base64 32`, хранить вне репозитория с ограниченными правами. Смена этого ключа делает ранее выданные email-коды непригодными. Содержимое файла не выводить в логи или чат.

По умолчанию HTTP слушает только `127.0.0.1:8081`, база — `./data/cloud.sqlite`, health — `GET /v1/health`. Настройки:

| Переменная | Назначение |
|---|---|
| `BLOT_CLOUD_ADDRESS`, `BLOT_CLOUD_PORT` | bind и port |
| `BLOT_CLOUD_DATABASE` | отдельная серверная SQLite DB |
| `BLOT_CLOUD_CHALLENGE_KEY_FILE` | постоянный base64 HMAC key |
| `BLOT_CLOUD_RELAY_BYTES` | предел ciphertext relay workspace; по умолчанию 536870912 байт |
| `BLOT_CLOUD_DAILY_TOKENS` | дневной UTC-лимит GigaChat на аккаунт; по умолчанию 20000 |
| `BLOT_GIGACHAT_CREDENTIALS_FILE` | Basic authorization key встроенного GigaChat |
| `BLOT_GIGACHAT_CA_FILE` | необязательный PEM доверенного CA для GigaChat; TLS hostname verification сохраняется |
| `BLOT_SMTP_HOST`, `BLOT_SMTP_PORT` | SMTP host, порт 587 STARTTLS либо 465 implicit TLS |
| `BLOT_SMTP_USERNAME`, `BLOT_SMTP_FROM` | SMTP login и подтверждённый sender |
| `BLOT_SMTP_PASSWORD_FILE` | SMTP password |

Для каждой переменной секрета поддерживается значение напрямую без `_FILE` для временного тестового процесса; в развёртывании использовать файлы. SMTP/GigaChat не подменяются демо-ответами: при отсутствии конфигурации соответствующий запрос возвращает ошибку. Подключение Gmail/Calendar имеет отдельные нативные OAuth clients и не использует SMTP сервера.

## Контейнер и TLS

`backend/cloud/Dockerfile` собирается из корня: `docker build -f backend/cloud/Dockerfile .`. `backend/cloud/deploy/compose.yaml` содержит single-node профиль с именованным томом SQLite, non-root процессом, read-only root filesystem, tmpfs и секретами. В каталоге `BLOT_CLOUD_SECRETS_DIR` заранее подготовить `challenge-key`, `gigachat-credentials`, `smtp-password`; задать SMTP-переменные. File-backed Compose secrets должны быть доступны на чтение UID/GID 10001 процесса контейнера; ограничьте доступ на хосте owner/group или ACL. Настройки uid/mode в Compose не заменяют права bind-mounted файла. Затем `docker compose -f backend/cloud/deploy/compose.yaml up --build -d`.

Для публичного окружения нужен собственный DNS/TLS endpoint. Пример `backend/cloud/deploy/Caddyfile` рассчитан на Caddy на том же хосте, `BLOT_CLOUD_DOMAIN` — реальный домен оператора. Relay port остаётся loopback. Proxy не должен сохранять Authorization, тела запросов/ответов, email-коды, model context или SSE. До выбора хоста/домена и настройки секретов публичное развёртывание не выполнено. Compose configuration проверена с синтетическими файлами секретов (`.build/apple-v1-compose-check.log`). Docker daemon недоступен; образ/контейнер/proxy не запускались, контейнерная приёмка остаётся отдельной проверкой.

SQLite WAL требует одного server instance с локальным постоянным диском; несколько replicas процесса над одним файлом в сетевом volume не поддерживаются этим профилем. Резервную копию делать SQLite backup API или `VACUUM INTO` при согласованном состоянии, а не копированием одного `.sqlite` без WAL. Бэкап сервера не содержит ключей расшифровки истории. Восстановление пароля восстанавливает аккаунт; история требует доверенного устройства и его ключей.

## Протокол HTTP

Все JSON API используют `/v1`, Authorization `Bearer` с access token. HTTPS обязателен для клиентской конфигурации; явное разрешение loopback HTTP применяется только интеграционным harness. Swift-клиент не следует redirects. Ошибки содержат только `code`, без тела запроса, SQL, токенов и stacktrace. Лимит HTTP body — 1 MiB.

| Группа | Методы |
|---|---|
| Account/session | `POST auth/register`, `auth/verify`, `auth/login`, `auth/refresh`, `auth/password/request`, `auth/password/reset`, `auth/logout`, `auth/revoke-sessions`; `GET auth/me` |
| Device proof | `POST auth/device-challenge`, `auth/device-bind`, `devices/bootstrap` |
| Pairing | `POST devices/pairings`, `devices/pairings/claim`, `devices/pairings/approve`; `GET devices/pairings/{id}`, `devices/pairings/{id}/result` |
| Device trust | `GET devices`, `devices/keys?afterEpoch=`; `POST devices/revoke` |
| Relay | `POST relay/changes`; `GET relay/changes?after=&limit=`, `relay/changes/{id}/receipt`; `POST relay/ack` |
| Snapshot | `POST relay/snapshots`, `relay/snapshots/offers`; `GET relay/snapshots`, `relay/snapshots/{id}` |
| Encrypted files | `PUT relay/blobs`; `GET relay/blobs/{id}/{index}` |
| Executor | `POST execution/tasks`, `execution/acquire`, `execution/renew`, `execution/check`, `execution/release`, `execution/cancel`, `execution/actions/begin`, `execution/actions/finish` |
| Model | `POST model/chat/completions`; `GET model/usage` |

Точные request/response типы находятся в `backend/cloud/.../web` и соответствующих services; encrypted packet/batch совпадают со Swift Codable. Полный cloud OpenAPI и schema fixtures для account/pairing ещё требуются; v3 entity schemas не заменяют этот API-контракт.

Первый email-verify даёт одноразовое право зарегистрировать первый signing/encryption public key. Password login сам по себе не выдаёт доступ к истории. Существующее устройство доказывает владение ключом через session-bound nonce; новое требует подписи владельца при QR pairing. Сервер получает только wrapped workspace keys. После revoke новые sessions/deliveries/leases запрещены, epoch увеличен, новым ключом снабжаются только оставшиеся устройства. Новое сопряжение и отзыв требуют подписанного точного manifest, сервер не генерирует групповой ключ.

Relay хранит ciphertext до 30 дней. Минимальные receipt IDs/digests/origin counters остаются для предотвращения дублей и повторного использования sequence; они не содержат историю. Pull ниже retention floor возвращает `replay_unavailable`; нужен согласованный снимок от доверенного устройства. Серверная очередь snapshot-запросов и подписанные предложения/блочная передача реализованы; native core ждёт донора, возобновляет загрузку, устанавливает снимок и получает tail. Подключение этого flow к UI ещё требуется. ACK монотонен и принимается после локального SQLite commit. Сервер не может проверить смысл зашифрованной записи.

Полномочие на 90 секунд привязано к task, явно назначенному device, holder процесса и generation. Одновременно максимум четыре действующих полномочия на workspace; глубина дочерних задач ≤2. Истёкшее поколение не выполняет tools. RUNNING/UNKNOWN внешнее действие требует сверки перед новым acquire. Cancel родителя отменяет всю сохранённую ветку.

Модельный шлюз обрабатывает выбранный контекст в памяти и сохраняет только request ID, reserved/actual usage, состояние и время. Повтор того же generation request ID не запускает генерацию заново. Неизвестное фактическое usage сохраняет консервативный резерв. Текстовый SSE завершён только после `finish_reason=stop` и `[DONE]`; оборванный поток остаётся прерванным. Реальный GigaChat в этом окружении пока не проверен.

## Доказательства

- `:cloud:test`: десять сценариев на настоящих SQLite, Argon2id и Java JCE P256. SMTP заменён capturing mailbox; это не приёмка email-доставки.
- `python3 scripts/check-apple-cloud-wire.py`: поднимает отдельный JAR на случайном loopback port, создаёт три изолированные Swift SQLite copies, проверяет настоящий CryptoKit → HTTP → Java JCE → CryptoKit путь, раздельные изменения, дедупликацию, chained owner-approved pairing/ECDH, revoke/epoch/lease fencing, encrypted multi-chunk файлы и snapshot bootstrap/resume/tail с сохранением pending данных, поворот session/конкурентный выход и отсутствие plaintext/token в relay DB/log. Для сетевого harness требуется разрешение среды на localhost.
- Harness засевает только временный verified test account и три unbound sessions в свою DB. Устройства, public keys, pairing и revoke создаёт нативный Swift-клиент через HTTP. Секреты устройств остаются в injected credential stores процесса. Это проверка native core/wire, а не регистрация/QR UI или SMTP. Дополнительный физический прогон общего ядра и настоящего Keychain выполняется отдельным signed iPhone host; он также не заменяет приёмку product UI. Логи и краткий результат — `.build/apple-v1-cloud-wire*.log`, `.build/apple-v1-cloud-wire-evidence.json`.
