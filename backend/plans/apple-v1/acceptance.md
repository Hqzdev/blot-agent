# Приёмка и фактические результаты

**Новая приёмка системного блока:** [N001–N012 и процедура проверки](native-integrations.md#7-проверяемый-реестр-блока), все NOT RUN. С 4 ноября актуальный реестр — **110 сценариев, порог 70% — 77 PASS; принято 0/110**. Исторические записи 98/69 ниже сохранены как прежний срез. Google-проверки E08–E10 не считаются пройденными от наличия EventKit; новый путь имеет собственные сценарии и границы.

Продолжение от 4 ноября: [фактические изменения, компонентные доказательства и ограничения](mvp-completion-2026-11-04.md). Прямой GigaChat проверен настоящим запросом; browser callback, новый runtime и peer snapshot — компонентами. Native Wi-Fi/Bluetooth, Google и полный путь регистрации Mac+iPhone ещё не приняты. Реестр 98 сценариев сохранён, 69 принятых сценариев не заявляются.


Реестр зафиксирован 3 ноября 2026; результаты обновлены 4 ноября 2026, Asia/Yekaterinburg. Исторический реестр до системного блока: 98 сценариев, порог 69 для 70%, зафиксировано **0/98 (0%)**. Текущий реестр: **0/110, порог 77**. Подтверждение компонентов не засчитывается как приёмка Mac+iPhone.

Для каждого полного прогона сохраняются: revision/working-tree digest, конфигурация и build ID обоих клиентов/сервера, версии ОС, физическое устройство либо симулятор, тестовый аккаунт без секретов, время/часовой пояс, команды/шаги, наблюдаемый итог и материал проверки. PASS требует реальных проверяемых результатов обеих платформ; PARTIAL/NOT RUN не входят в числитель.

## Обязательные сквозные сценарии

| ID | Подготовка и действия | Ожидаемый результат | Фактический результат |
| --- | --- | --- | --- |
| E01 Независимость | Выключить Mac; реальный запрос агенту на iPhone; затем наоборот | Два настоящих ответа, без второго устройства | NOT RUN |
| E02 Раздельная работа | Офлайн изменить данные на обоих; подключить по очереди, перезапустить | Одинаковые record IDs/content/tombstones, очередь подтверждена | PARTIAL: три Swift SQLite copies через настоящий encrypted Java HTTP relay; network snapshot/resume/pending merge/tail также проверены; продуктовый sync между физическими устройствами не проверен |
| E03 Повторы | Повторить команды/events/schedule fire, изменить payload того же commandID | Нет дублей message/reaction/task; изменённый payload отклонён | PARTIAL: SQLite command dedup проверен также на iPhone; encrypted HTTP wire повторы проверены на Mac; продуктовый двухустройственный прогон отсутствует |
| E04 Конфликты | Одновременно изменить инструкции агента и расписание | Обе revision доступны; выбор пользователя сохраняется | PARTIAL: causal merge, две agent revisions, snapshot и explicit resolve проверены; UI/устройства не приняты |
| E05 Поток | Оборвать сеть в потоке, завершить приложение, открыть снова | Частичный текст сохранён как INTERRUPTED; второго запроса нет | PARTIAL: recorder/reopen проверен на Mac/iPhone; live UI-adapter cancellation/reload проверены с injected model; реальная сетевая модель не проверена |
| E06 Группа | Координатор назначает работу двум агентам | Сохранены обращения/результаты, один связный итог | NOT RUN |
| E07 Отмена | Остановить родителя при двух активных детях | Вся ветка останавливается; новые tools/model calls не начинаются | PARTIAL: local/cloud cancel tree и lease fencing проверены; активный Swift runtime ещё требуется |
| E08 Подтверждения | Одобрить письмо/событие; изменить получателя/текст/время | Старый grant не подходит; запрошено новое подтверждение | PARTIAL: prepare/change/grant invalidation, digest tampering и atomic invocation claim проверены без Google API |
| E09 Google | Реальные тестовые Gmail/Calendar на обеих платформах | Поиск/read/draft/send и create/update/delete event подтверждены external IDs | NOT RUN |
| E10 UNKNOWN | Разорвать связь после отправки внешнего запроса до получения итога | UNKNOWN, сверка и отсутствие слепой повторной отправки | PARTIAL: invocation reopen → UNKNOWN и server acquire blocked до сверки; реальный внешний запрос не проверен |
| E11 Расписания | Сон Mac, закрытие iPhone, DST/смена timezone, повтор события | Политика пропусков, одна задача/fire, нет скрытого takeover | PARTIAL: DST, skipped/coalesced/catch-up runs, executor/manual/idempotence core проверены; ОС не проверены |
| E12 Память/файлы | Удалить память, синхронизировать старое резюме, сжать дважды; экспорт MD/PDF/CSV | Факт не возвращается; файлы открываются | PARTIAL: memory invalidation/context exclusion, imports/hash, многостраничный Cyrillic PDF/CSV проверены; полная синхронизация/устройства не приняты |
| E13 Доверие | Отозвать устройство; попытаться poll/push/renew с ним | Нет новых ciphertext/key epochs/lease/доступа | PARTIAL: cloud и native pairing/keyring/revoke/epoch/session/lease проверки прошли по HTTP; отзыв из product UI на физических устройствах ещё не проверен |
| E14 Обновление | Обновить DB, неудачно импортировать demo, открыть исходник | Исходные данные целы; новый schema version понятен клиенту | PARTIAL: отдельная local SQLite DB и безопасный close/reopen; server DB v1→v2 проверен без потери account/devices. Demo import и обновление product DB ещё требуют приёмки |

## Компонентные проверки

Прогон BlotWorkspace: **34 Swift Testing теста прошли на Mac**. Проверены SQLite transactional receipt/outbox/FTS, racing writers, response recovery/SSE framing/cancel, agent snapshots, groups/membership/mentions, reaction/read cursor, memory deletion/summary exclusion, skill parameter substitution, selected file limits/hash, PDF/CSV output, scheduler DST/missed policies, task tree/cancellation/shared budget. Два replicas с настоящим CryptoKit проверяют потерянный upload response/restart, причинность, field merge, concurrent config revisions, snapshot tombstones/conflicts и explicit conflict selection. Exact action preparation tests проверяют инвалидирование grant, повтор invocation без исполнения, UNKNOWN recovery и отказ смешанным параметрам со старым digest. PKCE tests проверяют state, duplicate parameters, redirect path/scheme и S256.

Отдельный cloud module: **10 Java-сценариев прошли** на SQLite/Argon2id/JCE P256: account verify/reset/session refresh/device proof, pairing confirmation/replay, signed durable relay/TTL, process lease generations/UNKNOWN, signed revocation/key epoch и quota dedup/единственный старт провайдера, provider preflight, отмена зарезервированного вызова и закрытие сессии до старта. Capturing mailbox проверяет components, не SMTP-доставку.

**Физический iPhone: 35 проверок PASS**, 0 failed/0 skipped, iOS 27.2. В отдельном подписанном `apps/verification/BlotWorkspaceVerification.xcodeproj` выполнены 34 теста общего ядра и настоящий Keychain write/read/remove. Bundle ID host отличается от приложения; пользовательская история и Google-токены не используются. Повторный прогон после разблокировки телефона — `.build/apple-v1-iphone-20261104T054242Z.xcresult`, краткие сведения — `.build/apple-v1-iphone-evidence.json`, сохранённый журнал — `.build/apple-v1-iphone-20261104T054242Z.log` (последний прогон также в `.build/apple-v1-iphone-tests.log`). Это запуск общего ядра на аппаратном iPhone, а не приёмка product UI.

Первый аппаратный прогон выявил удаление временных SQLite-каталогов до закрытия соединений. Добавлены explicit close и async test cleanup; повторный прогон прошёл без SQLite vnode/unlink warnings. Regression проверяет отказ обращений к закрытому repository и сохранность истории после нового открытия.

**Реальный HTTP wire harness PASS**: три Swift SQLite copies → CryptoKit encrypt/sign → запущенный cloud JAR → Java JCE verify → ciphertext SQLite → Swift decrypt/apply. Подтверждены раздельные сообщения/сходимость/дедуп, bootstrap, цепочка owner-approved pairing через уже сопряжённое устройство, ECDH-передача и восстановление ключей, signed revoke третьего устройства, epoch rotation, process lease fencing и многоблочные вложения с SHA-256. Проверены session rotation и гонка приостановленной записи refresh с logout: credentials после выхода не возвращаются. Неавторизованное устройство не инициализирует случайный ключ существующего workspace. Snapshot bootstrap ждёт донора, проверяет подписи и отвергает изменённый manifest, возобновляет многоблочную загрузку без повторного получения первой части; до завершения проверки cursor/история не изменяются. После установки сохранены pending local записи и получены сообщения после watermark. Повтор запроса после установки использует сохранённый исходный cursor. Server tests проверяют stale floor и v1→v2 migration. Relay DB/log не содержат plaintext сообщений/файла или bearer credentials.

Harness засевает только verified account и три unbound sessions в изолированную DB; devices/public keys/pairing создаются через настоящий native HTTP flow. Credential stores этого harness injected; настоящий Keychain проверен отдельно на iPhone. SMTP, Google, внешний провайдер модели, QR и product UI в этом прогоне не участвуют. Команда: `python3 scripts/check-apple-cloud-wire.py`; сведения — `.build/apple-v1-cloud-wire-evidence.json`, журнал — `.build/apple-v1-cloud-wire.log`.

Команда из корня (cache внутри workspace, чтобы не зависеть от прав на пользовательский cache):

```sh
env CLANG_MODULE_CACHE_PATH="$PWD/.build/apple-module-cache" \
    SWIFTPM_MODULECACHE_OVERRIDE="$PWD/.build/apple-module-cache" \
    swift test --disable-sandbox --package-path packages/BlotWorkspace \
    --scratch-path .build/apple-v1-workspace
```

Дополнительные завершённые проверки:

| Проверка | Результат | Материал |
| --- | --- | --- |
| Swift BlotWorkspace | PASS: 34 теста | `.build/apple-v1-workspace-tests.log` |
| Java cloud services | PASS: 10 сценариев | `.build/apple-v1-cloud-tests.log`, `.build/apple-v1-java-tests.log` |
| Swift/Java encrypted HTTP relay | PASS: три SQLite copies, native trust/rotation/files и запущенный JAR | `.build/apple-v1-cloud-wire-evidence.json` |
| Physical iPhone core + Keychain | PASS: 35 проверок, 0 failed/skipped | `.build/apple-v1-iphone-evidence.json`, `.build/apple-v1-iphone-summary.json` |
| Docker Compose configuration | PASS: synthetic secrets, без запуска контейнеров | `.build/apple-v1-compose-check.log` |
| Swift BlotDomain, включая новые DTO и rich Message | PASS: 5 тестов | `.build/apple-v1-domain-tests.log` |
| Java V3ContractTest на JDK 25 | PASS: 3 теста; 36 public records + rich Message, enum catalog, negative counters | `.build/apple-v1-java-tests.log` |
| JSON Schema 2020-12 | PASS: 157 fixtures и secret-field boundaries | `.build/checks-venv/bin/python scripts/check-v3-schemas.py` |
| Mac Xcode build | PASS через `./script/build_and_run.sh --build-only` | `.build/apple-v1-mac-build.log`, `.build/workspace-v3-check/build.log` |
| iOS Simulator Xcode build | PASS, signing disabled; запуск не выполнялся | `.build/apple-v1-ios-build.log` |

`swift test` для Domain использует те же cache env, что Workspace. Java-команда:

```sh
env JAVA_HOME="$PWD/.build/tools/jdk-25.0.4.1+1/Contents/Home" \
    GRADLE_USER_HOME="$PWD/.build/gradle-home" \
    backend/gradlew --offline --no-daemon -p backend :api:test --tests dev.blot.api.V3ContractTest
```

Для iOS использован `xcodebuild -project apps/Blot.xcodeproj -scheme BlotIOS -destination 'generic/platform=iOS Simulator' -derivedDataPath .build/apple-v1-ios CODE_SIGNING_ALLOWED=NO build`. Продуктовое приложение в симуляторе не запускалось. Физический iPhone проверен отдельным signed host командой `python3 scripts/check-apple-iphone.py`; сборка product UI и запуск core tests — разные проверки.

UI-adapter harness вызывается `./scripts/check-workspace-v3.sh --local-only`: временная SQLite DB, injected model, без Keychain/сети и пользовательской demo истории. Первый прогон PASS: команды UI сохраняются в SQLite, response stream проходит через recorder, явный retry не дублирует user message, reopen восстанавливает историю. Прогон отмены зависшего потока выявил, что AsyncStream при cancellation может вернуть конец итерации без исключения. Перед записью COMPLETED добавлена явная проверка cancellation; регрессия требует CANCELED и сохранённый частичный текст после reopen. Старый общий harness без этого аргумента здесь не запускался, поскольку он использует demo persistence. Логи без секретов остаются в `.build/`, краткие факты и команды — в этом документе. Генерация fixtures и сборка приложений отдельно от фактического запуска.

Дополнительные stream-регрессии: 100 локальных фрагментов дают одну неопубликованную outbox-запись; claim/snapshot запрещают последующее изменение того же payload/sequence; новые дельты создают новый sequence. Чужой RUNNING поток не прерывается при открытии принимающего устройства. UI-adapter повторно загружает активный чат без interruption и отклоняет вторую параллельную генерацию в том же разговоре. Явная configurationId не подменяется старой revision, пока новая не получена целиком.

## Ограничения текущего результата

Есть компонентное доказательство encrypted relay, lease/session/recovery services и Swift/Java HTTP interoperability. Нет продуктовой приёмки Mac+iPhone и account/QR UI, автоматической cloud-композиции в приложениях, реального SMTP/GigaChat/Google send/calendar, полного agent tool loop или iPhone background execution. **70% не достигнуты**: принято 0/98, знаменатель и BLOT matrix сохранены. Нельзя отправлять plaintext local outbox или запускать старый Java agent loop для Apple tasks.

Пользователь подтвердил: Google OAuth clients ещё не зарегистрированы, требуется подготовить configuration/guide. Это выполнено в `google-oauth.md`, `apps/shared/Resources/GoogleOAuth.plist` и `scripts/configure-google-oauth.py`; реальный вход остаётся NOT RUN. `--check` сообщает о выключенном состоянии, а не об успешной внешней авторизации.


Финальный UI-adapter прогон: **PASS**, `--local-only`, exit 0. Подтверждены create/send → durable stream → explicit retry → reopen, а также остановка зависшего потока, сохранение partial text и CANCELED после открытия базы заново; соединения закрываются до удаления временного каталога. Исправленная cancellation-регрессия воспроизведена тестом. Модель injected; это не проверка реального API или iPhone.

Исходная revision и хеши компонентов сохранены в [verification-2026-11-04.json](verification-2026-11-04.json). Изменения остаются незакоммиченными. Полный manifest SHA-256 для 389 исходных файлов и команды — в `.build/apple-v1-evidence.json`. Ни одна исходная BLOT-строка не удалена; сверка plan-файлов подтвердила 98 уникальных A-ID, 76 сценариев этапа 1, 30 BLOT mappings и существование локальных ссылок.
