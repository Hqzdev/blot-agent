# Продолжение Apple MVP — фактический срез 4 ноября 2026

Это журнал реализации, не приёмка полного блока. Реестр остаётся 98 сценариев; 70% и 69 принятых сценариев не заявляются.

## Уточнения пользователя

- История синхронизируется напрямую между устройствами по Wi-Fi/Bluetooth. Обязательный внешний relay и требование `BLOT_CLOUD_URL` отменены. Серверный HTTP relay остаётся существующим компонентом репозитория, но новое приложение его не запускает и не использует для синхронизации.
- Последующее уточнение 4 ноября: пользователь выбрал Vercel и PostgreSQL также для хранения чатов и проектов. Добавлены аккаунтные резервные снимки рабочего пространства в Neon; прямой peer transport остаётся доступен. Это дополняет предыдущую договорённость о локальном исполнении агента.
- Вход/регистрация/подтверждение почты проходят через `https://blot-agent.vercel.app/login` на всех устройствах. Сайт возвращает одноразовый код; приложение обменивает его с PKCE на собственную сессию. SMTP работает только в серверном обработчике сайта. Подробный контракт для автора страницы — [browser-login.md](browser-login.md).
- GigaChat вызывается напрямую с устройства. Общая серверная квота не считается работающей. Личный Debug-профиль допускает извлекаемый GigaChat key; Release со встроенными credentials блокируется.

## Реализовано

### Конфигурация

`apple_build_configuration.py` читает `.env`/`BLOT_ENV_FILE` как данные. Общий Xcode build phase обоих targets и CLI используют этот валидатор. Установочная конфигурация содержит GigaChat, URL входа и Google client IDs; SMTP-пароля и Google-токенов в ней нет. Native callback schemes и GoogleOAuth.plist формируются в собранном продукте, исходный plist пользовательских подключений не перезаписывается. Управляемая конфигурация устанавливается в отдельный Keychain namespace.

Обработка `blot-agent-ios:/oauth/start` и `blot-agent-macos:/oauth/start` открывает новый PKCE-сеанс после загрузки локального аккаунта; при уже активной сессии требуется явный выход для смены аккаунта.

Добавлен официальный публичный Russian Trusted Root CA, указанный документацией GigaChat. Trust применяется только к заданным provider hosts, с проверкой имени узла и цепочки. Глобальное системное доверие не изменяется, TLS не отключается.

Серверный account-процесс научился читать тот же dotenv и SMTP. `scripts/run-cloud.sh` сохраняет постоянный challenge key между перезапусками. Этот dev-process — реализация account API, а не требование размещать историю или вычисления агента в облаке.

### Вход и локальные данные

Обычный запуск больше не создаёт demo workspace и не принимает фиктивный вход. Удалены demo-ответы, отдельные старые JSON-persistence adapters и кнопка обхода авторизации. Файлы ранее установленной demo-истории не трогаются. Каталог экранов и интерактивные макеты остаются только явными preview-путями; их данные не импортируются в аккаунт.

`WorkspaceStore` зависит от интерфейсов аккаунта, команд, наблюдения и выполнения. Создание LocalWorkspaceService находится в composition root аккаунта. После входа выбирается отдельная SQLite по owner/workspace; identity проверяется до открытия истории. Создаются ключи устройства. Process lock не позволяет второму процессу запускать восстановление/работу той же установки. Выход отменяет всех активных response workers и очищает интерфейс, сохраняя SQLite. Поздний результат старой сессии не возвращает историю в интерфейс.

Native login использует системный ASWebAuthenticationSession и проверяет точный callback, уникальный state, одноразовый code и PKCE. Account API выдаёт и атомарно обменивает 60-секундные коды, проверяет client/callback и активность подтверждённой browser session. Публикация сайта в этом срезе не выполнялась.

### Модель и выполнение

Оба модельных адаптера используют типизированные события text/toolCall/usage/finished/failure. GigaChat реализует native functions, object arguments, functions_state_id и роль function. Compatible API собирает фрагменты tool_calls. Вызов инструмента не публикуется до завершения SSE и проверки JSON. EOF не считается успешным завершением. Поток разбирается по байтам с сохранением пустых SSE-строк; Foundation `.lines` для этого непригоден.

OAuth GigaChat обновляется single-flight. На 401 токен сбрасывается, но генерация автоматически не повторяется. Настройки и CA входят в продукт; исходный `.env` на устройстве не читается.

Общий WorkspaceModelRuntime сохраняет ModelStep с запросом, model/configuration/skill/budget и отдельным responseMessageId. Он записывает полный набор вызовов до инструмента и каждый результат до следующего действия. Есть проверка разрешённых инструментов, аргументов, отмены, выбранного устройства, состояния задачи и её предков, UNKNOWN и бюджета. Общий пул ограничен четырьмя модельными запросами. Удалённые/старые задачи без executionMode не запускаются. Локальные инструменты: чтение явно прикреплённых файлов, создание Markdown/PDF/CSV, кандидат памяти с источником; модель не активирует кандидата сама.

Usage хранится один раз на ModelStep; отсутствие счётчиков остаётся неизвестным расходом. В iPhone usage view удалены demo estimates; показываются реальные счётчики и отдельное число запросов с неизвестным расходом. Есть выбор GigaChat/compatible и локальных инструментов в настройках агента. Попытки генерации и частичный ответ сохраняются; повтор только явный.

### Прямой peer sync

