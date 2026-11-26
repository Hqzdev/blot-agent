# Сверка расширенного реестра Grok Bot с Blot

18 ноября 2026 года. Основание — присланный пользователем реестр F001–F311: 311 пунктов в 30 разделах. Проверяется текущий macOS/iOS-проект и связанные Swift/Java-сервисы. [Предыдущая сверка экранов](grok-catalog-gap-analysis.md) остаётся отдельной картой визуальных блоков.

Это обзор покрытия по 30 разделам с точечным чтением реализаций. Не является подтверждением всех 311 сценариев на устройствах или подсчётом процента готовности продукта. Пункты пересекаются, часть относится только к Enterprise или сервисам самого Grok. «Не найдено» означает отсутствие найденного законченного сценария в проверенном коде, а не результат отрицательного теста каждого внешнего провайдера. Текущая документация Grok в интернете заново не проверялась: сравнение выполнено с переданным текстом.

## Уточнение к предыдущему отчёту

Расширенный документ прямо отделяет текущий продукт от старых видео: у личного Grok Bot убраны отдельная страница настроек/описания роли и отдельный экран памяти. Поэтому отличие этих элементов от S063 — **историческое визуальное расхождение, а не обязательный пробел относительно текущей версии Grok**. Собственный профиль/редактор инструкций Blot может сохраняться по нашим требованиям. Светлая тема и прежние указания пользователя по Liquid Glass остаются визуальным ориентиром.

Также не нужно копировать старые цены, домен `mail.grokbot.com`, `@bot` как чужую учётную запись или URL scheme Grok. Сравнивается пользовательская возможность; у Blot должны быть собственные идентификаторы и продуктовые решения.

## Дополнительные существенные пробелы

### 1. Управление ботами, не только чатами

Нет найденных законченных сценариев: создание бота самим ботом (F003), выбор/замена primary Bot (F004), проектные секции sidebar (F009), дублирование бота без истории/памяти (F011), публикация/обновление/отключение ссылки шаблона (F013–F015).

В live UI есть создание и редактор агента, а также pin/archive/delete **переписки**. Их нельзя автоматически засчитывать как отдельные pin/hide/delete **самого бота** (F008, F010, F012). В `WorkspaceAgentService` найдена операция save; отдельный жизненный цикл удаления/дублирования агента не найден. Изменение постоянной роли через чат (F002) также не подтверждено: редактор инструкций есть, но соответствующий инструмент изменения профиля в рабочем tool catalog не найден. [A]

### 2. Уточнение работающему агенту

F029 не закрыт: `WorkspaceStore.perform` отклоняет `.send`, когда в выбранном чате уже есть live response: «Дождитесь ответа или остановите его перед новым сообщением». Кнопка Stop существует, но остановка **сообщением** (F030), очередь уточнений и доставка новой инструкции текущей работе — отдельные отсутствующие механизмы. [B]

### 3. Поиск на iPhone

F218 покрыт частично: `PhoneSearchResults`/`PhoneSearchView` выводят агентов и группы. Нет Messages/Files/Routines в этом общем мобильном поиске. Общий `WorkspaceLocalSearchView` ищет сообщения, однако это не функциональность текущей мобильной search sheet. Фильтр файлов по имени существует отдельно. [C]

### 4. Событийные и управляемые через чат routines

Есть расписание по времени/часовому поясу, включение/пауза, ручной запуск и сведения о выполнениях. Не найдены триггеры Slack/GitHub/Linear/Sentry/PagerDuty/email/webhook и передача JSON webhook в задачу (F101–F105). Создание/изменение расписания естественным языком и удаление с подтверждением (F099, F109–F110) не найдены как законченные сценарии. UI создаёт расписание формой, а `.updateSchedule` только меняет `enabled`. [D]

### 5. Медиа и форматы файлов

