# Домен и общие типы

В корневом Java-пакете и в `agent` лежат ранние доменные типы. `workspace` содержит модель локального Java v2, а `v3` содержит сгенерированные типы общего контракта, используемого также в Swift.

[Папка исходников](https://github.com/Hqzdev/kiln-agent/tree/4e6c47f65e0e734dedc122d586c7bb67d37395a3/backend/core) · [Блок-схемы проекта](../architecture/backend.md)

## С чего начать

- [Entity](src/main/java/dev/blot/core/workspace/Entity.java.md)
- [EntityKind](src/main/java/dev/blot/core/workspace/EntityKind.java.md)
- [ConversationData](src/main/java/dev/blot/core/workspace/conversation/ConversationData.java.md)
- [RunData](src/main/java/dev/blot/core/workspace/projects/RunData.java.md)
- [TaskData](src/main/java/dev/blot/core/workspace/projects/TaskData.java.md)
- [RecordMetadata](src/main/java/dev/blot/core/v3/RecordMetadata.java.md)

## Разделы

| Путь в модуле | Ответственность |
| --- | --- |
| [`src/main/java/dev/blot/core`](src/main/java/dev/blot/core/index.md) | Проект, запуск, спецификация и задача исходной модели. |
| [`src/main/java/dev/blot/core/agent`](src/main/java/dev/blot/core/agent/index.md) | Профили, инструкции, права, роли, назначения и попытки. |
| [`src/main/java/dev/blot/core/v3`](src/main/java/dev/blot/core/v3/index.md) | Модели и состояния из contracts/v3/model.json. Этот пакет поставляет типы данных и используется при проверке общего контракта. |
| [`src/main/java/dev/blot/core/workspace`](src/main/java/dev/blot/core/workspace/index.md) | Общая обёртка, каталог типов и результаты ревью. |
| [`src/main/java/dev/blot/core/workspace/agent`](src/main/java/dev/blot/core/workspace/agent/index.md) | Сессии, конфигурации, назначения и попытки. |
| [`src/main/java/dev/blot/core/workspace/artifact`](src/main/java/dev/blot/core/workspace/artifact/index.md) | Метаданные файла, его происхождение и связь с задачей. |
| [`src/main/java/dev/blot/core/workspace/automation`](src/main/java/dev/blot/core/workspace/automation/index.md) | Параметры и сроки автоматизации. |
| [`src/main/java/dev/blot/core/workspace/billing`](src/main/java/dev/blot/core/workspace/billing/index.md) | Лимиты, зарезервированные и использованные токены. |
| [`src/main/java/dev/blot/core/workspace/conversation`](src/main/java/dev/blot/core/workspace/conversation/index.md) | Чаты и сообщения, память, сводки и входящие сообщения агентов. |
| [`src/main/java/dev/blot/core/workspace/execution`](src/main/java/dev/blot/core/workspace/execution/index.md) | Генерации, запросы моделей и операции инструментов. |
| [`src/main/java/dev/blot/core/workspace/identity`](src/main/java/dev/blot/core/workspace/identity/index.md) | Аккаунты, сессии, устройства, сопряжение и разрешения. |
| [`src/main/java/dev/blot/core/workspace/planning`](src/main/java/dev/blot/core/workspace/planning/index.md) | Шаги, требования и связи их покрытия. |
| [`src/main/java/dev/blot/core/workspace/profile`](src/main/java/dev/blot/core/workspace/profile/index.md) | Настройки агента, применяемые при подготовке сессии. |
| [`src/main/java/dev/blot/core/workspace/projects`](src/main/java/dev/blot/core/workspace/projects/index.md) | Проект, запуск, задачи и служебная очистка. |
| [`src/main/java/dev/blot/core/workspace/provider`](src/main/java/dev/blot/core/workspace/provider/index.md) | Модель, объём контекста и пределы расхода. |
| [`src/main/java/dev/blot/core/workspace/skills`](src/main/java/dev/blot/core/workspace/skills/index.md) | Инструкция, список ролей и активность навыка. |

## Файлы в корне модуля

- [build.gradle.kts](build.gradle.kts.md)
- [gradle.lockfile](gradle.lockfile.md)
