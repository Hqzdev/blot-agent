# Доступ к выбранному репозиторию на Mac

> **Статус: октябрьская версия.** Если здесь написано иначе, чем в [ТЗ от 1 ноября 2026](../product/blot-technical-specification.md), верно ТЗ.

1. Settings → Git & GitHub открывает системный выбор папки.
2. `ProjectBookmarks` сохраняет app-scoped bookmark в контейнере приложения. При запуске работающего backend новый выбор можно подтвердить через `project.access`.
3. Java получает transferable bookmark только через унаследованные pipes `MacPlatformBroker`. В HTTP JSON и окружение процессов он не попадает.
4. `MacProjectAccess` загружает `libBlotProjectAccess.dylib`. Небольшой Foundation JNI adapter разрешает bookmark внутри самого Java-процесса и сверяет фактический путь с ожидаемым.
5. Открытые области удерживаются до остановки backend. При следующем запуске восстанавливаются доступные папки сохранённых проектов. Устаревший bookmark требует нового выбора на Mac.
6. Правила владельца, роли, разрешённых путей и отдельных действий продолжают проверяться в Java. Наличие системного доступа не выдаёт агенту права на изменение.

Самостоятельный сервер использует права OS-пользователя, который его запустил. Для встроенного режима включены App Sandbox, доступ к выбранным папкам и app-scoped bookmarks; глобальное отключение sandbox не используется.

Общий репозиторий не передаётся гостевой VM: туда попадает только проверенная staging-копия рабочей области без `.git` и секретов. Native adapter относится к доступу доверенного backend, а выполнение сгенерированного кода остаётся в VM.

Библиотека собирается `scripts/build-native-helpers.sh` и подписывается вместе с остальным вложенным кодом. Проверка в настоящем App Sandbox требует подписанного приложения; сейчас подтверждены сборки, а такой запуск отложен владельцем проекта.

## Источники API

- [Apple: startAccessingSecurityScopedResource](https://developer.apple.com/documentation/foundation/nsurl/startaccessingsecurityscopedresource()).
- [Apple: accessing files from the macOS App Sandbox](https://developer.apple.com/documentation/security/accessing-files-from-the-macos-app-sandbox).
- [Java 25: System.load](https://docs.oracle.com/en/java/javase/25/docs/api/java.base/java/lang/System.html#load(java.lang.String)).
