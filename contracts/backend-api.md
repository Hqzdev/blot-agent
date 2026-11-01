# Blot API v2

Рабочий контракт — `schemaVersion: 2`. Старые маршруты `/projects`, `/runs`, `/tasks`, `/commands` закрыты. Архив исходного контракта находится в `legacy-v1/`; исторические Swift DTO не используются для новых запросов.

## Транспорт и доступ

Встроенный backend использует TLS и сертификат конкретной установки. Mac передаёт сессию через `Authorization: Bearer <token>`. iPhone получает собственную сессию после локального подтверждения сопряжения. Регистрация, пароли, SMTP и ключ модели доступны только через локальный канал Mac; BLE-коннектор не считается таким каналом. Для ручной разработки loopback HTTP допустим, внешние HTTP-запросы отклоняются.

Запись аккаунта, хеши паролей, коды, сессии и секреты сопряжения не доступны через общий records API или snapshot. Принадлежность определяется сессией. Идентификаторы другого владельца возвращают 404.

## Команды

`POST /v2/commands` возвращает HTTP 202 и квитанцию:

```json
{
  "schemaVersion": 2,
  "commandId": "9440ec73-deee-4f19-a10c-31a3880640cc",
  "type": "conversation.send_message",
  "projectId": null,
  "expectedVersion": null,
  "payload": {
    "conversationId": "46a19327-d208-44a6-9e1c-57e131449b03",
    "content": "Привет"
  }
}
```

```json
{
  "commandId": "9440ec73-deee-4f19-a10c-31a3880640cc",
  "decision": "accepted",
  "operationId": "d08226db-3b4a-4a6c-9989-40f0c978e4b8",
  "result": {"id": "d08226db-3b4a-4a6c-9989-40f0c978e4b8"}
}
```

`result` содержит полную созданную/изменённую запись или результат короткой операции. `operationId` — её ID; при создании разговора это ID разговора, при отправке сообщения — ID генерации. Квитанция подтверждает принятие команды. Завершение длительной работы определяется сохранённым состоянием и событиями. Дополнительное поле `hash` в ответе — служебный digest.

Повтор той же команды возвращает сохранённую квитанцию. Изменённое содержимое с прежним ID даёт `duplicate_command_mismatch`. Вся команда, её квитанция и события фиксируются одной транзакцией. Перед повтором нужно сохранить исходные ID и payload. Для изменения существующей записи передаётся её актуальный `expectedVersion` на уровне envelope. После явного удаления ресурса тело ранее выданной квитанции очищается до `{deleted: true, resourceId: ...}`; ID, digest и operationId сохраняются, повтор не исполняет удалённое действие заново.

| type | payload |
| --- | --- |
| project.create | name, repositoryPath; только Mac |
| project.access | id; повторно открыть выбранную папку, только Mac |
| legacy.adopt | sourceProjectId, confirmed: true; явное локальное принятие старой истории |
| project.archive / project.delete | id |
| conversation.create | title; projectId необязателен |
| conversation.update | id, title и/или archived; версия разговора |
| message.delete | id сообщения Work; версия сообщения, нет активной генерации |
| conversation.send_message | conversationId, content; только WORK |
| generation.cancel / generation.retry | id |
| run.create | goal, необязательный tokenBudget; projectId обязателен |
| run.plan.approve / run.pause / run.resume / run.stop / run.accept | id |
| run.steer | id, goal |
| tool.reconcile / tool.abandon | id операции инструмента; abandon фиксирует явный отказ от неизвестного результата, Git исключён |
| task.retry | id; неизвестные операции блокируют повтор |
| memory.save | id (null при создании), data: scope, scopeId, content, sourceId, status |
| memory.delete | id |
| provider.settings | model, contextTokens, outputTokens, runTokenBudget |
| profile.save | id, data: role, instruction, settings, tools, maxTurns |
| device.pair | {} |
| device.approve / device.revoke | id |
| permission.grant | id подготовленного действия, seconds, uses: 1 |
| permission.deny | id подготовленного действия |
| permission.revoke | id выданного разрешения |
| user.answer | id вопроса, answer; допускается собственный текст |
| budget.increase | id, limit |
| skill.save | id, data: name, instruction, roles, enabled |
| skill.delete / automation.delete | id |
| automation.save | id, data: name, goal, timezone, localTime, weekdays (1–7), enabled, tokenBudget; projectId обязателен |
| automation.run_now | id расписания и его expectedVersion; создаёт обычный запуск с заданным бюджетом |
| git.prepare_commit | runId, arguments: {message} |
| git.prepare_push | runId, arguments: {remote, refspec} |
| git.execute | id подготовленного действия; нужно отдельное permission.grant |
| git.reconcile | id операции; сверка выполняется асинхронно |

