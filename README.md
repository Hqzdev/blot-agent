# Blot

ИИ-помощник с агентами. В репозитории находятся наработки приложений Mac/iPhone, Java backend, Swift packages и лендинг. Новый план расширяет продукт до macOS, iOS, Android и Windows; код разрабатывает команда с помощью ИИ.

Требования от 1 ноября 2026: [план и оценка кода](docs/product/blot-product-plan.md), [полное ТЗ](docs/product/blot-technical-specification.md), [руководство MCP](docs/integrations/mcp-developer-guide.md). При расхождении с прежними планами применяются эти документы. Целевая основная поставка — 1 декабря 2026; наличие спецификации не означает готовность функций.

## Приложения

Откройте apps/Blot.xcodeproj и выберите BlotMac или BlotIOS. Один проект содержит две цели. Минимум — macOS 26 и iOS 26. Точки входа открывают интерфейс v3 по ноябрьским макетам. Серверные действия v3 пока недоступны; прежний backend v2 не запускается интерфейсом автоматически.

- apps/macos/BlotMac — приложение Mac, папки Features, Models и Services.
- apps/ios/BlotIOS — приложение iOS, папки Features, Models и Services.
- apps/shared/WorkspaceV3 — 53 экрана, независимые черновики форм, навигация и каталог предпросмотра; общие ресурсы сохранены.
- packages — четыре Swift package с общими компонентами, исходниками и тестами.
- backend — четыре модуля Gradle, Java-сервер и системные адаптеры; границы проверки описаны в backend/README.md.
- contracts — OpenAPI и JSON Schema.
- fixtures/contracts — общие примеры данных.

Новые модели и схемы находятся в `contracts/v3`, примеры — в `fixtures/v3`. [Сверка 25 сущностей и границы реализации](docs/status/apple-v3-implementation.md). В Debug доступен каталог экранов; аргументы `--workspace-preview --screen 05-new-task` включают только тестовые данные. Предпросмотр не выполняет внешних действий. Сборки и проверка интерфейса не означают прохождение функциональной приёмки BLOT-01…30.

## Сайт и документы

```bash
cd landing
npm ci
npm run dev
```

План находится на /workspace. npm run build обновляет скачиваемые документы, проверяет ссылки и собирает сайт. Документы P0 завершены. A2 и S14 остаются открытыми до реализации и проверок; завершённые задачи получают тег «Выполнено».

Начните с [списка документов](docs/README.md). Команды инструментов описаны в docs/architecture/build-commands.md. Собственные скрипты и реализации помощника удалены; конфигурации сохранены.

## Проверки backend и Swift-пакетов

Настройка SMTP и общего доступа к модели: заполните `.env` по [.env.example](.env.example) и используйте `scripts/run-backend.sh`. [Инструкция](docs/status/installation-environment.md).

Требования к JDK, Gradle, Swift и Xcode, а также локальные команды и ограничения CI собраны в [инструкции backend](backend/README.md).
