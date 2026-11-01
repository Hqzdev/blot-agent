# Blot

ИИ-помощник с агентами. В репозитории находятся наработки приложений Mac/iPhone, Java backend, Swift packages и лендинг. Новый план расширяет продукт до macOS, iOS, Android и Windows; код разрабатывает команда с помощью ИИ.

Требования от 1 ноября 2026: [план и оценка кода](docs/blot-product-plan.md), [полное ТЗ](docs/blot-technical-specification.md), [руководство MCP](docs/integrations/mcp-developer-guide.md). При расхождении с прежними планами применяются эти документы. Целевая основная поставка — 1 декабря 2026; наличие спецификации не означает готовность функций.

## Приложения

Откройте apps/Blot.xcodeproj и выберите BlotMac или BlotIOS. Один проект содержит две цели. Минимум — macOS 26 и iOS 26. Сохранены исходный пользовательский ContentView и ресурсы.

- apps/macos/BlotMac — приложение Mac, папки Features, Models и Services.
- apps/ios/BlotIOS — приложение iOS, папки Features, Models и Services.
- apps/shared — пользовательский общий экран и ресурсы.
- packages — четыре Swift package с общими компонентами, исходниками и тестами.
- backend — четыре модуля Gradle, Java-сервер и системные адаптеры; границы проверки описаны в backend/README.md.
- contracts — OpenAPI и JSON Schema.
- fixtures/contracts — общие примеры данных.

## Сайт и документы

```bash
cd landing
npm ci
npm run dev
```

План находится на /workspace. npm run build обновляет скачиваемые документы, проверяет ссылки и собирает сайт. Документы P0 завершены. A2 и S14 остаются открытыми до реализации и проверок; завершённые задачи получают тег «Выполнено».

Начните с [списка документов](docs/README.md). Команды инструментов описаны в docs/architecture/build-commands.md. Собственные скрипты и реализации помощника удалены; конфигурации сохранены.

## Проверки backend и Swift-пакетов

Настройка SMTP и общего доступа к модели: заполните `.env` по [.env.example](.env.example) и используйте `scripts/run-backend.sh`. [Инструкция](docs/installation-environment.md).

Требования к JDK, Gradle, Swift и Xcode, а также локальные команды и ограничения CI собраны в [инструкции backend](backend/README.md).