Добавлен независимый WorkspacePeerSync: challenge-response с подписью, capability check, зашифрованный снимок, commit до подписанного ACK. Он использует существующие CryptoKit keys и snapshot merge, сохраняет локальные изменения и tombstones и не передаёт право выполнения. Receipt одного peer не очищает очередь для остальных устройств. Два отдельных SQLite-экземпляра проверены без relay и без интернета.

Это протокольный компонент. Подключение к native Wi-Fi/Bluetooth discovery/transports, QR UI, полный incremental log, ротации/отзыв и передача вложений в этом новом прямом режиме ещё не завершены. Проверенный ранее HTTP relay нельзя выдавать за готовую native peer-синхронизацию.

## Доказательства

- 45 Swift component tests BlotWorkspace: typed SSE/function formats, реальный tool loop с сохранённым результатом и usage, строгая проверка аргументов, process lock, браузерный state/PKCE, account identity, прямой snapshot exchange и существующие repository/permission/sync tests.
- 5 BlotDomain tests и 167 JSON fixtures проходят проверку схем. Java V3ContractTest проходит с новыми ModelStep/ExecutionMode.
- Java account/cloud tests проходят, включая неправильный verifier/client/callback, срок и повтор browser code.
- 6 Python configuration tests: Release gate, отсутствие SMTP в native config, dotenv без выполнения shell, обязательные поля и Google clients.
- UI-store harness: 53 references, отсутствие авторизационного обхода, форма/навигация, SQLite/stream/retry/cancel/reopen с внедрённой тестовой моделью.
- Реальный GigaChat tool loop завершён: 2 модельных шага, 1 открываемый Markdown, 391 provider tokens. Это проверка настоящих native function calls/functions_state_id и долговечного runtime.
- Реальный прямой GigaChat OAuth+TLS+SSE завершён, получен непустой текст и 28 provider tokens. Это транспортный harness, не сквозная приёмка приложения.

Журналы: `.build/model-tests.log`, `.build/mvp-domain-tests.log`, `.build/mvp-schema.log`, `.build/mvp-cloud-tests.log`, `.build/mvp-java-contracts.log`, `.build/mvp-ui-tests.log`, `.build/mvp-ui-full-tests.log`, `.build/direct-model-test.log`, `.build/direct-tool-loop-test.log`. В лог реального запроса записываются только количество символов и usage; ключи и тело ответа не записываются.

## Что не принято

Обновление 4 ноября: причина `503 auth_service_unconfigured` устранена. Создана отдельная Neon PostgreSQL `blot-accounts`, подключена к Production/Preview проекта Vercel `landing`. Account API перенесён в Node.js-обработчики сайта с сохранением native PKCE-контракта. Production deployment `dpl_6fQ5TBVLP6PiSW7MQNprb1Eytjqh` опубликован на `blot-agent.vercel.app`. Восемь live-проверок подтвердили работу API и базы, проверку неправильных credentials, CSRF, Google redirect и отказ неавторизованному чтению резервных копий. SMTP TLS и авторизация Gmail отдельно проверены из Vercel без отправки письма. Прошли 11 JS/PostgreSQL tests, два Swift backup tests и сборка Mac. Реальное получение письма, Google consent и полный путь «сайт → приложение → ответ модели → перезапуск» пока не приняты.

`WorkspaceCloudBackup` подключён к жизненному циклу аккаунта: чаты, сообщения и записи проектов сохраняются снимками в PostgreSQL, загружаются частями по 512 KiB и сливаются существующим causal merge при восстановлении. Проверены несколько частей, восстановление проекта/чата, offline edits и повтор после потерянного ответа commit. Файловые байты вложений и локальные credentials не входят в снимки. Сервер читает содержимое этих HTTPS-backups; E2E peer-шифрование для них не заявляется. Код сайта сохранён в PR #11; native изменения остаются в локальной рабочей папке.

Также остаются: native peer discovery/QR/incremental/attachments/revocation; работающая UI-композиция групп с двумя детьми и общим бюджетом; точные подтверждения реальных Google операций и UNKNOWN reconciliation; OAuth+REST Gmail/Calendar с несколькими ящиками; компактирование/skill flows; расписания с фактическим исполнителем и системным фоном; backup/restore/delete; физическая Mac+iPhone приёмка. Полированная MacTeam preview-композиция ещё не переведена на живые сервисы: рабочий режим использует существующую SQLite-backed shell. Это ограничение сохранения текущего дизайна, не завершённый дизайн-паритет.

Не подменять эти пункты результатами unit tests или заранее подготовленными preview-ответами. Полный MVP не завершён.

Подписанные Debug-сборки Mac и iPhone проходят `codesign --verify --strict` с доступом к системной trust-службе. macOS процесс запущен штатным `script/build_and_run.sh --verify` без передачи `.env` на вход. Визуальная проверка CUA не выполнена: доступ к интерфейсу Blot не был предоставлен. Это не основание отмечать UI-приёмку успешной.

Машинный отчёт этого среза: [verification-mvp-progress-2026-11-04.json](verification-mvp-progress-2026-11-04.json). Локальные архивы `.build/artifacts/Blot-Mac-personal-dev.zip` и `.build/artifacts/Blot-iPhone-personal-dev.ipa` проверены на целостность; хеши и точные пути включены в отчёт. Содержимое исходного `.env`, SMTP и рабочие SQLite-базы в архивы не включаются. Встроенный GigaChat key присутствует согласно принятому personal-dev профилю.