- Встроенный `document_create`/экспорт создаёт Markdown/PDF/CSV. Это не готовая генерация Word/Excel/PowerPoint (часть F119).
- Импорт поддерживает PDF, ряд изображений и UTF-8 текст/код/CSV/JSON/YAML. `docx/xlsx/pptx`, аудио/видео и `ipynb` не включены в штатный список `WorkspaceFileFormat` (части F113–F115).
- Не найдены встроенная генерация изображений/видео, видео по двум кадрам и специализированный видеоплеер (F120–F122, F125).
- Нет готовых коннекторов переноса результатов в Drive/OneDrive/SharePoint (F116).
- Локальный CLI или произвольно настроенный MCP теоретически могут создавать другие файлы; это не подтверждает штатный поддерживаемый сценарий приложения. [E]

### 6. Мобильные системные возможности

Нет найденных: Share Extension для отправки из других приложений (F212), специального Add to Chat для выделения (F214), Live Activities (F222), инструментов геопозиции, AlarmKit/таймеров и Apple Home (F225–F226, F228).

Есть виджеты с переходами в приложение и App Shortcut «Открыть приложения Apple». Это частичное покрытие F221; произвольные задачи агенту через Siri, Spotlight и отдельное действие для Action Button не подтверждены. Виджеты не являются Live Activities. Календарь, контакты, reminders и Apple Shortcuts имеют отдельные реализации и не должны попадать в список полностью отсутствующих. [F]

### 7. Настоящие push-уведомления

В `PhoneNotifications` найдены разрешение и **локальные** `UNNotificationRequest` при получении ответа. Не найдена законченная регистрация APNs/device token и серверная доставка, позволяющая сообщить о работе без активного исполнения приложения. Поэтому F220 нельзя считать полностью закрытым наличием уведомления и настроек haptics. [G]

### 8. Полный голосовой сценарий

Живой разговор, mute/hang up, текущий transcript и язык распознавания существуют. Выбор голоса/скорости (F050) закрыт не полностью: голос выбирается по locale, скорость используется системная. Не найдены законченные голосовые заметки, возврат к продолжающемуся звонку после ухода, карточка завершённого звонка и запись/экспорт transcript звонка (F048, F051–F052, F056). Голосовая сессия завершается при уходе приложения в background. Телефонные звонки организации с takeover (F053–F055) отсутствуют отдельно. [H]

### 9. MCP: базовый транспорт есть, OAuth-flow нет

Remote HTTP(S), Bearer token, выбор инструментов/агентов, обновление, отключение и stdio на Mac реализованы. В UI нет настройки произвольных HTTP headers и полноценного MCP OAuth client-flow (F077); предлагается вручную указать уже выданный токен. Не найдено подключения нового MCP по просьбе в чате (F079). Внешние сервисы из каталога не становятся подключёнными автоматически при наличии MCP-механизма. [I]

### 10. Сервисная почта, X и внешние входы

Нет собственного адреса почты агента/aliases, входящих email-триггеров, штатного X search/private X plugin и приёма заданий из X-упоминания (F081–F088, F304–F307). Apple Mail и ручной просмотр сайта в браузере — отдельные существующие механизмы, не равные этим сервисам. [I, J]

### 11. Настройки и коммерческие функции

Не найдены полноценное переключение нескольких аккаунтов внутри приложения (F232), выбор Bot color/Black (F234: текущий цвет автоматически следует агенту в личном чате), выбор микрофона (F236), аппаратного ускорения (F237), маршрутизация трафика через компьютер (F241), автоматическое обновление/перезапуск (F242), Copy request ID для ошибок (F246).

Есть одноаккаунтная авторизация, темы/язык, настройки агента и компьютеров, локальное исполнение, read/unread/mute чата. Для уведомлений конкретной переписки есть mute, поэтому F243 нельзя целиком обозначить отсутствующим. Нет полного коммерческого набора: weekly reset, By Bot/By source, additional usage/monthly limit, credits/auto top-up/referral (F248–F253). Подписка и реальные счётчики токенов существуют отдельно. [K]

