# Реализация и зависимости

**Актуальный системный блок MVP:** [native-integrations.md](native-integrations.md), этапы N0–N6. Сначала контракт → чтение EventKit → подтверждённая запись и восстановление; затем Reminders → передача в приложения → Shortcuts/App Intents → физическая приёмка. Google REST отложен; Google web sign-in остаётся отдельным.

Обозначения: `[x]` реализованный компонент, `[ ]` остающаяся работа. Ни один этап не считается завершённым лишь из-за наличия схем или экрана. Приёмка сценариев отдельно в acceptance.md.

## Этап 0 — объём и контракт

- [x] Сохранить пять материалов в одной папке; закрепить реестр 98 сценариев (76 в первом этапе), правило подсчёта и BLOT mapping.
- [x] Найти composition points Mac/iOS, demo persistence и unavailable v3 service; сопоставить семейства UI-действий с реестром.
- [x] Отделить общий workspace от executor, добавить DTO групп, участников, ответов/упоминаний, реакций/прочтения, skill revisions, журнала/конфликтов и lease.
- [ ] Полные payload schemas и fixtures каждой новой команды/события, capability handshake и семантические state-machine examples для Java/Swift.

Зависимость: согласованные поля до persistence migrations и relay. `model.json` остаётся единым источником DTO.

## Этап 1 — общий локальный пакет

- [x] Создать BlotWorkspace без UI; SQLite adapter, actor repository, schema version, отдельная база.
- [x] Атомарные record + receipt + outbox + FTS, проверка expectedVersion, дедупликация, запрет stale resurrection.
- [x] Durable create/send, привязка ответа и валидация UTF16 mentions.
- [x] Durable частичный ответ и восстановление RUNNING → INTERRUPTED без повторного запроса, только для своего executor. Замороженный перед шифрованием/snapshot outbox; объединение неопубликованных дельт сохраняет receipts и nonce uniqueness.
- [x] Подключить пакет к обоим Xcode targets и общий live adapter/observable projections, сохраняя дизайн и отдельное demo; gate `--workspace-local`.
- [x] Локальные rename/pin/archive/delete разговора с версиями и tombstones; отдельный response retry без дубля user message.
- [x] Core-команды агентов/revisions, групп/участников, реакций/прочтения, памяти/кандидатов/резюме, навыков и task/budget. Live UI подключён к агентам, группам, реакциям/прочтению и памяти.
- [ ] Полный UI навыков/кандидатов/резюме и всех настроек; оставшиеся live-действия не меняют business snapshot напрямую.
- [x] Локальные вложения по ID, ограниченный импорт выбранных файлов, безопасный путь/hash, FTS и переход к сообщению в Mac/iOS UI; перенос bytes между устройствами отдельно.
- [ ] Явный demo import с backup, ID mapping, rollback; без превращения demo-подключений в Google.

Выход: перезапуск обоих приложений сохраняет все перечисленные данные и очередь; один чат использует общее ядро на обеих платформах.

## Этап 2 — аккаунт и репликация