Профили могут сужать инструменты роли. Названия функций и исходные инструкции возвращает `GET /v2/roles`. `AGENT_CONFIGURATION` сохраняет неизменяемую конфигурацию сессии. Дочерние Motes ограничены возможностями родителя и не создают своих Motes.

План содержит `requirements: [{key, content}]`, `coverage: [{requirementKey, taskKeys}]` и `steps`. Каждый объявленный ключ требования должен иметь непустое покрытие существующими задачами. После принятия плана checkpoint `requirement_coverage` связывает требования с настоящими taskId.

Очередь `MODEL_REQUEST` хранит назначение, приоритет 0, состояние, владельца и usage. Генерация одного личного доступа сериализуется даже при одинаковом ключе у двух локальных аккаунтов. Незавершённые модельные запросы после перезапуска получают INTERRUPTED; продолжение запуска создаёт новый проверяемый шаг.

История расписания — `CHECKPOINT` с `parentId` расписания и `data.phase: automation_run`. Запись содержит настоящий `runId`, `startedAt` и `manual`; периодическое срабатывание также содержит `scheduledAt`, `commandId` и признак объединения пропусков. Ошибка срабатывания сохраняет `error`. Ручной запуск не переносит следующее плановое время. Отключение периодического планировщика через конфигурацию не закрывает API навыков и расписаний.

## Чтение и события

| Route | Результат |
| --- | --- |
| GET /health, /ready | состояние процесса / доступность хранилища |
| GET /v2/compatibility | версия и зарегистрированные команды |
| GET /v2/commands/{id} | сохранённая квитанция |
| GET /v2/records/{KIND}?projectId=&parentId=&limit=100&offset=0 | страница записей; limit 1–500 |
| GET /v2/records/{KIND}/{id} | запись владельца |
| GET /v2/snapshot | записи, watermark и nextCursors; большие группы дочитываются страницами |
| GET /v2/legacy/projects?offset=0 | ещё не принятые старые проекты, только Mac |
| GET /v2/events?after=0 | SSE, событие `project`, seq строкой |
| GET /v2/roles | инструкции и инструменты ролей |
| GET /v2/provider/models | настоящие модели подключённого GigaChat |
| GET /v2/projects/{id}/export | история и метаданные проекта |
| GET /v2/projects/{id}/export.zip | манифест и фактические артефакты в ZIP |
| GET /v2/artifacts/{id}/content?offset=0&length=262144 | бинарное содержимое; length до 1 MiB |
| GET /v2/diagnostics | метаданные без промптов и секретов |
| GET /v2/statistics?projectId= | фактические токены, состояния задач/запусков, ревью и замечания |
| GET /v2/devices/pairings | безопасные сведения о сопряжении, только Mac |
| GET /v2/pairing/{id}/ticket | одноразовый секрет для QR, только владелец на Mac |

Для последовательной загрузки используйте `cursor` вместо `offset`. Это base64url без padding от UTF-8 строки `createdAt + "\n" + id`, ID в нижнем регистре. Позиция не сдвигается при удалении более ранней записи. `snapshot.nextCursors` содержит продолжение после первых 500 записей; `nextOffsets` сохранён для совместимости. После дочитывания клиент применяет события от watermark, сверяя версии и перечитывая затронутые ID. Swift `BackendSynchronization` восстанавливает SSE после обрыва; при `replay_unavailable` получает новый snapshot. Номер не обязан увеличиваться ровно на единицу.

