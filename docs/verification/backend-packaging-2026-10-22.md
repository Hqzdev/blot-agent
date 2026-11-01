# Упаковка backend и настройки владельца — 22 октября 2026

## Причина ошибки

Стандартная сборка Xcode в `~/Library/Developer/Xcode/DerivedData/.../Blot.app` не содержала `Backend/blot-backend.jar` и встроенную Java. Отдельная сборка в `.build/xcode` содержала их. Цель BlotMac не вызывала упаковщик автоматически.

## Изменения

- В BlotMac добавлен обязательный build phase `Embed Java backend`. Ошибка Gradle, jlink или упаковки завершает сборку ошибкой.
- Launcher использует этот же build phase и проверяет наличие JAR/Java до открытия приложения. Добавлен режим `--build-only`.
- Для локальной сборки применяется ad hoc без Apple identity и без Hardened Runtime. Настоящая identity включает Hardened Runtime при подписи. App Sandbox и VM-изоляция выполнения команд сохранены.
- Настройки владельца читаются из `.env` как данные. Для локального запуска launcher передаёт `.env` через приватный FIFO в stdin; Mac отправляет bootstrap Java по приватному pipe. Значения не попадают в аргументы, outbox или `.app`.
- В bundle может входить только явно выбранный публичный CA; копируются исключительно PEM-блоки сертификатов. Секреты, соседний текст и приватные ключи не включаются.
- При конфигурации SMTP/модели владельцем аккаунтам не требуется вводить эти настройки; API не разрешает заменить их пользовательскими командами.

## Материалы сборки

Выполнены компиляция Java, форматирование и сборка Mac, без запуска тестов:

```sh
script/build_and_run.sh --build-only
xcodebuild -quiet -project apps/Blot.xcodeproj -scheme BlotMac -configuration Debug -destination 'platform=macOS,arch=arm64' CODE_SIGNING_ALLOWED=NO build
```

Оба процесса завершились с кодом 0. Логи: `.build/env-packaged-build.log`, `.build/env-xcode-default-build.log`.

JAR в `.build/xcode/.../Blot.app` совпадает с `backend/api/build/libs/blot-backend.jar`. Встроенная Java присутствует; подпись Java показывает ad hoc без флага runtime. Entitlements основного приложения содержат `com.apple.security.app-sandbox = true`. Упаковщик выполняет `codesign --verify --deep --strict`. Файлов `.env` в bundle нет; корневой `.env` игнорируется Git.

## Что не подтверждено

Приложение, JVM внутри App Sandbox, реальные SMTP/GigaChat, VM и физический iPhone этим проходом не запускались. Сборка не заменяет приёмку этих сценариев. Результаты старых тестов не объявляются результатами этого изменения.

Общие секреты распространяемых пользовательских DMG должны храниться на сервере владельца. Настройка `.env` на одной машине не создаёт общий серверный сервис и не подключает к нему остальные установки.

## Диагностика ошибки запуска −10810

В системном журнале 22 октября зафиксированы `System Policy: xpcproxy ... deny(1) file-read-data .../Desktop/klin-agent/.env` и `launchd: Unable to open stdin path ... Operation not permitted`. LaunchServices возвращал −10810 до запуска приложения. Прямой путь к `.env` заменён на приватный FIFO во временном каталоге. Чтение stdin в Swift выполняется до EOF, поскольку pipe может отдавать данные частями.

Отдельно процесс Blot PID 4253 находился в состоянии `TX` под Xcode debugserver. Прежний `pkill -x Blot` отправлял SIGTERM, на котором останавливался отладчик. Теперь скрипт сообщает о таком процессе до сборки и предлагает завершить отладку в Xcode.

После исправления `script/build_and_run.sh --build-only` завершился с кодом 0. Лог: `.build/launch-fix-build.log`. Синтаксис скрипта проверен через `bash -n`; `git diff --check` не обнаружил ошибок пробелов.

Фактический запуск после этих изменений требует отдельного подтверждения; системные журналы устанавливают причину прежнего отказа, но не заменяют проверку нового запуска.