- [x] Отдельный Java cloud process: account/session registration, verification/recovery, revoke, device identity, rate limits, body limits и безопасные ошибки. Компонентные проверки; SMTP/публичный release не проверены.
- [x] Device-only Keychain adapter, нативный HTTP/session client с single-flight refresh; серверные bootstrap/challenge/owner-signed pairing и expiry/replay checks.
- [x] Нативные P256 signing/agreement keys, ECDH wrapped keys, подписанные native pairing/revoke manifests, наследуемая цепочка доверия и keyring с pending/active epoch; проверено через HTTP harness.
- [ ] QR, пользовательская сверка кода и account/pairing UI, подключение cloud services к обоим приложениям.
- [x] AES256-GCM/P256/HKDF envelope, durable nonce/sequence, повтор точного ciphertext, server relay TTL 30 дней и постоянные минимальные dedup receipts.
- [x] Шифрование/возобновление file chunks, проверка hash до установки, точный повтор ciphertext; native keyring rotation и trust chain.
- [ ] Автоматическая загрузка/получение cloud attachments в UI и физическая приёмка передачи между приложениями.
- [x] Inbox/apply/checkpoint одной транзакцией, ACK после commit, durable outbox ciphertext, causal gap/replay checks; потерянный upload response и повтор ACK проверены. Реальный HTTP wire test трёх SQLite copies прошёл; bootstrap, цепочка pairing, revoke/rotation и файлы проверены.
- [x] Field/vector merge, message/reaction/read/tombstone, обе версии agent/schedule, явное conflict.resolve и shared UI выбора. Новые задачи и расписания блокируются до выбора; снимок сохраняет конфликты.
- [x] Локальный consistent replica snapshot + vector watermark, encrypted snapshot seal/open, transactional merge без потери pending local данных и без отката собственного nonce sequence.
- [x] Серверная очередь snapshot-запросов, native donor/publish/download, подпись manifest и cursor, hash/chunks/resume, ожидание донора и локальный журнал запросов после restart. HTTP harness проверяет bootstrap с pending local данными и tail replay; server tests проверяют retention floor и migration v1→v2.
- [ ] UI bootstrap/ожидания донора и автоматическое подключение snapshot recovery при REPLAY_UNAVAILABLE в обоих приложениях.
- [x] Серверный подписанный revoke: session closure, epoch+1, opaque key grants оставшимся устройствам, cancellation назначенных задач; проверено без физических клиентов.
- [x] Серверный lease на task/device/process-holder/generation, renew/release/cancel; UNKNOWN блокирует новый acquire до сверки. Отдельный cloud process не запускает старый Java agent loop.

Выход: выключенные по очереди Mac/iPhone сходятся после независимой работы и не выполняют задачу вдвоём. Это gate перед групповыми инструментами и расписаниями.

## Этап 3 — реальные чаты и модели

- [x] Текстовый OpenAI-compatible SSE adapter, HTTPS endpoint/model/key validation, device-only Keychain config.
- [x] Серверный текстовый GigaChat gateway, metadata-only quota reserve/actual/unknown и запрет повторной генерации requestID.
- [ ] Подключить встроенный gateway к обоим Apple-клиентам и проверить реальный GigaChat; capability validation compatible API.
- [x] Текстовый stream transport → durable recorder → UI, отдельный terminal status, cancel и явный retry; компонентная проверка с injected model.
- [ ] Реальная модельная приёмка обоих клиентов, поток usage/tool calls и сохранённое состояние задания.
- [ ] Сохранённые состояния local/waiting/accepted/running/completed/error; ошибки не изображаются успехом.
- [ ] Независимые реальные генерации с выключенным вторым устройством; offline read/send queue.

## Этап 4 — агенты и группы

- [ ] Swift portable agent loop: immutable configuration snapshot → model request → policy/approval → tool adapter → persisted result → next step.
- [ ] Координатор, два участника, сохранённая переписка, источники итогов и typed mentions.
- [x] Локальные pinned task/session configurations, parent depth ≤2, cancel дерева и общий root budget reserve/actual/unknown с дедупликацией. Cloud ограничивает active leases до четырёх; enforcement в полном agent loop ещё требуется.
- [x] Точные prepare/approve/deny/begin/finish, одноразовый grant и atomic first invocation claim; проверки digest против изменённых полей; crash RUNNING → UNKNOWN без повторного исполнения.
- [ ] Cooperative runtime cancellation активных calls всей ветки, fencing lease перед шагами и реальные адаптеры reconciliation.
- [ ] Shared state transition examples с существующим Java-циклом; Java очередь Apple tasks выключена.

## Этап 5 — память, навыки и результаты

- [x] Core personal/agent memory, источники, кандидаты/принятие, редактирование/удаление, summary invalidation и context builder без удалённых источников.
- [ ] Автоматическое получение summary/кандидатов моделью и полный UI проверки источников.
- [x] Core immutable skill revisions/parameters и фиксация revision в task/schedule; подстановка не интерпретирует введённое значение как новый шаблон.
- [ ] Запуск навыка из UI чата/расписания через рабочий agent/tool runtime.
- [x] TXT/MD/CSV/JSON/code/text-PDF read, copied file storage, hash/path/byte limits и источники страниц PDF; выбранные вложения включаются в контекст.
- [x] Локальный MD/PDF/CSV export из ответа, многостраничный PDF с кириллицей, CSV quoting/formula protection, открытие/экспорт файла.
- [ ] Реальные прикладные задания и подтверждение категорий импортированных расходов.