Entity: `id, ownerId, projectId, parentId, version, createdAt, updatedAt, data`. Даты — UTC ISO 8601. Неизменяемые артефакты имеют SHA-256. События содержат ID/версию записи: клиент читает актуальные данные через GET. Глобальные номера могут иметь промежутки из-за других аккаунтов; числовую непрерывность клиент не проверяет. Курсор означает последнюю обработанную запись. История исходных сообщений при сжатии не удаляется.

`statistics.knownInputTokens` и `knownOutputTokens` суммируют только подтверждённый usage. `requestsWithUnknownUsage` считает завершённые/прерванные запросы без полного usage; ожидающие и активные запросы показаны отдельно. `usageIncomplete` учитывает также неизвестный расход попыток в бюджете. Цена `costMinorUnits` и `currency` равна null: подтверждённый тариф не настроен.

`project.delete` создаёт постоянные задания `WORKSPACE_CLEANUP`. Файловые операции выполняются после транзакции и повторяются при сбое. Они удаляют только служебные worktree заданного запуска; исходная папка, её несохранённые файлы и ветки сохраняются. Пока готовится рабочая область, удаление проекта отклоняется. Очередь и причина повторения доступны владельцу через records; после очистки приходит `workspace.removed`.

## Аккаунты и настройки

| Route | JSON |
| --- | --- |
| POST /v2/auth/register | email, password, name |
| POST /v2/auth/verify | email, code |
| POST /v2/auth/resend | email |
| POST /v2/auth/login | email, password, remember |
| POST /v2/auth/logout | {} и действующая сессия |
| GET /v2/auth/me | безопасные сведения аккаунта |
| POST /v2/auth/password/request | email |
| POST /v2/auth/password/reset | email, code, password |
| PUT /v2/setup/smtp | host, port, username, password, from; только Mac |
| GET /v2/setup/status | Режим настроек владельца: emailManaged, providerManaged и публичные modelSettings; без секретов |
| PUT /v2/provider/key | key; только Mac, нет активного/ожидающего модельного запроса |
| POST /v2/provider/certificate/inspect | pem; метаданные и SHA-256 выбранного CA, только Mac |
| PUT /v2/provider/certificate | pem; доверие выбранному CA только для GigaChat этого аккаунта |
| GET /v2/provider/certificate | метаданные настроенного CA, только Mac |
| POST /v2/pairing/request | id, secret, name, platform |
| POST /v2/pairing/claim | id, secret; после подтверждения на Mac |

Код: 6 цифр, 10 минут, 5 попыток, повтор через 60 секунд. Пароль: 12–128 символов, Argon2id. Сессия: 12 часов или 30 дней. Восстановление отозвает старые сессии. Ключи не передаются через журнал команд. Настройка CA не добавляет сертификат в системное хранилище. Имя TLS-сервера продолжает проверяться.

Ошибки: `code, message, details`. Основные HTTP статусы: 400 формат/правила, 401 сессия, 403 область/разрешение, 404 запись, 409 версия/повтор/состояние, 422 контекст/ответ модели, 429 бюджет/лимит, 503 внешняя система или неподготовленная VM. Частичный ответ хранится отдельно от статуса генерации и не означает COMPLETED.

## Выполнение команд в VM

Выбранная владельцем архитектура: Apple Virtualization.framework. Настройка — раздел Environments на Mac. Гостевой runner и установка описаны в `docs/architecture/virtual-machine-runner.md`. До подготовки образа process_run завершится явной ошибкой. Подмена запуском произвольного кода на основном Mac отсутствует.

Старые записи v1 не открываются новому аккаунту автоматически. `legacy.adopt` сохраняет их исходную историю неизменяемым артефактом `application/vnd.blot.legacy+json` и создаёт проект v2; прежние статусы не запускают новых агентов. Один исходный проект нельзя одновременно принять в два аккаунта.

Актуальные результаты проверок и оставшиеся работы: `docs/backend-implementation-progress.md`.
