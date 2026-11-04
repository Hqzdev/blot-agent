const completedIds = new Set(["P0.1", "P0.2", "P0.3", "P0.4", "P0.5", "P0.6", "P0.7", "P0.8", "P0.9", "P0.10", "A2.1", "A2.2"]);

const definitions = [
  ["P0.1", "archive/product-scope.md", "Границы продукта", "Сопоставлены платформы, локальное исполнение и 18 требований."],
  ["P0.2", "rules/domain-glossary.md", "Терминология и инварианты", "Разделены профиль/сессия, задача/попытка и receipt/completion."],
  ["P0.3", "rules/chat-to-run.md", "Чат и рабочий запуск", "Разобраны разговор, явная работа, уточнение, повтор и остановка."],
  ["P0.4", "rules/roles-and-gates.md", "Роли и принятие результата", "Определены автор, независимый reviewer, QA и пользовательские gates."],
  ["P0.5", "rules/permission-policy.md", "Политика разрешений", "Проверены protected refs, scope, инвалидация и отдельные commit/push grants."],
  ["P0.6", "rules/supported-projects.md", "Поддерживаемые проекты", "Выбраны Java/Swift control projects и проверяемые дефекты с до/после."],
  ["P0.7", "rules/platform-matrix.md", "Матрица платформ", "Пользователь утвердил минимальные версии: macOS 26 и iOS 26. Проверки приложения на устройствах предстоят."],
  ["P0.8", "rules/tool-boundaries.md", "Границы инструментов", "Определены read, patch, process, Git, сеть и допуск native runner."],
  ["P0.9", "rules/data-lifecycle.md", "Жизненный цикл данных", "Прослежены storage, archive, export, restore и удаление данных Blot."],
  ["P0.10", "archive/acceptance-matrix.md", "Матрица приёмки", "18 требований и 24 блока связаны с экранами, API, задачами и evidence."],
  ["A2.1", "architecture/repo-policy.md", "Репозиторий и Git", "Git, .gitignore и .gitattributes проверены. Main защищена на GitHub: обязательный PR, запрет force push и удаления."],
  ["A2.2", "architecture/apple-targets.md", "Targets macOS и iOS", "Созданы BlotMac и BlotIOS, общие схемы, минимум ОС 26. Проверены сборки приложений; пользовательский экран сохранён."],
  ["A2.3", "architecture/swift-packages.md", "Общие Swift packages", "Подготовлены Package.swift и папки четырёх пакетов. Исходники и тесты пишет пользователь."],
  ["A2.4", "architecture/java-modules.md", "Java-модули", "Настроены четыре модуля Gradle, Wrapper, зависимости и папки. Java-код удалён."],
  ["A2.5", "architecture/composition-root.md", "Composition root", "Описаны интерфейсы, зависимости и сроки жизни. CompositionRoot предстоит написать пользователю."],
  ["A2.6", "architecture/toolchain.md", "Toolchain и версии", "Версии, SHA-256 и lock-файлы подготовлены. Проверки продукта требуют его реализации."],
  ["A2.7", "architecture/formatting.md", "Форматирование и границы", "Настроены EditorConfig, swift-format и Spotless. Проверки границ требует написать пользователь."],
  ["A2.8", "architecture/build-commands.md", "Команды сборки", "Документированы доступные команды Xcode, Gradle и сайта. Общий скрипт требует кода пользователя."],
  ["A2.9", "architecture/ci.md", "CI", "Подготовлен workflow без собственных скриптов. Реальный запуск CI ещё не проверен."],
  ["A2.10", "architecture/fixtures.md", "Общие fixtures", "Подготовлены 12 общих JSON-примеров. Проверки чтения Java и Swift предстоят."],
  ["A2.11", "architecture/contracts.md", "Контракты Swift ↔ Java", "Подготовлены OpenAPI и две JSON Schema. Реализация и проверки совместимости предстоят."],
  ["A2.12", "architecture/logging.md", "Логи и redaction", "Описаны поля логов, ротация и удаление секретов. Реализацию пишет пользователь."],
];

