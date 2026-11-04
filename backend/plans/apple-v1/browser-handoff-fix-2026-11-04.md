# Возврат с сайта в Mac-приложение — 4 ноября 2026

Пользователь сообщил: после «Открыть Blot» на сайте Mac-приложение не открывается.

Диагностика LaunchServices через `NSWorkspace.urlForApplication(toOpen:)` показала, что `blot-agent-macos:/oauth/start` выбирал `.build/mvp-mac/Build/Products/Debug/Blot.app`, тогда как актуальная рабочая сборка находится в `.build/xcode/Build/Products/Debug/Blot.app`. Все копии имели одну bundle ID и build version 1. В shared root дополнительно находились два `.onOpenURL`, вызывавшие разные пути входа.

Исправления:

- Снята регистрация устаревшей тестовой копии `.build/mvp-mac` без удаления её файлов и истории; текущая копия зарегистрирована. Разрешение URL теперь возвращает `.build/xcode/Build/Products/Debug/Blot.app`.
- Штатный скрипт запуска обновляет регистрацию запускаемого app bundle перед `open`. Build number повышен до 2, чтобы новая поставка отличалась от старых копий.
- Оставлен один `.onOpenURL`, `handleBrowserLaunch` направляет событие в общий `openAuthenticationURL`. Вход ожидает завершения загрузки SQLite/сессии и не создаёт второй browser attempt при повторной доставке.
- Добавлены только безопасные OSLog-события получения ссылки и начала/ожидания входа. URL, state, code, verifier, токены и данные аккаунта в журнал не попадают.

Проверки:

- `scripts/check-workspace-v3.sh --browser-launch-only` — PASS: некорректные URL игнорируются; один load при холодном запуске; повтор ссылки запускает один OAuth request; ошибка тестового сервиса не создаёт фиктивный аккаунт.
- Shared app root содержит один `.onOpenURL`.
- Подписанная Mac-сборка 2 собрана, `codesign --verify --strict` и целостность ZIP проходят.
- Тот же URL, который отдаёт сайт, отправлен через системный LaunchServices. Unified log процесса Blot подтвердил `Received website sign-in launch`; уже начатый сеанс не дублируется (`Sign-in already in progress`). Это подтверждает доставку в native handler; завершение пользовательского входа и браузерные разрешения проверяет сам пользователь.
- Визуальный доступ к Blot не использовался. Текущий браузерный вход пользователя при финальной сборке и упаковке не закрывался.

Журналы: `.build/browser-handoff-tests.log`, `.build/browser-handoff-launch.log`, `.build/browser-handoff-runtime.log`, `.build/browser-handoff-final-build.log`. Обновлённый файл: `.build/artifacts/Blot-Mac-personal-dev.zip`.