## Этап 6 — системный календарь и приложения

- [ ] N0: capabilities, контракты, fixtures и журнал системных действий.
- [ ] N1: разрешения ОС, выбор календарей и реальное чтение Mac/iPhone.
- [ ] N2: free slots, prepare/approve/execute, конфликты, повторения и UNKNOWN reconciliation.
- [ ] N3: независимые разрешения и операции Reminders.
- [ ] N4: файлы, поддерживаемый compose и открытие выбранного приложения.
- [ ] N5: выбранные пользовательские Shortcuts и три App Intents самого Blot.
- [ ] N6: lifecycle, расписания, peer replay и приёмка N001–N012.

Зависимости, ограничения EventKit и точные gates: [полный план](native-integrations.md). Этот блок не требует Google OAuth для Calendar/Gmail.

### Исторический задел Google — отложен за пределы MVP

- [x] Выключенная до регистрации конфигурация, проверяемый configure script, [инструкция Google OAuth](google-oauth.md), PKCE/state/callback validation и token exchange/refresh/revoke.
- [ ] Пользователь подтвердил отсутствие зарегистрированных клиентов: зарегистрировать реальные Apple client IDs/test users, подключить системный browser flow и device-only Google token store к UI.
- [ ] Gmail account selection/search/thread/summary/draft/edit; exact approval адресатов/текста/вложений, persisted result/externalID.
- [ ] Gmail UNKNOWN → сверка; без слепого send retry.
- [ ] Calendar list/events/free-busy/prepare create-update-delete, timezone/calendar/attendee confirmation, etag validation/stable externalID.
- [ ] Реальные тестовые ящики/календари на Mac и iPhone; моки только для компонентов.

## Этап 7 — расписания и настройки

- [x] Core и формы once/repeat, IANA timezone, DST, next fire preview, disable/manual enqueue; выполнение очереди агентом ещё требуется.
- [x] Уникальный `(automationID, scheduledAt)`, manual trigger отдельно, COALESCE/SKIP/ограниченный CATCH_UP; foreground scheduler ставит задачи только для назначенного устройства.
- [ ] Local OS reminders, notification permissions, iOS lifecycle recovery; точный background task launch не обещается.
- [ ] Профиль, models/limits/memory/integrations/notifications; platform-only UI/launch/login/Reduce Motion preferences локальны.

## Этап 8 — надёжность и выпуск

- [ ] Crash recovery before/during/after external action, lease expiry/revocation, usage deduplication и ограничение storage.
- [ ] Согласованный export/backup/restore/delete, migrations, import rollback и диагностика без секретов.
- [x] Отдельный cloud JAR, параметры локального процесса, Dockerfile/compose/TLS proxy profile и [инструкция развёртывания](cloud.md).
- [x] Проверка compose configuration без запуска контейнеров.
- [ ] Сборка/запуск контейнера (Docker daemon недоступен), публичный хост/DNS/TLS/секреты, подключение обоих реальных клиентов к одному окружению.
- [ ] Подсистемные feature gates; рабочий режим включается после проверок, demo остаётся отдельным.
- [ ] Все 14 сквозных сценариев; физические Mac+iPhone, evidence с build/hash/device/date; минимум 77 из 110 сценариев полностью приняты.

## Внешние зависимости приёмки

Для актуального системного блока нужны подписанные Mac/iPhone, реальные системные календари и списки Reminders, поддерживаемое почтовое приложение, выбранные файлы и пользовательский Shortcut. Google OAuth для Calendar/Gmail не требуется. Вход Blot, модель и принятый способ синхронизации проверяются отдельно по актуальному срезу MVP. Секреты не помещаются в plan, fixtures или git. До проверки конкретной зависимости задача остаётся «не проверено»; отсутствие доступа не заменяется демо-результатом.
