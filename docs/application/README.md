# Прикладные сценарии Java

Модуль отвечает за правила работы локального workspace: чаты, планы, задачи, вызовы модели, разрешения и обработку команд. Внешние действия и хранение доступны через порты.

[Папка исходников](https://github.com/Hqzdev/kiln-agent/tree/4e6c47f65e0e734dedc122d586c7bb67d37395a3/backend/application) · [Блок-схемы проекта](../architecture/backend.md)

## С чего начать

- [CommandDispatcher](src/main/java/dev/blot/application/workspace/commands/CommandDispatcher.java.md)
- [ConversationService](src/main/java/dev/blot/application/workspace/conversation/ConversationService.java.md)
- [GenerationWorker](src/main/java/dev/blot/application/workspace/execution/GenerationWorker.java.md)
- [WorkflowScheduler](src/main/java/dev/blot/application/workspace/execution/WorkflowScheduler.java.md)
- [WorkspaceStore](src/main/java/dev/blot/application/ports/WorkspaceStore.java.md)

## Разделы

| Путь в модуле | Ответственность |
| --- | --- |
| [`src/main/java/dev/blot/application`](src/main/java/dev/blot/application/index.md) | Сценарии проектов, запусков, ревизий и задач с транзакцией и outbox. |
| [`src/main/java/dev/blot/application/agent`](src/main/java/dev/blot/application/agent/index.md) | Создание назначений, сессий и попыток задачи. |
| [`src/main/java/dev/blot/application/ports`](src/main/java/dev/blot/application/ports/index.md) | Интерфейсы, через которые сценарии используют хранилище и внешние системы. |
| [`src/main/java/dev/blot/application/workspace`](src/main/java/dev/blot/application/workspace/index.md) | Доступ к записям, версии, ошибки, обслуживание и области путей. |
| [`src/main/java/dev/blot/application/workspace/agent`](src/main/java/dev/blot/application/workspace/agent/index.md) | Контекст роли, обработка результата, файлы, коммуникации и делегирование. |
| [`src/main/java/dev/blot/application/workspace/artifact`](src/main/java/dev/blot/application/workspace/artifact/index.md) | Очистка содержимого, для которого больше нет действующей ссылки. |
| [`src/main/java/dev/blot/application/workspace/automation`](src/main/java/dev/blot/application/workspace/automation/index.md) | Сохранение автоматизаций и создание запусков по времени. |
| [`src/main/java/dev/blot/application/workspace/billing`](src/main/java/dev/blot/application/workspace/billing/index.md) | Локальный резерв и фактическое списание модельного расхода. |
| [`src/main/java/dev/blot/application/workspace/commands`](src/main/java/dev/blot/application/workspace/commands/index.md) | Квитанции клиентских команд и определения инструментов модели. |
| [`src/main/java/dev/blot/application/workspace/conversation`](src/main/java/dev/blot/application/workspace/conversation/index.md) | Сообщения, контекст модели, сводки и проверка локальной сессии. |
| [`src/main/java/dev/blot/application/workspace/data`](src/main/java/dev/blot/application/workspace/data/index.md) | Диагностика, удаление данных проекта и экспорт. |
| [`src/main/java/dev/blot/application/workspace/execution`](src/main/java/dev/blot/application/workspace/execution/index.md) | Очереди, генерации, задачи, инструменты и обработка прерываний. |
| [`src/main/java/dev/blot/application/workspace/git`](src/main/java/dev/blot/application/workspace/git/index.md) | Подготовка Git-действий и управление их выполнением. |
| [`src/main/java/dev/blot/application/workspace/identity`](src/main/java/dev/blot/application/workspace/identity/index.md) | Локальная почтовая проверка, доверие устройств и токены. |
| [`src/main/java/dev/blot/application/workspace/integrations`](src/main/java/dev/blot/application/workspace/integrations/index.md) | Интеграция принятых изменений, финальные проверки и итоговая приёмка. |
| [`src/main/java/dev/blot/application/workspace/library`](src/main/java/dev/blot/application/workspace/library/index.md) | Навыки и перенос проектов из предыдущего формата. |
| [`src/main/java/dev/blot/application/workspace/permissions`](src/main/java/dev/blot/application/workspace/permissions/index.md) | Запись подготовленного действия и проверка одноразового разрешения. |
| [`src/main/java/dev/blot/application/workspace/profile`](src/main/java/dev/blot/application/workspace/profile/index.md) | Выбор и фиксация конфигурации агента для сессии. |
| [`src/main/java/dev/blot/application/workspace/projects`](src/main/java/dev/blot/application/workspace/projects/index.md) | Создание и изменение проекта с учётом доступа к каталогу. |
| [`src/main/java/dev/blot/application/workspace/providers`](src/main/java/dev/blot/application/workspace/providers/index.md) | Выбор параметров, доверие TLS провайдера и обработка ответа. |
| [`src/main/java/dev/blot/application/workspace/requirements`](src/main/java/dev/blot/application/workspace/requirements/index.md) | Сопоставление требований с шагами предлагаемого плана. |
| [`src/main/java/dev/blot/application/workspace/review`](src/main/java/dev/blot/application/workspace/review/index.md) | Сценарии проверки и решения по результатам задач. |
| [`src/main/java/dev/blot/application/workspace/statistics`](src/main/java/dev/blot/application/workspace/statistics/index.md) | Агрегация локальных данных о работе и токенах. |
| [`src/test/java/dev/blot/application`](src/test/java/dev/blot/application/index.md) | Тесты прикладного фасада. |
| [`src/test/java/dev/blot/application/workspace`](src/test/java/dev/blot/application/workspace/index.md) | Тесты путей и связей требований с планом. |

## Файлы в корне модуля

- [README.md](README.md.md)
- [build.gradle.kts](build.gradle.kts.md)
- [gradle.lockfile](gradle.lockfile.md)