### 12. Deep links

На iOS есть `blot-agent-ios://widgets/chat/<UUID>` и `/agent/<UUID>`, переходы compose/agents/schedules/overview. Также есть ссылки авторизации и подключений. Это частичная основа F308–F309, а не полное отсутствие deep links. Не найдены общий кроссплатформенный chat-link с подстановкой текста без отправки (F310) и fallback к выбранному primary Bot (F311). Widget parser запрещает query; он не поддерживает подстановку сообщения. [L]

## Покрытие всех 30 разделов

В таблице «есть» означает найденную основу, а не полное покрытие всего диапазона F. Упоминания общих функций Enterprise не засчитываются как наличие корпоративного продукта.

| Раздел и диапазон | Найденная основа | Что остаётся |
| --- | --- | --- |
| Боты и организация — F001–F015 | Создание/редактирование, форма, цвет, инструкции, встроенные шаблоны. | Primary Bot, агент создаёт агента, lifecycle бота вместо lifecycle чата, проектные секции, публикация/импорт сторонних шаблонов, Generate/Upload. [A] |
| Память — F016–F023 | Личная/агентная память, использование approved memories в контексте, изменение/удаление. | Import Memory, контекст записанных звонков, явный Reset с сохранением памяти; полный review кандидатов. Просмотр памяти вопросом не подтверждён отдельным инструментом чтения всей памяти. [M] |
| Переписка и поиск — F024–F037 | Сообщения, файлы, reply, reactions, инструменты, черновики/карточки, поиск локальных сообщений, Stop. | Live steering, Stop сообщением, полный набор @сущностей, Gmail/Outlook-вложения, единый поиск всех категорий. Полная палитра команд в действующем live shell отдельно не подтверждена: наличие старого компонента не считается доступностью. [B, C, J] |
| Группы и передача — F038–F045 | Группы, редактирование состава, общий контекст, специалисты, асинхронные задания, вложения, вопросы. | Точное покрытие @everyone, адресации всех сущностей, владения этапом естественным языком и пользовательских форм требует отдельной проверки; не объявляется отсутствующим или готовым по одним скринам. [N] |
| Голос/звонки — F046–F056 | Внутренний голосовой разговор, распознавание, озвучка, mute/hang up/current transcript, язык распознавания. | Телефония, запись/экспорт, voice notes, завершённая карточка, возвращение к звонку, голос/скорость. Диктовка в редактируемый черновик не подтверждена голосовой сессией, которая отправляет фразу в модель. [H] |
| Облачный компьютер — F057–F067 | Браузер, локальные проекты/CLI/файлы, постоянные браузерные профили, preview, ручной шаг. | Работа при выключенном/закрытом исполнителе, общий облачный `/workspace`, полноценные облачные экраны, обновление образа/recovery/reset VM. Локальный каталог сессии Blot существует под другой моделью хранения. [O] |
| Приложения и MCP — F068–F080 | Apple-подключения, MCP HTTP/stdio, выбор инструментов и агентов, отключение. | Нативный OAuth внешних сервисов из каталога, соответствующие multi-account/labels, 1Password, MCP OAuth/headers/подключение через чат. [I] |
| Почта и X — F081–F088 | Почта Apple как отдельный локальный путь; браузер. | Собственный mailbox/aliases, входящие email-триггеры, полноценные внешние mail-коннекторы, штатный X search и авторизованный X plugin. [J] |
| Навыки — F089–F098 | Текстовые skills, версии, параметры, назначение нескольким агентам, запуск из списка и `skill_list`/`skill_run` в чате. | Автоматическое сохранение выполненной процедуры, Teach, публикация команде/ссылки/Sync/Unpublish, Team Bot-specific skill. Запуск по имени имеет основу через discovery/run и не считается полностью отсутствующим. [P] |
| Расписания и события — F099–F112 | Форма, timezone, enable/pause, ручной запуск, статусы/история запусков. | Естественный язык для управления, event/webhook, edit/delete существующей routine, Team Bot visibility; круглосуточное облачное исполнение. [D] |
| Файлы и результаты — F113–F126 | PDF, изображения/OCR, текстовые форматы/код; Markdown/PDF/CSV output; файлы/diff локальной задачи и условная PR-ссылка. | Office, audio/video input, notebooks как поддерживаемый тип, медиа-генерация, медиа-gallery/video player, полноценный download all и внешние storage-коннекторы. [E] |
| Pages/Library — F127–F140 | Файлы, preview, панель рядом с чатом, локальный поиск по имени. | Самостоятельные Page/interactive dashboard/tracker с обновлением, Library по времени/типам, pins, sharing, viewers и управление публикацией. [Q] |
| Согласования — F141–F151 | Prepared actions/digest, разовые разрешения/отказ, ограниченное Always allow, expiry, Keychain, ручной шаг. | Общий Custom Rules CRUD, приоритет конфликтующих Ask first, locked admin rules и auto-review как отдельная политика. Точные 30 минут/отсутствие таймера для чата не подтверждены. [R] |
| Vault/платежи — F152–F163 | Защищённое поле API secret и Keychain; подписка Blot отдельно. | Structured Vault, CSV, фото карты, Hints, Link/X Money/Shop Pay, default method, заказ и пакет покупок с одним согласованием. Write-only управление записями Vault не равно отдельному вводу секрета. [R] |
| Инициатива — F164–F168 | Координатор групп, статус подключения, ошибки, reconnect механизмы Apple/MCP, задания по времени. | Отдельные check-ins по обнаруженным событиям/работе, инициативный primary Bot и follow-up в X Chat. [N, D, I] |
| Team Bots — F169–F182 | Личные агенты одного владельца и группы. | Командные боты с публикацией, sharing, Owner/Manager/Collaborator, приватными разговорами участников, Review learnings, общими accounts/secrets и per-bot analytics. [N] |
| Microsoft Teams — F183–F191 | Специализированного канала не найдено. | Весь законченный flow публикации, admin approval, Link Account, чаты/ветки, OneDrive и обновление/удаление бота. [I] |
| Slack как канал — F192–F198 | Исходящий черновик/отправка через вручную подключённый MCP при подходящем tool schema. | Bot handle, входящие DM/@, ответы в исходной ветке, initiator approval, routine thread, Workspace Access. [I, J] |
| Встречи — F199–F209 | Полного meeting-сценария не найдено. | Meet/Zoom/Teams join, календарный join, интерактивность, meeting transcript, отчёты и действия встречи. Голосовая сессия внутри Blot не считается участием во встрече. [H] |
| Мобильное приложение — F210–F222 | Синхронизация/устройства, боты/группы, черновики по чатам, файлы, голос, routines/history, виджеты, локальные notifications, App Shortcut. | Share Extension/Add to Chat, полный поиск, Pages/sharing, удалённый экран, APNs, Live Activities и полное Siri/Spotlight/Action Button. [C, F, G, L] |
| Физический телефон — F223–F231 | Календарь, контакты, reminders, файлы/Shortcuts, системные разрешения и approval на устройстве. | Location, alarms/timers, Home; полноценное управление именами устройств и единая карточка capability states не подтверждены. У контактов Blot есть также write-операции — поведение отличается от read-only ограничения в присланном реестре. [F] |
| Настройки — F232–F246 | Темы, язык, одноаккаунтная сессия, устройства, локальное исполнение, статусы и chat read/unread/mute. | Multi-account switcher, accent selector, microphone selector, hardware switch, traffic route, updater/restart, request ID; глобальная timezone auto-detect отдельно от timezone routine не подтверждена. [K] |
| Usage/Billing — F247–F254 | Счётчики токенов/вызовов и heatmap, тарифы подписки и web checkout отдельно. | Полный Manage billing, quota/reset, By Bot/By source, additional usage/caps, credits/auto top-up/referral, разбор коммерческого расхода ботом. [K] |
| Администрирование — F255–F269 | Личный аккаунт, доступ конкретным агентам/инструментам и устройствам. | Организации/группы, SSO/SCIM, enterprise policies, Shared Logins, team secrets/scripts, sudo, action recording, audit/OTel/Admin API. [S] |
| Сеть/безопасность — F270–F279 | Есть реальные локальные проверки доступа/URL, device authority, Keychain и удаление аккаунта. | Общие enterprise network policy modes, domain/IP/group allowlists, применение к MCP, статический egress и управляемый retention. Отсутствие этого продукта не означает отсутствие всех мер безопасности. [S] |
| Корпоративная инфраструктура — F280–F285 | Готового managed network flow не найдено. | Desktop route в частную сеть, Team Setup, управляемые Tailscale/Cloudflare, Setup/Check scripts и повторное применение. Установка пользователем внешней CLI не является такой интеграцией. [S] |
| Inference hooks — F286–F295 | Есть внутренняя проверка действий инструментов. | Внешний подписанный prompt frame, HTTPS verdict, validate-tool-calls hook, secret rotation/test/shadow/enforcement/failure policy/rollout/audit. Внутренние guard не заменяют внешний hook. [S] |
| Управление компьютерами — F296–F303 | Pair/revoke устройств; удаление личного аккаунта и данных. | Административные recreate/terminate/delete VM, durable disk, bulk operation/progress/retry/API и retention не найдены. Личное account deletion не засчитывается как массовая операция enterprise. [S] |
| Внешние входы X — F304–F307 | Не найдено. | Приём задания из упоминания, ответ-подтверждение, context thread/quotes, перенос результата в приложение. Нужен собственный вход Blot, не копирование чужого @bot. [J] |
| Deep links — F308–F311 | iOS widget URLs открывают чат/агента по UUID, compose и разделы; auth/connect links отдельно. | Общая схема Mac/iOS для чата с безопасной подстановкой draft, primary fallback и документированным контрактом. [L] |

