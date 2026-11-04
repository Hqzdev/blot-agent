# Backend Blot

Java 25, Spring Boot, SQLite и четыре модуля: `core`, `application`, `infrastructure`, `api`. Конкретные адаптеры собираются в `api/workspace/WorkspaceConfiguration`.

## Проверки

Из корня репозитория:

```sh
backend/gradlew --no-daemon -p backend --dependency-verification=strict spotlessCheck check :api:bootJar
BLOT_HTTP_FIXTURES="$PWD/.build/http-fixtures" swift test --package-path packages/BlotAPI
```

Нужен JDK 25. Gradle Wrapper и зависимости зафиксированы lock-файлами и `verification-metadata.xml`. При первом запуске требуется сеть. Полный локальный проход — `scripts/check-backend.sh`.

Java HTTP-проверка сохраняет настоящий ответ v2 в `.build/http-fixtures/workspace-conversation.json`; его читает Swift. Старые фикстуры v1 проверяют исторические DTO, старые HTTP-маршруты закрыты.

## Запуск

SMTP и общий доступ GigaChat можно задать через `.env` в корне репозитория. Начните с `.env.example`, заполните значения и выполните `scripts/run-backend.sh`. Backend сам выбирает модель, а приложение скрывает соответствующие формы настройки. Файл с секретами не включается в сборку.

[Переменные, приоритеты и граница общего сервиса](../docs/status/installation-environment.md).

Для разработки:

```sh
backend/gradlew -p backend :api:bootRun
```

По умолчанию сервер доступен на loopback. Полный режим с Keychain, TLS, сопряжением и VM запускается приложением Mac: `script/build_and_run.sh`. Build phase `Embed Java backend` включён в цель BlotMac, поэтому обычная сборка Xcode тоже добавляет JVM через jlink, JAR, SQLite JNI, Foundation adapter и гостевой runner. Локальная сборка использует ad hoc без Apple-сертификата; App Sandbox остаётся включённым. Если задана настоящая `BLOT_SIGNING_IDENTITY`, применяется Hardened Runtime. Установленная отдельно Java пользователю приложения не нужна.

`script/build_and_run.sh --build-only` собирает и упаковывает приложение без его запуска. Для локального запуска с `.env` используйте `script/build_and_run.sh`: launcher открывает файл и передаёт его через stdin, затем Mac передаёт конфигурацию Java по приватному pipe. Секреты не копируются в `.app`; выбранный публичный CA может быть включён отдельно.

Данные хранятся в Application Support/Blot/local; в App Sandbox это каталог контейнера приложения. Встроенный сервер выбирает свободный TLS-порт и записывает `ready.json`. Основной Swift-процесс хранит секреты в Keychain и обслуживает закрытые pipes Java. Публичного доступа к Keychain через CLI или HTTP нет.

Если параметры не заданы владельцем через окружение, SMTP, личный ключ GigaChat, доверенный CA и параметры модели задаются в приложении. CA выбирается вручную в формате PEM с просмотром SHA-256 перед подтверждением; доверие ограничено HTTP-клиентом GigaChat конкретного аккаунта. REST base URL по умолчанию — `https://api.giga.chat/v1/`. Без этих настроек функции возвращают явные ошибки. Тестовые провайдеры существуют только в проверках.

Для выполнения программ необходимо подготовить гостевую macOS. [Устройство VM](../docs/architecture/virtual-machine-runner.md).

## Контракт и состояние реализации

- [Контракт v2](../contracts/backend-api.md), [OpenAPI](../contracts/openapi.yaml).
- [Фактическая готовность и оставшиеся работы](../docs/status/backend-implementation-progress.md).
- [Требования продукта](../docs/archive/product-scope.md).

Наличие собирающегося адаптера не означает прохождения приёмки на реальном провайдере, подготовленной VM и физическом iPhone. Эти результаты фиксируются отдельно.
