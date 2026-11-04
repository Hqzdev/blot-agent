# Контракты, команды и синхронизация Apple v1

**Проектируемое дополнение 4 ноября:** системные providers, device-local привязки EventKit, PreparedSystemAction, SystemInvocation и состояния передачи описаны в [native-integrations.md, разделы 3–5](native-integrations.md#3-архитектура-и-ответственность). Это требования к следующему изменению `contracts/v3/model.json`, ещё не сгенерированные DTO. Google REST отложен; системные действия выполняются только выбранным устройством, peer sync результата не запускает их повторно.

Источник wire-моделей: `contracts/v3/model.json`. Генератор `scripts/generate-v3-contracts.py` выпускает Java records, Swift DTO, JSON Schema и общие fixtures. Редактировать сгенерированные модели вручную нельзя. Модели — контракт данных; наличие DTO не означает наличие HTTP-маршрута, работающей репликации или серверной проверки прав.

## Изменение границ v3

Workspace теперь общий, а не рабочая область одного исполнителя. `Workspace.executorDeviceId` оставлен nullable для чтения старых тестовых данных, но не является полномочием на исполнение. `Conversation.mobileOwned` сохраняется для совместимости представления; он также не определяет права. Старые v2 API и данные не переиспользуются автоматически.

Задача имеет явные `execution.executorDeviceId`, `originDeviceId`, `taskId`, configuration revision и `leaseGeneration`. Поколение относится к конкретной задаче, растёт при новом полномочии, проверяется перед каждым шагом и внешним действием. Сервер определяет account/device из сессии, проверяет доверие и выдаёт lease. История синхронизируется независимо от назначения исполнителя. Истёкший lease останавливает новые шаги; начатое внешнее действие проходит сверку. Для desktop-only инструментов запрет ПК → другой ПК сохраняется; они отложены.

Добавления к существующим DTO nullable, чтобы текущие fixtures и demo продолжали декодироваться. Новые записи рабочего ядра явно заполняют поддерживаемые поля. Это совместимость внутри ещё не выпущенного v3, не поддержка старого клиента в новой рабочей среде. Перед выпуском capability/version handshake отклоняет клиент без необходимых возможностей.

| Данные | Добавлено / назначение | Где обеспечивается поведение |
| --- | --- | --- |
| Conversation | `kind: DIRECT/GROUP`; отдельный ConversationParticipant с kind USER/AGENT, participantID и removed | Core group/participant commands, проверка membership и stable member IDs |
| Message | authorAgentId, replyToMessageId, mentions с agentID/startUTF16/lengthUTF16, Lamport position, executorDeviceId; WAITING_CONNECTION/INTERRUPTED | Send проверяет source, UTF16 границы и membership; recorder восстанавливает только поток своего executor; coordinator runtime ещё требуется |
| MessageReaction | messageID + participantID + emoji + removed | Составной логический ключ, remove-dominant concurrent merge |
| ConversationReadPosition | participantID, messageID и монотонная позиция | max `(position,messageID)` в разговоре, без отката после merge |
| Skill / SkillRevision | activeRevisionID, инструкции, parametersJSON, toolIDs | Immutable revisions/typed string parameters; task фиксирует skillRevisionID, runtime ещё требуется |
| Task | configurationID, parentTaskID, skillRevisionID, budgetTokenLimit | Snapshot конфигурации, дерево ≤2, общий root budget/cancel |
| ExecutionLease | taskID, executorDeviceID, generation, expiresAt, state | Cloud lease API: device + process holder + generation, TTL 90s, UNKNOWN fencing |
| PreparedAction | preparationID и canonical content digest | Переподготовка отзывает grants; digest проверяется против actual fields перед approve/begin |
| Artifact | execution nullable для выбранных пассивных файлов, encryptionEpoch | Импорт не создаёт фиктивную task/execution; file bytes отдельно от records |
| Connection | deviceID без токенов | Статус может быть общим, доступность и секрет локальны |
| Automation | scheduledAt для разового запуска, skillRevisionID, maxCatchUpRuns | DST-aware calculator, unique scheduled/manual run и durable task enqueue |
| RecordChange | originDeviceID, sequence, baseVersion, recordVersion, operation, payloadJSON | Переносится внутри шифрованного envelope; транспорт далее |
| RecordTombstone | kind/id, deletedByDeviceID, deletedAt | SQLite и replica/snapshot merge запрещают возврат удалённого ID |
| ReplicationCheckpoint | deviceID, streamID, sequence, state | Внутренний replica cursor фиксируется вместе с inbox/apply, ACK после commit |
| ConflictingRevision | baseVersion, originDeviceID, payloadJSON, resolved | Сохранены обе версии; explicit conflict.resolve, shared UI и запрет новых запусков до выбора |

## Команды

Envelope v3 содержит schemaVersion, commandID, workspaceID, type, expectedVersion, expiresAt, payload. Digest считается по каноническому JSON команды, включая type, workspace и содержимое. Идентификатор устройства в payload не является доказательством отправителя.

| Семейство | Команды | Результат | Ошибки |
| --- | --- | --- | --- |
| Чат | conversation.create/send_message/update/delete, reaction.set/remove, conversation.read | Receipt + долговечные записи/outbox | COMMAND_CONFLICT, VERSION_CONFLICT, RECORD_DELETED, MISSING_CONVERSATION |
| Генерация | generation.start/cancel/retry | Одна assistant-запись на попытку; отдельные text/status updates | MODEL_UNAVAILABLE, NETWORK, INTERRUPTED, LIMIT |
| Группы | group.create, participants.set, agent.message | Участники/межагентное сообщение и связь с task | SCOPE_DENIED, PARTICIPANT_REMOVED |
| Агенты/задачи | agent.save, task.create/delegate/pause/resume/cancel | Снимок конфигурации, дерево задачи, бюджет | LEASE_STALE, DEVICE_UNAVAILABLE, DEPTH_LIMIT, BUDGET_EXHAUSTED |
| Память/навык | memory.create/update/delete/propose/accept, context.compact, skill.save/run | Источники, версии и инвалидация summaries | SOURCE_MISSING, VERSION_CONFLICT, SCOPE_DENIED |
| Действия | action.prepare/revise, approval.decide/revoke, action.execute/reconcile | Exact digest, grant, invocation, externalID | ACTION_INVALIDATED, APPROVAL_REQUIRED, OPERATION_UNKNOWN |
| Расписание | automation.save/disable/preview/run/fire | AutomationRun с scheduledAt | VERSION_CONFLICT, TIMEZONE_INVALID, EXECUTOR_UNAVAILABLE |
| Доверие/репликация | device.pair/confirm/revoke, sync.bootstrap/push/pull/ack/rebase | Ciphertext envelopes, durable checkpoint | DEVICE_REVOKED, REPLAY_UNAVAILABLE, KEY_EPOCH_REQUIRED |

Core-команды реализованы для разговоров, групп/участников, реакций/прочтения, агентов/configuration snapshots, памяти/кандидатов/summary validation, навыков, файлов, task/cancel/budget, расписаний и exact approvals/invocations. Portable tool runtime, coordinator, Google adapters, общие rules и часть pause/resume отсутствуют. Полные wire command payload schemas/fixtures ещё не покрывают все core API; это отдельная незакрытая задача. Принятие команды не означает завершение задачи.

Одинаковые commandID + содержимое возвращают прежний результат. Другое содержимое с тем же ID отклоняется. Локальный send использует commandID как стабильный messageID; create — как conversationID. Новая явная попытка генерации имеет новый responseID и связь с исходным сообщением. Повтор доставки запроса и новая попытка — разные операции.

## Локальное хранение

`WorkspaceRepository` — actor; `SQLiteDatabase` скрывает handle/statements. `WorkspaceChatService` и `WorkspaceConversationService` проверяют команды; `WorkspaceResponseRecorder` фиксирует дельты до публикации. UI и модельный транспорт не работают с SQL. `CompatibleChatModel` разбирает SSE по завершённым событиям; EOF без `[DONE]` и stop finish reason не считается успехом. Tool calls и неподдерживаемый finish reason дают явную ошибку. URL и ключ проверяются до запроса; ключ не входит в outbox. `LocalWorkspaceService` связывает репозиторий, credentials, transport и recorder.

SQLite v3: `records(kind,id,workspace_id,version,payload,deleted)`, `receipts(command_id,fingerprint,result_id)`, `outbox(sequence,change_id,command_id,kind,record_id,version,payload,deleted,acknowledged)`, `message_search` FTS5, `local_settings`. Одна `BEGIN IMMEDIATE` транзакция охватывает receipt, изменения, FTS и outbox. Конфликт любой записи откатывает весь batch. Tombstone оставляет ID занят навсегда; устаревшая запись не может его восстановить. Будущие миграции меняют user_version; неизвестная более новая схема отвергается без очистки.

SQLite schema 3 добавляет replica_clock/records/inbox/state и sealed_outbox; текущая schema 4 добавляет outbox.in_flight. Локальный outbox содержит открытый payload, а `WorkspaceSyncEngine` отправляет только подписанный AES-GCM packet: точный ciphertext/signature сначала сохраняется, затем повторно используется после потерянного upload response. `WorkspaceCloudSyncTransport` передаёт эти packets по HTTPS; plaintext никогда не передаётся в relay. Исходящий packet меняется при новом key epoch только после запроса receipt предыдущего epoch. Локальная identity сама по себе не cloud account; native account/key pairing composition ещё не подключена к app mode. Отдельные JSON demo и v2 DB не читаются этим хранилищем.

Вложения хранятся отдельно по ID/hash; путь проверяется против traversal и symlink escape, чтение ограничено 32 MiB и сверяет hash. Selected imports допускают до восьми файлов на сообщение. `WorkspaceAttachmentSync` шифрует chunks до отправки, сохраняет их для точного повтора, возобновляет загрузку и проверяет размер/hash перед установкой. Реальная передача по cloud HTTP проверена; автоматическое получение вложений в UI ещё не подключено. Согласованная резервная копия использует SQLite backup API либо согласованный snapshot, а не копирование открытого `.sqlite` без WAL.

Каждая дельта текста долговечно сохраняется локально. Последняя неопубликованная assistant-запись outbox объединяется до передачи, без создания операции на каждый токен. Claim перед шифрованием и создание snapshot атомарно замораживают payload/sequence; claimed или sealed запись больше не меняется. Следующая дельта получает новый sequence, поэтому один nonce не используется для разных содержимых. Receipt каждой команды сохраняется независимо от объединения. Восстановление потока принадлежит executorDeviceId; получение чужого RUNNING сообщения не прерывает работу его устройства.

`WorkspaceAgentConfigurationResolver` требует точную configurationId профиля; неполная репликация не разрешает использовать старую revision. `WorkspaceRepository.close()` освобождает SQLite; после закрытия новые обращения явно отклоняются. Перед удалением каталога и восстановлением базы вызывающая сторона останавливает workers и закрывает соединения.

## Репликация: реализованное ядро и оставшиеся границы

1. На отправителе изменение и outbox зафиксированы. Канонический RecordChange подписывается устройством и шифруется с authenticated workspace/key epoch, origin stream, sequence, changeID, типом и версией envelope.
2. Сервер проверяет сессию, membership и допустимый epoch, хранит ciphertext и маршрутизирует только доверенным устройствам. Не расшифровывает историю. Вложения также шифруются до отправки.
3. Получатель проверяет подпись/epoch/целостность, затем пишет inbox/changeID, данные, FTS и cursor одной транзакцией. ACK только после commit. Outbox не удаляется по факту HTTP-запроса.
4. Sequence монотонен внутри origin stream. Повторы отсекаются по changeID. Пропуск не закрывается ACK более поздней позиции. Данные разных устройств нельзя сравнивать по локальному sequence как по общему времени.
5. Snapshot фиксирует watermark каждого origin stream и набор tombstones. Новый получатель записывает его целиком, затем применяет изменения после watermark. Пока snapshot не проверен, текущая база не заменяется.
6. Message — add by ID; reactions — tuple `(message,participant,emoji)` с remove-записью; read — max логической позиции участника. Удаление доминирует над старым upsert.
7. Конкурентные agent instructions/automation revisions не разрешаются часами устройства: сохраняются обе версии и базовая revision, выбор пользователя создаёт новую revision.
8. Черновики и панели локальны. Устройства, подключённые в разное время, получают очередь до 30 дней. При REPLAY_UNAVAILABLE требуется snapshot от актуального доверенного устройства; отсутствие донора — ожидание, не пустая история.
9. Отзыв закрывает сессии и выдачу данных, меняет будущий epoch/ключи. Уже известный отозванному устройству старый plaintext удалённо забыть невозможно.

## Внешние действия и Google

`PreparedAction` фиксирует аккаунт/ресурс, canonical parameters, preparationID, digest, срок и последствия. Digest включает preparation/action/task/executor IDs, tool/resource/parameters/consequences/expiry и перепроверяется по сохранённым полям; смешанный результат field merge не может использовать прежнее подтверждение. Разрешение связывается с exact digest и одноразово потребляется перед исполнением. После правки текста, адресатов, вложений или времени требуется новое разрешение. `executeOutcome.applied` возвращает true только первому atomic claim; повтор receipt не даёт право вызвать внешний API снова. `RUNNING` с потерянным итогом переходит в UNKNOWN и только в сверку. Подготовка и исполнение доступны назначенному executor; owner approval может прийти с другого доверенного устройства. Fencing cloud lease перед actual network request должен обеспечить будущий runtime/tool adapter.

Gmail scopes выдаются по операциям: чтение, drafts/compose, send. Ограничения и категории чувствительности сверяются с [официальной таблицей Gmail](https://developers.google.com/workspace/gmail/api/auth/scopes). Google-токены остаются в Keychain каждого устройства, не попадают в DTO/export/outbox.

Calendar create сохраняет устойчивый собственный externalID до запроса; это поддерживает [Calendar API](https://developers.google.com/workspace/calendar/api/guides/create-events). Изменения проверяют etag/версию события после подготовки. Даже при устойчивом ID неизвестный результат сверяется с внешним сервисом.

## Проверка совместимости

Общие fixtures читаются и обратно кодируются Java/Swift; enum catalog сверяется целиком. Проверки схем исключают секреты. Семантические проверки команд, lease, merge и UNKNOWN дополняют shape-тесты, а не заменяются ими. Shared examples для циклов Java/Swift и реальные Google/двухустройственные тесты ещё необходимы.

## Сетевая доставка snapshot

Cloud DB schema 2 добавляет snapshot_requests, миграция v1 сохраняет аккаунты/устройства/relay. `/v1/relay/snapshots` принимает requestID и исходный minimumCursor; тот же ID с другим содержимым даёт COMMAND_CONFLICT. Запрос живёт до 30 дней; отсутствие актуального донора остаётся ожиданием. Server pending выбирает запросы доверенных устройств, требующие нового снимка. MinimumCursor учитывает текущий retention floor.

Донор синхронизируется, атомарно получает snapshot/замораживает outbox, сохраняет точный ciphertext и manifest локально, затем досылает все вошедшие в снимок локальные изменения до публикации предложения. Ciphertext передаётся отдельными chunks до 256 KiB, общий максимум 128 MiB. Manifest связывает requestID, snapshotID, donorID, epoch, relay cursor, bytes/count, SHA-256 и подпись encrypted packet отдельной P256 proof (`BLOT-SNAPSHOT-OFFER-1`). Сервер проверяет proof, текущий epoch, ACK донора, floor и полноту/размер/владельца частей до публикации. Устаревшие из-за floor, epoch или отзыва донора предложения снова требуют актуального снимка.

Получатель проверяет request/manifest proof, размер/hash всего ciphertext, подпись packet, AEAD и равенство relay cursor внутри snapshot подписанному manifest. Прерванная загрузка хранит ciphertext-части и возобновляется; до полной проверки записи/cursor не меняются. Merge и cursor фиксируются одной SQLite-транзакцией, затем ACK и tail replay. Pending local записи не теряются. Локальный журнал хранит исходный cursor запроса и завершённость, поэтому restart и повтор commandID после установки не меняют payload запроса. UI polling/ожидание и автоматическое восстановление при retention gap ещё не подключены.

## Ключи и доверие устройств

`WorkspaceDeviceKeys` сохраняет отдельные P256 signing/agreement private keys и epoch keyring в device-only Keychain (`AfterFirstUnlockThisDeviceOnly`, Data Protection Keychain, без iCloud sync). ECDH/HKDF/AES-GCM envelope связывает ключи с получателем, workspace, подписавшим устройством и epoch. Полные пары публичных ключей наследуются только через owner-attested envelope; произвольный серверный список не становится корнем доверия.

`WorkspaceCloudDevices` реализует bootstrap, session-bound proof, invite/claim/owner confirmation/finish и signed revoke. Session tokens включают bootstrapAllowed: новый password login не инициализирует собственный случайный epoch 1 вместо ключа существующего workspace. Approval/revoke manifests сохраняются до HTTP для точного повтора после потерянного ответа. Будущий epoch остаётся pending до подтверждения сервером; старая история сохраняет старые ключи. Native flow проверен harness; QR и пользовательское подтверждение в продуктовых клиентах ещё требуют UI.

`WorkspaceCloudSession` сериализует записи credentials, объединяет refresh и использует generation для отмены устаревшего результата. После forget/logout приостановленная запись refresh не возвращает секреты в Keychain. Сетевой logout с истёкшим access может обновить сессию только для её отзыва, без локального сохранения.

## Cloud и Google configuration

Отдельный сервер и HTTP routes описаны в [cloud.md](cloud.md). Его relay хранит только непрозрачный `WorkspaceEncryptedPacket`: kind, workspaceID, originDeviceID, changeID, sequence, keyEpoch, ciphertext, signature. Бинарная подпись: ASCII `BLOT-APPLE-SYNC-1`, byte kind 1/2, UUIDs (raw 16 bytes), sequence/epoch big endian Int64, ciphertext. Swift CryptoKit и Java JCE проверены реальным HTTP wire harness. Ciphertext changes ограничены 512 KiB plaintext; локальные records — 192 KiB encoded для запаса envelope. Field/vector merge использует causal clocks, не wall-clock updatedAt; неизвестные kinds и stamps вне enclosing vector отвергаются. Снимки ограничены 128 MiB, сохраняют tombstones/conflicts и не заменяют pending local данные. Сетевые запросы/публикация/загрузка снимков реализованы отдельным snapshot service; автоматическое включение в жизненный цикл приложений ещё требуется.

Google OAuth сейчас выключен до регистрации реальных client IDs. Скрипт согласует clientID, reversed URL scheme, redirect URI и bundle ID; PKCE/state и token endpoint проверяются компонентными тестами. [Регистрация и обязательные Google проверки](google-oauth.md). Отсутствие ID не заменяется demo connection.
