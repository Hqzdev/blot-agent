# Как работает Blot

По блок-схемам можно проследить, куда уходит запрос пользователя, где выполняется работа и какие данные сохраняются. Разбор каждого файла доступен в [оглавлении бэкенда](../README.md#бэкенд-по-файлам).

Документация описывает код ветки `mac/workspace` на ревизии [`4e6c47f`](https://github.com/Hqzdev/kiln-agent/tree/4e6c47f65e0e734dedc122d586c7bb67d37395a3). Ссылки на исходники, которые отличаются от `mac/main`, ведут на эту ревизию.

## Карта системы

```mermaid
flowchart LR
    Apple["Клиенты Mac и iPhone"] --> Swift["Общее Swift-ядро BlotWorkspace"]
    Swift --> AppleDB[("SQLite на устройстве")]
    Swift --> Site["Next.js в landing"]
    Swift -.->|"API relay и координации"| Cloud["Java Cloud v1"]
    Browser["Веб-браузер"] --> Site
    CLI["Терминальный клиент"] -->|"Модельный API CLI"| Site
    Site -->|"Аккаунты и снимки workspace"| PG[("PostgreSQL")]
    Site -->|"Веб-приложение и поток модели"| Upstream["Отдельный веб-сервис"]
    Upstream --> Giga["GigaChat"]
    Site -->|"Модельный маршрут CLI"| Giga
    Cloud --> CloudDB[("SQLite облачного Java-сервера")]
    Cloud --> Giga
    V2Client["Клиент локального Java API"] --> Local["Spring Boot API v2"]
    Local --> LocalDB[("SQLite локального Java workspace")]
    Local --> Giga
```

Локальные данные Swift и Java v2 хранятся в разных базах. Java Cloud и веб-сервис аккаунтов также используют разные хранилища. При наличии URL PostgreSQL маршруты авторизации сайта работают через `landing/lib/accounts`. В штатной серверной ветке без этого URL `accountRequest` перенаправляет поддерживаемые вызовы в Java Cloud. Связь Swift с Java Cloud на схеме обозначает интерфейсы репликации и координации, доступные в коде.

См. [запуск Apple workspace](https://github.com/Hqzdev/kiln-agent/blob/4e6c47f65e0e734dedc122d586c7bb67d37395a3/apps/shared/WorkspaceV3/WorkspaceRootView.swift), [выбор сервиса аккаунтов](https://github.com/Hqzdev/kiln-agent/blob/4e6c47f65e0e734dedc122d586c7bb67d37395a3/landing/lib/auth/config.mjs), [прокси веб-приложения](https://github.com/Hqzdev/kiln-agent/blob/4e6c47f65e0e734dedc122d586c7bb67d37395a3/landing/proxy.js), [модель аккаунта Apple](https://github.com/Hqzdev/kiln-agent/blob/4e6c47f65e0e734dedc122d586c7bb67d37395a3/packages/BlotWorkspace/Sources/BlotWorkspace/ChatModel.swift), [маршрут CLI](https://github.com/Hqzdev/kiln-agent/blob/4e6c47f65e0e734dedc122d586c7bb67d37395a3/landing/app/v1/cli/model/route.js) и [базу Java Cloud](../cloud/src/main/java/dev/blot/cloud/storage/CloudDatabase.java.md).

## Зависимости Java-модулей

Стрелки показывают зависимости при сборке. `api` и `cloud` собираются в отдельные JAR.

```mermaid
flowchart TD
    API["api · локальный сервер v2"] --> App["application · сценарии и порты"]
    API --> Infra["infrastructure · адаптеры"]
    Cloud["cloud · облачный сервер v1"] --> App
    Cloud --> Infra
    Infra --> App
    App --> Core["core · доменные и контрактные типы"]
```

См. [api](../api/README.md), [application](../application/README.md), [infrastructure](../infrastructure/README.md), [core](../core/README.md) и [cloud](../cloud/README.md). Формат v3 задаётся [`contracts/v3/model.json`](https://github.com/Hqzdev/kiln-agent/blob/4e6c47f65e0e734dedc122d586c7bb67d37395a3/contracts/v3/model.json) и используется для генерации Java- и Swift-типов. Версия общего формата данных и префикс HTTP-маршрута относятся к разным частям системы.

## Локальная Java-команда и события v2

```mermaid
flowchart TD
    Request["POST /v2/commands"] --> Actor["Проверить сессию и определить владельца"]
    Actor --> Dispatch["CommandDispatcher"]
    Dispatch --> Seen{"Есть квитанция для commandId?"}
    Seen -->|"Да, содержимое совпадает"| Receipt["Вернуть сохранённую квитанцию"]
    Seen -->|"Да, содержимое отличается"| Conflict["Вернуть конфликт 409"]
    Seen -->|"Нет"| Handler["Выполнить прикладной сценарий"]
    Handler --> Save["В одной транзакции сохранить записи, события и квитанцию"]
    Save --> Accepted["Вернуть квитанцию accepted"]
    Save --> Poll["Клиент читает SSE после своего курсора"]
    Poll --> View["Перечитать изменённые записи или получить snapshot"]
```

Для отправки сообщения сценарий сохраняет сообщение и добавляет запись генерации в очередь. Фоновый обработчик вызывает модель и пишет ход и результат в хранилище. Клиент наблюдает обновления через SSE. Квитанция `accepted` появляется в момент приёма команды. Итог генерации лежит в записях диалога и генерации.

См. [WorkspaceController](../api/src/main/java/dev/blot/api/workspace/controllers/WorkspaceController.java.md), [CommandDispatcher](../application/src/main/java/dev/blot/application/workspace/commands/CommandDispatcher.java.md), [ConversationService](../application/src/main/java/dev/blot/application/workspace/conversation/ConversationService.java.md), [GenerationWorker](../application/src/main/java/dev/blot/application/workspace/execution/GenerationWorker.java.md) и [EventController](../api/src/main/java/dev/blot/api/workspace/controllers/EventController.java.md).

## План, агент и подтверждение действия в Java v2

```mermaid
flowchart TD
    Goal["Цель и требования пользователя"] --> Plan{"Модель сформировала план?"}
    Plan -->|"Нужно уточнение"| Question["RunService сохраняет вопрос пользователю"]
    Plan -->|"Есть план"| Coverage["RunService проверяет шаги и покрытие требований"]
    Coverage --> Approval["Пользователь утверждает план"]
    Approval --> Scheduler["WorkflowScheduler ждёт принятия зависимостей"]
    Scheduler --> Agent["Агент выполняет шаг"]
    Agent --> Permission{"Инструмент требует подтверждения?"}
    Permission -->|"Да"| Prepare["Сохранить подготовленное действие"]
    Prepare --> Grant["Пользователь выдаёт разрешение"]
    Grant --> Executor["Адаптер выполняет разрешённое действие"]
    Permission -->|"Нет"| Result["Сохранить результат шага"]
    Executor --> Result
    Result --> Review["Передать результат на ревью, когда требуется"]
    Review --> Accepted{"Результаты всех шагов приняты?"}
    Accepted -->|"Есть готовые шаги"| Scheduler
    Accepted -->|"Да"| Integration["Свести результаты и провести финальные проверки"]
    Integration --> Done["Итоговая приёмка пользователем"]
```

При неизвестном итоге внешней операции `ToolRecoveryService` сверяет сохранённое состояние операции. Подготовленные действия привязаны к параметрам и проверяются перед выполнением.

См. [RunService](../application/src/main/java/dev/blot/application/workspace/execution/RunService.java.md), [WorkflowScheduler](../application/src/main/java/dev/blot/application/workspace/execution/WorkflowScheduler.java.md), [PermissionService](../application/src/main/java/dev/blot/application/workspace/permissions/PermissionService.java.md), [PreparedActionExecutor](../application/src/main/java/dev/blot/application/workspace/execution/PreparedActionExecutor.java.md), [ToolRecoveryService](../application/src/main/java/dev/blot/application/workspace/execution/ToolRecoveryService.java.md) и [IntegrationService](../application/src/main/java/dev/blot/application/workspace/integrations/IntegrationService.java.md).

## Чат Apple и ответ модели

```mermaid
flowchart TD
    UI["Отправить сообщение на Mac или iPhone"] --> Service["LocalWorkspaceService"]
    Service --> Chat["WorkspaceChatService сохраняет сообщение"]
    Chat --> DB[("Локальная SQLite workspace-v3")]
    Chat --> Runtime["WorkspaceModelRuntime"]
    Runtime --> Model{"Какая модель настроена?"}
    Model -->|"Модель аккаунта"| Site["Потоковый маршрут сайта /app/api/model/chat"]
    Model -->|"Свой совместимый провайдер"| Custom["Настроенный HTTP API"]
    Site --> Response["Текст, вызовы инструментов и расход из потока"]
    Custom --> Response
    Response --> Tools{"Нужен вызов инструмента?"}
    Tools -->|"Да"| LocalTool["Локальный реестр инструментов и проверки доступа"]
    LocalTool --> Runtime
    Tools -->|"Ответ готов"| Save["Сохранить итог сообщения и модельного шага"]
    Save --> DB
    Save --> Update["Обновить чат в приложении"]
```

Swift-ядро записывает состояние сообщения и модельного шага. Модель аккаунта получает токен сессии и запрашивает поток через сайт. Доступные локальные инструменты зависят от конфигурации агента, прав и устройства.

См. [LocalWorkspaceService](https://github.com/Hqzdev/kiln-agent/blob/4e6c47f65e0e734dedc122d586c7bb67d37395a3/apps/shared/WorkspaceV3/LocalWorkspaceService.swift), [WorkspaceChatService](https://github.com/Hqzdev/kiln-agent/blob/4e6c47f65e0e734dedc122d586c7bb67d37395a3/packages/BlotWorkspace/Sources/BlotWorkspace/WorkspaceChatService.swift), [WorkspaceModelRuntime](https://github.com/Hqzdev/kiln-agent/blob/4e6c47f65e0e734dedc122d586c7bb67d37395a3/packages/BlotWorkspace/Sources/BlotWorkspace/WorkspaceModelRuntime.swift) и [модель аккаунта](https://github.com/Hqzdev/kiln-agent/blob/4e6c47f65e0e734dedc122d586c7bb67d37395a3/packages/BlotWorkspace/Sources/BlotWorkspace/ChatModel.swift).

## Вход в приложение Apple через сайт

```mermaid
flowchart TD
    Start["Приложение начинает вход с PKCE"] --> Browser["Сайт открывается в браузере"]
    Browser --> SignIn["Пользователь подтверждает аккаунт"]
    SignIn --> Code["Сервис выдаёт одноразовый код для клиента"]
    Code --> Return["Браузер возвращает код в приложение"]
    Return --> Exchange["Приложение отправляет код и PKCE verifier"]
    Exchange --> Session["Сервис проверяет код и выдаёт сессию"]
    Session --> Workspace["Приложение открывает локальный workspace аккаунта"]
```

Сервис проверяет соответствие кода исходному запросу. Приложение сохраняет сессию в хранилище учётных данных и открывает SQLite рабочего пространства по идентификаторам аккаунта и workspace.

См. [WorkspaceBrowserAuthorization](../../packages/BlotWorkspace/Sources/BlotWorkspace/WorkspaceBrowserAuthorization.swift), [WorkspaceCloudSession](../../packages/BlotWorkspace/Sources/BlotWorkspace/WorkspaceCloudSession.swift), [коды сайта](https://github.com/Hqzdev/kiln-agent/blob/4e6c47f65e0e734dedc122d586c7bb67d37395a3/landing/lib/accounts/browser-codes.mjs), [CloudBrowserAuthorization](../cloud/src/main/java/dev/blot/cloud/identity/CloudBrowserAuthorization.java.md) и [открытие workspace](https://github.com/Hqzdev/kiln-agent/blob/4e6c47f65e0e734dedc122d586c7bb67d37395a3/apps/shared/WorkspaceV3/WorkspaceAccountApplicationService.swift).

## Снимки аккаунта и зашифрованный relay

```mermaid
flowchart TD
    subgraph Account["Снимки аккаунта через веб-сервис"]
        Local1["SQLite первого Apple-устройства"] --> Backup["WorkspaceCloudBackup готовит снимок"]
        Backup --> Server["Маршрут /v1/workspace/backups принимает части"]
        Server --> PG[("PostgreSQL · снимки аккаунта")]
        PG --> Restore["Второе устройство скачивает части и сверяет хеш"]
        Restore --> Local2["Установить снимок в локальную SQLite"]
    end
    subgraph Relay["Транспорт изменений через Java Cloud"]
        Outbox["Исходящие изменения workspace"] --> Seal["Swift подписывает и шифрует пакеты"]
        Seal --> Transfer["CloudRelay сохраняет и отдаёт пакеты по курсору"]
        Transfer --> Open["Получатель проверяет подпись и расшифровывает"]
        Open --> Apply["Применить изменения и сохранить курсор"]
        Apply --> ACK["Отправить подтверждение relay"]
    end
```

Обычный запуск аккаунта Apple включает `WorkspaceCloudBackup`. Он загружает снимок частями и проверяет его целостность при скачивании. Для `CloudRelay` шифрование и расшифровка происходят на устройствах. В Swift также есть обмен напрямую между доверенными устройствами через `WorkspacePeerSync` и отдельный транспорт сопряжения находящихся рядом устройств.

См. [WorkspaceCloudBackup](https://github.com/Hqzdev/kiln-agent/blob/4e6c47f65e0e734dedc122d586c7bb67d37395a3/packages/BlotWorkspace/Sources/BlotWorkspace/WorkspaceCloudBackup.swift), [сервер снимков аккаунта](https://github.com/Hqzdev/kiln-agent/blob/4e6c47f65e0e734dedc122d586c7bb67d37395a3/landing/lib/accounts/workspace-backups.mjs), [WorkspaceSyncEngine](../../packages/BlotWorkspace/Sources/BlotWorkspace/WorkspaceSyncEngine.swift), [CloudRelay](../cloud/src/main/java/dev/blot/cloud/relay/CloudRelay.java.md), [WorkspacePeerSync](../../packages/BlotWorkspace/Sources/BlotWorkspace/WorkspacePeerSync.swift) и [транспорт сопряжения](../../apps/shared/WorkspaceV3/WorkspaceNearbyPairingTransport.swift).