function document(id, relativePath, title, summary, taskId = id) {
  return Object.freeze({ id, taskId, path: `docs/${relativePath}`, title, summary, href: `/workspace/documents/${id}`, downloadUrl: `/project-docs/${relativePath}`, completed: completedIds.has(taskId) });
}

export const architectureDocuments = Object.freeze(definitions.map((entry) => document(...entry)));
export const documentationReview = document("documentation-review", "status/documentation-review.md", "Протокол проверки документов", "Сценарная и структурная проверка документальных результатов.", null);
export const documentationIndex = document("architecture-overview", "README.md", "Архитектура Blot", "Общий индекс решений, границ и открытых работ.", null);
export const implementationPlan = document("implementation-plan", "archive/implementation-plan.md", "Порядок реализации", "Все задачи в порядке зависимостей и список доступных работ.", null);
export const agentDocuments = Object.freeze([
  ["orchestrator", "Оркестратор"],
  ["orchestrator-commands", "Команды оркестратора"],
  ["agent-types", "Типы агентов"],
  ["agent-system-prompts", "Системные инструкции агентов"],
  ["agent-capabilities", "Возможности агентов"],
  ["motes", "Motes: малые специализированные агенты"],
].map(([id, title]) => document(id, `agents/${id}.md`, title, "Документация агентов Blot.", null)));
export const futureDocuments = Object.freeze([
  document("optimization", "rules/optimization.md", "Оптимизация работы Blot", "Целевые правила расходов, скорости и качества.", null),
  document("google-workspace", "integrations/google-workspace.md", "Будущая интеграция Google Workspace", "План Gmail, Calendar и Drive; статус за пределами первой поставки.", null),
]);
export const currentProductDocuments = Object.freeze([
  document("apple-v3-implementation", "status/apple-v3-implementation.md", "Интерфейс Apple v3", "Сверка сущностей, каталог экранов и границы проверки серверных функций.", null),
  document("module-map", "architecture/module-map.md", "Карта модулей Blot", "Кто за что отвечает: 16 блоков ядра, клиенты, облако и приёмка.", null),
  document("domain-model", "architecture/domain-model.md", "Сущности и состояния", "25 сущностей ТЗ, состояния задачи и расхождения с кодом.", null),
  document("grok-bot-character-catalog", "design/grok-bot-character-catalog.md", "Персонажи роли и движения", "Сохранённые варианты Grok Bot, наблюдаемая анимация и требования к компоненту Blot.", null),
  document("blot-product-plan", "product/blot-product-plan.md", "План Blot для четырёх платформ", "Требования от 1 ноября: блоки, архитектура, инфраструктура, сроки и оценка кода.", null),
  document("blot-technical-specification", "product/blot-technical-specification.md", "Техническое задание Blot", "Четыре платформы, CEO и агенты, локальные данные, инструменты, интеграции и приёмка.", null),
  document("mcp-developer-guide", "integrations/mcp-developer-guide.md", "Подключение MCP серверов", "Целевой контракт внешних инструментов: transports, авторизация, разрешения и проверка совместимости.", null),
]);
export const documents = Object.freeze([...currentProductDocuments, ...architectureDocuments, documentationIndex, documentationReview, implementationPlan, ...agentDocuments, ...futureDocuments]);

export function getDocument(id) { return documents.find((item) => item.id === id); }

export function applyDocumentationProgress(tasks) {
  return tasks.map((task) => {
    const artifact = architectureDocuments.find((item) => item.taskId === task.id);
    if (!artifact) return { ...task, status: "planned" };
    return {
      ...task, status: artifact.completed ? "completed" : "planned", deliverables: [artifact],
      documentationSummary: artifact.summary,
      ...(artifact.completed ? { completedAt: "2026-10-11", completionChecks: [artifact.summary, artifact.taskId.startsWith("A2.") ? "Проверки результата записаны в документе задачи и протоколе." : "Проверены полнота документа и сценарии; ссылки и примеры проверяются при сборке."], completionEvidence: documentationReview } : {}),
    };
  });
}
