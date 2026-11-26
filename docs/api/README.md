# Локальный HTTP API

Модуль принимает команды, проверяет сеанс и выдаёт записи или поток событий Java v2. Здесь Spring собирает прикладные сервисы с конкретными адаптерами.

[Папка исходников](../../backend/api) · [Блок-схемы проекта](../architecture/backend.md)

## С чего начать

- [BlotServer](src/main/java/dev/blot/api/BlotServer.java.md)
- [WorkspaceConfiguration](src/main/java/dev/blot/api/workspace/WorkspaceConfiguration.java.md)
- [WorkspaceController](src/main/java/dev/blot/api/workspace/controllers/WorkspaceController.java.md)
- [EventController](src/main/java/dev/blot/api/workspace/controllers/EventController.java.md)
- [HttpApiTest](src/test/java/dev/blot/api/HttpApiTest.java.md)

## Разделы

| Путь в модуле | Ответственность |
| --- | --- |
| [`src/main/java/dev/blot/api`](src/main/java/dev/blot/api/index.md) | Точка входа Spring Boot, проверки готовности и форматирование транспортных ответов. |
| [`src/main/java/dev/blot/api/workspace`](src/main/java/dev/blot/api/workspace/index.md) | Связывает интерфейсы приложения с конкретными реализациями. |
| [`src/main/java/dev/blot/api/workspace/auth`](src/main/java/dev/blot/api/workspace/auth/index.md) | HTTP-авторизация v2 и ограничение попыток. |
| [`src/main/java/dev/blot/api/workspace/commands`](src/main/java/dev/blot/api/workspace/commands/index.md) | Имена команд API и перевод полезной нагрузки в вызов конкретного сценария. |
| [`src/main/java/dev/blot/api/workspace/controllers`](src/main/java/dev/blot/api/workspace/controllers/index.md) | Команды, записи, SSE, экспорт, диагностика и статистика. |
| [`src/main/java/dev/blot/api/workspace/installation`](src/main/java/dev/blot/api/workspace/installation/index.md) | Чтение настроек запуска и публикация состояния локального сервера. |
| [`src/main/java/dev/blot/api/workspace/security`](src/main/java/dev/blot/api/workspace/security/index.md) | TLS, проверка запросов и локальная настройка провайдера и почты. |
| [`src/main/java/dev/blot/api/workspace/transport`](src/main/java/dev/blot/api/workspace/transport/index.md) | Определение участника запроса и курсоры списка записей. |
| [`src/main/resources`](src/main/resources/index.md) | Конфигурация локального API и его логирования. |
| [`src/test/java/dev/blot/api`](src/test/java/dev/blot/api/index.md) | Тесты реального HTTP-ответа и чтения общих форматов. |

## Файлы в корне модуля

- [build.gradle.kts](build.gradle.kts.md)
- [gradle.lockfile](gradle.lockfile.md)