## Отличия ограничений

Это отдельные продуктовые решения, не доказательство ошибки:

- В присланном описании — до 20 вложений desktop. В `LocalWorkspaceService.execute(.send)` сейчас максимум **8**.
- В присланном описании — разные крупные лимиты для изображений/обычных файлов/видео. `WorkspaceFileService` по умолчанию ограничивает файл **32 MiB** и поддерживает меньший набор форматов.
- Правила 2–6 ботов в группе, 50 routines/бот, интервал 5 минут, 20 запусков истории, 20+20 custom rules нельзя объявлять реализованными только по наличию групп/расписаний/разрешений. Эти пределы требуют отдельных решений и проверок.
- Локальная работа при запущенном Mac и облачная работа при закрытом ноутбуке имеют разные гарантии; синхронизация через cloud не делает локального исполнителя облачным.

## Основания в коде

- **A:** [WorkspaceAgentService](../../packages/BlotWorkspace/Sources/BlotWorkspace/WorkspaceAgentService.swift), [WorkspaceChatActionsMenu](../../apps/shared/WorkspaceV3/WorkspaceChatActionsMenu.swift), [MacAgentCreationView](../../apps/macos/BlotMac/Features/Agents/MacAgentCreationView.swift).
- **B:** [WorkspaceStore](../../apps/shared/WorkspaceV3/WorkspaceStore.swift), особенно блок `perform` и `stopReply`.
- **C:** [PhoneSearchView](../../apps/ios/BlotIOS/Features/Chat/PhoneSearchView.swift), [PhoneSearchResults](../../apps/ios/BlotIOS/Features/Chat/PhoneSearchResults.swift), [WorkspaceLocalSearchView](../../apps/shared/WorkspaceV3/WorkspaceLocalSearchView.swift).
- **D:** [LocalWorkspaceService](../../apps/shared/WorkspaceV3/LocalWorkspaceService.swift), [WorkspaceScheduleService](../../packages/BlotWorkspace/Sources/BlotWorkspace/WorkspaceScheduleService.swift), [PhoneScheduleEditor](../../apps/ios/BlotIOS/Features/Schedules/PhoneScheduleEditor.swift), [WorkspaceTeamViews](../../apps/shared/WorkspaceV3/WorkspaceTeamViews.swift).
- **E:** [WorkspaceFileFormat](../../packages/BlotWorkspace/Sources/BlotWorkspace/WorkspaceFileFormat.swift), [WorkspaceFileService](../../packages/BlotWorkspace/Sources/BlotWorkspace/WorkspaceFileService.swift), [WorkspaceLocalTools](../../packages/BlotWorkspace/Sources/BlotWorkspace/WorkspaceLocalTools.swift), [WorkspaceExportFormat](../../apps/shared/WorkspaceV3/WorkspaceExportFormat.swift).
- **F:** [AppleToolCatalog](../../packages/BlotAppleIntegrations/Sources/BlotAppleIntegrations/AppleToolCatalog.swift), [PluginCatalog](../../packages/BlotAppleIntegrations/Sources/BlotAppleIntegrations/PluginCatalog.swift), [ApplePluginIntents](../../apps/shared/WorkspaceV3/ApplePluginIntents.swift), [BlotWidgets](../../apps/ios/BlotWidgets/BlotWidgets.swift), [PhoneGeneralSettingsView](../../apps/ios/BlotIOS/Features/Settings/PhoneGeneralSettingsView.swift).
- **G:** [PhoneNotifications](../../apps/ios/BlotIOS/Services/PhoneNotifications.swift).
- **H:** [WorkspaceVoiceView](../../apps/shared/WorkspaceV3/WorkspaceVoiceView.swift), [WorkspaceVoiceSettingsView](../../apps/shared/WorkspaceV3/WorkspaceVoiceSettingsView.swift), [AppleVoiceOutput](../../packages/BlotAppleIntegrations/Sources/BlotAppleIntegrations/AppleVoiceOutput.swift).
- **I:** [MCPConfigurationFields](../../apps/shared/WorkspaceV3/MCPConfigurationFields.swift), [WorkspaceMCPSettingsView](../../apps/shared/WorkspaceV3/WorkspaceMCPSettingsView.swift), [WorkspaceMCPService](../../packages/BlotWorkspace/Sources/BlotWorkspace/WorkspaceMCPService.swift), [MacMarketplacePluginDetail](../../apps/macos/BlotMac/Features/Workspace/MacMarketplacePluginDetail.swift), [PhonePluginConnectionView](../../apps/ios/BlotIOS/Features/Plugins/PhonePluginConnectionView.swift).
- **J:** [MCPToolProvider](../../packages/BlotWorkspace/Sources/BlotWorkspace/MCPToolProvider.swift), [WorkspaceConversationCards](../../apps/shared/WorkspaceV3/WorkspaceConversationCards.swift), [AppleToolCatalog](../../packages/BlotAppleIntegrations/Sources/BlotAppleIntegrations/AppleToolCatalog.swift).
- **K:** [MacSettingsGeneralPane](../../apps/macos/BlotMac/Features/Workspace/MacSettingsGeneralPane.swift), [WorkspaceChatStyle](../../apps/shared/WorkspaceV3/WorkspaceChatStyle.swift), [WorkspaceAccountApplicationService](../../apps/shared/WorkspaceV3/WorkspaceAccountApplicationService.swift), [MacSettingsUsagePane](../../apps/macos/BlotMac/Features/Workspace/MacSettingsUsagePane.swift), [PhoneSettingsProfileView](../../apps/ios/BlotIOS/Features/Settings/PhoneSettingsProfileView.swift), [WorkspaceChatActionsMenu](../../apps/shared/WorkspaceV3/WorkspaceChatActionsMenu.swift).
- **L:** [WidgetDestination](../../packages/BlotWidgetSupport/Sources/BlotWidgetSupport/WidgetDestination.swift), [PhoneWidgetNavigation](../../apps/ios/BlotIOS/Features/Widgets/PhoneWidgetNavigation.swift), [WorkspaceRootView](../../apps/shared/WorkspaceV3/WorkspaceRootView.swift), [WorkspaceBrowserLaunch](../../apps/shared/WorkspaceV3/WorkspaceBrowserLaunch.swift).
- **M:** [WorkspaceMemoryService](../../packages/BlotWorkspace/Sources/BlotWorkspace/WorkspaceMemoryService.swift), [WorkspaceContextBuilder](../../packages/BlotWorkspace/Sources/BlotWorkspace/WorkspaceContextBuilder.swift), [PhonePrivacySettingsView](../../apps/ios/BlotIOS/Features/Settings/PhonePrivacySettingsView.swift).
- **N:** [WorkspaceGroupService](../../packages/BlotWorkspace/Sources/BlotWorkspace/WorkspaceGroupService.swift), [WorkspaceGroupResponder](../../apps/shared/WorkspaceV3/WorkspaceGroupResponder.swift), [WorkspaceAgentInstructions](../../packages/BlotWorkspace/Sources/BlotWorkspace/WorkspaceAgentInstructions.swift).
- **O:** [WorkspaceBrowserService](../../packages/BlotWorkspace/Sources/BlotWorkspace/WorkspaceBrowserService.swift), [WorkspaceNativeService](../../packages/BlotWorkspace/Sources/BlotWorkspace/WorkspaceNativeService.swift), [WorkspaceSessionFileService](../../packages/BlotWorkspace/Sources/BlotWorkspace/WorkspaceSessionFileService.swift), [MacChatInspector](../../apps/macos/BlotMac/Features/Workspace/MacChatInspector.swift).
- **P:** [WorkspaceSkillTools](../../packages/BlotWorkspace/Sources/BlotWorkspace/WorkspaceSkillTools.swift), [WorkspaceSkillsView](../../apps/shared/WorkspaceV3/WorkspaceSkillsView.swift), [WorkspaceSkillService](../../packages/BlotWorkspace/Sources/BlotWorkspace/WorkspaceSkillService.swift).
- **Q:** [WorkspaceLocalFileView](../../apps/shared/WorkspaceV3/WorkspaceLocalFileView.swift), [WorkspaceBrowserStartPage](../../apps/shared/WorkspaceV3/WorkspaceBrowserStartPage.swift), [WorkspaceRoute](../../apps/shared/WorkspaceV3/WorkspaceRoute.swift).
- **R:** [WorkspacePermissionService](../../packages/BlotWorkspace/Sources/BlotWorkspace/WorkspacePermissionService.swift), [WorkspaceConversationCardService](../../packages/BlotWorkspace/Sources/BlotWorkspace/WorkspaceConversationCardService.swift), [WorkspaceNativeProjectsView](../../apps/shared/WorkspaceV3/WorkspaceNativeProjectsView.swift), [WorkspaceSettingsViews](../../apps/shared/WorkspaceV3/WorkspaceSettingsViews.swift).
- **S:** [WorkspaceRoute](../../apps/shared/WorkspaceV3/WorkspaceRoute.swift), [CloudExecutionController](../../backend/cloud/src/main/java/dev/blot/cloud/web/CloudExecutionController.java), [WorkspaceAccountErasure](../../packages/BlotWorkspace/Sources/BlotWorkspace/WorkspaceAccountErasure.swift), [WorkspaceDevicePairingView](../../apps/shared/WorkspaceV3/WorkspaceDevicePairingView.swift), проверка наличия соответствующих UI/сервисных точек входа в Apple clients и cloud sources.

Приложение не изменялось и не пересобиралось. Новые проверки на Mac/iPhone, внешние отправки, авторизации и оплаты в этом проходе не выполнялись.
