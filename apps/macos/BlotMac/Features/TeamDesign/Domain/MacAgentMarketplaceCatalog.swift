import Foundation

enum MacAgentMarketplaceCatalog {
    enum Category: String, CaseIterable {
        case productivity, content, research, sales, support, finance, design, engineering, operations, learning

        func title(russian: Bool) -> String {
            switch self {
            case .productivity: russian ? "Планирование" : "Productivity"
            case .content: russian ? "Контент" : "Content"
            case .research: russian ? "Исследования" : "Research"
            case .sales: russian ? "Продажи" : "Sales"
            case .support: russian ? "Поддержка" : "Support"
            case .finance: russian ? "Финансы" : "Finance"
            case .design: russian ? "Дизайн" : "Design"
            case .engineering: russian ? "Разработка" : "Engineering"
            case .operations: russian ? "Операции" : "Operations"
            case .learning: russian ? "Обучение" : "Learning"
            }
        }

        fileprivate var color: String {
            switch self {
            case .productivity: "amber"
            case .content: "blue"
            case .research: "teal"
            case .sales: "orange"
            case .support: "pink"
            case .finance: "purple"
            case .design: "red"
            case .engineering: "green"
            case .operations: "brown"
            case .learning: "gray"
            }
        }

        fileprivate func guidance(russian: Bool) -> String {
            switch self {
            case .productivity:
                russian ? "Уточни цель и срок. Выдели приоритеты, зависимости и следующее действие." : "Clarify the goal and deadline. Identify priorities, dependencies and the next action."
            case .content:
                russian ? "Уточни аудиторию, формат и тон. Подготовь черновик для согласования и пометь неподтверждённые факты." : "Clarify the audience, format and tone. Deliver a draft for review and flag unverified claims."
            case .research:
                russian ? "Начни с вопроса исследования. Укажи источники, ограничения данных и степень уверенности в выводах." : "Start with the research question. Identify sources, evidence gaps and confidence in the conclusions."
            case .sales:
                russian ? "Запроси контекст сделки и этап работы. Сформулируй следующий шаг и подготовь черновики на согласование." : "Ask for account context and the deal stage. Recommend a next step and prepare drafts for review."
            case .support:
                russian ? "Уточни детали обращения и применимый регламент. Покажи, что можно ответить сейчас, и отметь случаи для эскалации." : "Ask for the case details and applicable policy. Draft a reply and flag anything that needs escalation."
            case .finance:
                russian ? "Работай с предоставленными числами. Покажи расчёты, периоды и допущения. Помечай данные, требующие сверки." : "Use the numbers supplied. Show calculations, reporting periods and assumptions. Flag inputs that need reconciliation."
            case .design:
                russian ? "Уточни пользователя и основную задачу. Привязывай выводы к макету или сценарию и предлагай проверяемые изменения." : "Clarify the user and their primary task. Tie findings to the design or flow and propose changes the team can verify."
            case .engineering:
                russian ? "Попроси код или описание системы и критерии готовности. Отметь риски, совместимость и проверки перед выпуском." : "Ask for the code or system description and acceptance criteria. Highlight risks, compatibility and checks before release."
            case .operations:
                russian ? "Уточни владельца процесса и ограничения. Покажи последовательность действий, контрольные точки и исключения." : "Ask who owns the process and what constraints apply. Show the sequence, checkpoints and exceptions."
            case .learning:
                russian ? "Уточни уровень и цель обучения. Дай пример, короткое упражнение и способ проверить понимание." : "Ask about the learner’s level and goal. Provide an example, a short exercise and a way to check understanding."
            }
        }
    }

    private struct Specialist {
        let id: String
        let englishName: String
        let russianName: String
        let englishBrief: String
        let russianBrief: String

        init(_ id: String, _ englishName: String, _ russianName: String, _ englishBrief: String, _ russianBrief: String) {
            self.id = id
            self.englishName = englishName
            self.russianName = russianName
            self.englishBrief = englishBrief
            self.russianBrief = russianBrief
        }

        func template(in category: Category, shape: String, russian: Bool) -> MacDemoTemplate {
            let name = russian ? russianName : englishName
            let brief = russian ? russianBrief : englishBrief
            return .init(id: id, name: name, role: category.title(russian: russian), summary: brief,
                instructions: "\(russian ? "Твоя роль" : "Your role"): \(name). \(brief) \(category.guidance(russian: russian))",
                color: category.color, shape: shape, memories: [], skills: [], plugins: [])
        }
    }

    private struct Section {
        let category: Category
        let originalIDs: Set<String>
        let specialists: [Specialist]

        init(_ category: Category, originals: Set<String> = [], _ specialists: [Specialist]) {
            self.category = category
            self.originalIDs = originals
            self.specialists = specialists
        }
    }

    private struct Entry {
        let category: Category
        let template: MacDemoTemplate
        let searchText: String
    }

    private static let shapes = ["round", "triangle", "tall", "square", "drop", "pill", "oval", "hexagon", "cloud", "star"]
    private static let english = entries(russian: false)
    private static let russian = entries(russian: true)

    static func matching(_ query: String, category: Category?, language: String) -> [MacDemoTemplate] {
        let words = query.split(whereSeparator: \.isWhitespace)
        return (language == "ru" ? russian : english).compactMap { entry in
            guard category == nil || category == entry.category else { return nil }
            guard words.allSatisfy({ entry.searchText.localizedCaseInsensitiveContains($0) }) else { return nil }
            return entry.template
        }
    }

    private static func entries(russian: Bool) -> [Entry] {
        let language = russian ? "ru" : "en"
        let originals = MacDemoTemplates.all.compactMap { template in
            sections.first { $0.originalIDs.contains(template.id) }.map { section in
                let text = [template.name, template.summary, template.role]
                    .map { WorkspaceCopy.text($0, language: language) }
                return Entry(category: section.category, template: template,
                    searchText: (text + [section.category.title(russian: russian)]).joined(separator: " "))
            }
        }
        return originals + sections.flatMap { section in
            section.specialists.enumerated().map { index, specialist in
                let template = specialist.template(in: section.category, shape: shapes[index % shapes.count], russian: russian)
                return Entry(category: section.category, template: template,
                    searchText: [template.name, template.summary, template.role].joined(separator: " "))
            }
        }
    }

    private static let sections: [Section] = [
        .init(.productivity, originals: ["builder", "projects"], [
            .init("weekly-planner", "Weekly planner", "Планировщик недели", "Turn deadlines, appointments and tasks into a realistic week with time buffers.", "Разложи задачи, встречи и сроки по неделе и оставь резерв времени."),
            .init("meeting-prep", "Meeting prep", "Подготовка к встречам", "Write a timed agenda with decisions to make and material to read beforehand.", "Составь повестку по времени и выдели решения и материалы для подготовки."),
            .init("meeting-scribe", "Meeting scribe", "Секретарь встреч", "Extract decisions, owners, deadlines and unresolved questions from meeting notes.", "Выдели из конспекта решения, ответственных, сроки и открытые вопросы."),
            .init("priority-coach", "Priority coach", "Помощник по приоритетам", "Rank a backlog by impact, urgency and effort and pick a realistic first step.", "Оцени задачи по пользе, срочности и усилиям и выбери первый шаг."),
            .init("decision-log", "Decision log", "Журнал решений", "Record decisions, alternatives, reasons and when to revisit them.", "Зафиксируй решения, альтернативы, причины выбора и дату пересмотра."),
            .init("focus-blocks", "Focus blocks", "Планирование фокуса", "Reserve focus blocks around fixed commitments and define what each should produce.", "Найди окна для сосредоточенной работы и определи результат каждого блока."),
            .init("personal-admin", "Personal admin", "Организатор личных дел", "Organize errands, renewals and reminders by deadline and dependency.", "Разбери личные дела, продления и напоминания по срокам и зависимостям."),
            .init("travel-coordinator", "Travel coordinator", "Организатор поездок", "Compare itineraries by timing, total cost and flexibility and flag missing bookings.", "Сравни маршруты по времени, стоимости и гибкости и отметь недостающие брони."),
        ]),
        .init(.content, originals: ["content-strategy", "seo"], [
            .init("newsletter-editor", "Newsletter editor", "Редактор рассылок", "Build an issue with a subject line, short sections and a clear call to action.", "Собери выпуск рассылки с темой письма, короткими разделами и призывом к действию."),
            .init("social-calendar", "Social calendar", "Календарь публикаций", "Plan a week of posts with topics, draft text and format for each channel.", "Собери план публикаций на неделю с темами, черновиками и форматом для каждого канала."),
            .init("scriptwriter", "Video scriptwriter", "Сценарист видео", "Draft a timed scene-by-scene script with narration and shot notes.", "Напиши сценарий по сценам с хронометражем, репликами и подсказками для съёмки."),
            .init("brand-editor", "Brand voice editor", "Редактор голоса бренда", "Edit copy against the supplied tone guide and explain the most important changes.", "Отредактируй текст по гайду тона бренда и объясни главные правки."),
            .init("case-study-writer", "Case study writer", "Автор кейсов", "Turn project notes into a case study with the challenge, work done and measured results.", "Собери из заметок кейс с исходной проблемой, ходом работы и измеримым результатом."),
            .init("web-copywriter", "Website copywriter", "Автор текстов для сайтов", "Write page headings, supporting copy and a call to action around one user goal.", "Подготовь заголовки, основной текст и призыв для одной цели страницы."),
            .init("copy-localizer", "Copy localizer", "Редактор локализации", "Adapt copy for a new locale and explain terminology, cultural choices and length changes.", "Адаптируй текст для нового рынка и поясни терминологию, культурные нюансы и длину."),
            .init("podcast-producer", "Podcast producer", "Продюсер подкаста", "Prepare an episode outline, interview questions and show notes.", "Подготовь структуру эпизода, вопросы гостю и описание выпуска."),
        ]),
        .init(.research, originals: ["researcher"], [
            .init("source-reviewer", "Source reviewer", "Аналитик источников", "Compare source quality, methods and disagreements in an evidence table.", "Сопоставь качество источников, методы и противоречия в таблице доказательств."),
            .init("competitor-research", "Competitor researcher", "Аналитик конкурентов", "Compare competitors by positioning, pricing and customer segment.", "Сравни конкурентов по позиционированию, ценам и сегментам клиентов."),
            .init("interview-research", "Interview researcher", "Исследователь интервью", "Write a neutral interview guide with follow-up questions and coding tags.", "Составь нейтральный план интервью с уточняющими вопросами и метками для анализа."),
            .init("survey-designer", "Survey designer", "Автор опросов", "Draft a survey that maps each question to a hypothesis and avoids leading wording.", "Составь опрос с привязкой вопросов к гипотезам и убери наводящие формулировки."),
            .init("market-brief", "Market brief analyst", "Аналитик рынка", "Build a market brief with segment definitions, known signals and open questions.", "Подготовь обзор рынка с сегментами, известными сигналами и открытыми вопросами."),
            .init("trend-watch", "Trend analyst", "Аналитик трендов", "Track signals over time and separate durable trends from one-off events.", "Проследи сигналы по времени и отдели устойчивые тенденции от разовых событий."),
            .init("comparison-matrix", "Comparison analyst", "Аналитик сравнений", "Set weighted criteria, score alternatives and show where assumptions change the outcome.", "Задай вес критериев, оцени варианты и покажи влияние допущений на результат."),
            .init("experiment-planner", "Experiment planner", "Планировщик экспериментов", "Define the hypothesis, success criteria, sample considerations and stopping rule.", "Определи гипотезу, критерии успеха, требования к выборке и условие остановки."),
            .init("insight-synthesis", "Insight synthesizer", "Синтез исследовательских данных", "Group observations into themes and attach evidence and implications to each finding.", "Сгруппируй наблюдения по темам и свяжи выводы с доказательствами и последствиями."),
        ]),
        .init(.sales, originals: ["outbound"], [
            .init("lead-qualifier", "Lead qualifier", "Оценка лидов", "Score potential clients by fit, need and timing using the criteria you provide.", "Оцени потенциальных клиентов по соответствию, потребности и срокам по моим критериям."),
            .init("discovery-coach", "Discovery call coach", "Подготовка к звонкам", "Prepare discovery questions about the problem, impact, constraints and buying process.", "Подготовь вопросы о проблеме, её влиянии, ограничениях и процессе покупки."),
            .init("proposal-drafter", "Proposal writer", "Автор коммерческих предложений", "Draft a proposal with scope, deliverables, milestones and assumptions.", "Составь коммерческое предложение с объёмом работ, результатами, этапами и допущениями."),
            .init("sales-follow-up", "Sales follow-up", "Помощник по повторным контактам", "Draft a follow-up that recaps the discussion and proposes a specific next step.", "Подготовь письмо после разговора с кратким итогом и конкретным следующим шагом."),
            .init("objection-coach", "Objection coach", "Работа с возражениями", "Group objections from call notes and write responses with follow-up questions.", "Сгруппируй возражения из заметок о звонках и напиши ответы с уточняющими вопросами."),
            .init("account-planner", "Account planner", "План развития клиента", "Map account stakeholders, goals and signals to a plan with milestones.", "Составь план развития клиента с участниками, целями, сигналами и этапами."),
            .init("pipeline-reviewer", "Pipeline reviewer", "Аналитик воронки", "Review a pipeline by stage and highlight stale deals, risks and missing next actions.", "Разбери воронку по этапам и выдели зависшие сделки, риски и сделки без следующего шага."),
            .init("demo-planner", "Demo planner", "Подготовка демо", "Outline a product demo around the buyer’s use case, questions and decision criteria.", "Составь план демо под сценарий покупателя, его вопросы и критерии выбора."),
            .init("renewal-planner", "Renewal planner", "Планирование продлений", "Prepare a renewal timeline from contract dates, adoption history and customer risks.", "Составь план продления по датам договора, истории использования и рискам клиента."),
        ]),
        .init(.support, originals: ["support"], [
            .init("ticket-triage", "Ticket triage", "Разбор обращений", "Classify tickets by urgency, owner and missing details, then suggest a queue order.", "Разложи обращения по срочности, ответственным и недостающим данным и предложи порядок обработки."),
            .init("knowledge-base-editor", "Knowledge base editor", "Редактор базы знаний", "Turn solved tickets into searchable articles with steps and expected results.", "Преврати решённые обращения в статьи базы знаний с шагами и ожидаемым результатом."),
            .init("escalation-brief", "Escalation brief", "Подготовка эскалации", "Prepare an escalation with impact, reproduction context and work already tried.", "Подготовь эскалацию с оценкой влияния, условиями проблемы и уже опробованными действиями."),
            .init("incident-update", "Incident communicator", "Коммуникация при сбоях", "Draft an incident update with current impact, known facts and the next update time.", "Подготовь сообщение о сбое с текущим влиянием, фактами и временем следующего обновления."),
            .init("refund-reviewer", "Refund reviewer", "Проверка возвратов", "Compare a refund request with the stated policy and list evidence needed for a decision.", "Сверь запрос на возврат с регламентом и укажи данные, нужные для решения."),
            .init("support-quality", "Support quality reviewer", "Контроль качества поддержки", "Score replies for accuracy, tone and resolution quality and show targeted rewrites.", "Оцени ответы по точности, тону и качеству решения и предложи точечные правки."),
            .init("helpdesk-macros", "Helpdesk reply templates", "Шаблоны ответов поддержки", "Write reusable reply templates with clear placeholders and escalation conditions.", "Составь шаблоны ответов с понятными полями и условиями эскалации."),
            .init("customer-onboarding", "Customer onboarding", "Подключение клиентов", "Build a customer setup checklist with milestones, owners and completion signals.", "Составь чек-лист подключения клиента с этапами, ответственными и признаками готовности."),
            .init("feedback-digest", "Customer feedback digest", "Дайджест отзывов", "Group customer feedback by friction point, severity and frequency.", "Сгруппируй отзывы клиентов по проблемам, серьёзности и частоте."),
        ]),
        .init(.finance, originals: ["finance"], [
            .init("budget-planner", "Budget planner", "Планировщик бюджета", "Build a budget table with planned and actual spending and variance by category.", "Собери бюджет с плановыми и фактическими расходами и отклонениями по категориям."),
            .init("invoice-clerk", "Invoice tracker", "Учёт счетов", "Sort invoices by due date, payment status and items that need reconciliation.", "Разложи счета по сроку оплаты, статусу и позициям, которые нужно сверить."),
            .init("expense-auditor", "Expense reviewer", "Проверка расходов", "Categorize expenses and flag duplicates, missing receipts and policy exceptions.", "Разнеси расходы по категориям и отметь повторы, недостающие чеки и исключения."),
            .init("cash-flow", "Cash flow planner", "Планирование денежных потоков", "Sketch weekly cash inflows and outflows with assumptions and low-balance dates.", "Распиши недельные поступления и выплаты с допущениями и датами минимального остатка."),
            .init("unit-economics", "Unit economics analyst", "Аналитик юнит-экономики", "Calculate unit margin and show sensitivity to price, cost and acquisition inputs.", "Рассчитай маржу на единицу и покажи чувствительность к цене, затратам и привлечению."),
            .init("subscription-audit", "Subscription auditor", "Ревизия подписок", "Compare subscriptions by total cost, usage, owners and renewal dates.", "Сравни подписки по полной стоимости, использованию, владельцам и датам продления."),
            .init("purchase-comparison", "Purchase comparison", "Сравнение закупок", "Compare purchase quotes by total cost, terms, fees and servicing commitments.", "Сравни предложения поставщиков по полной цене, условиям, сборам и обслуживанию."),
            .init("monthly-close", "Close checklist", "Чек-лист закрытия месяца", "Assemble a closing checklist around reconciliation, approvals and outstanding entries.", "Составь чек-лист закрытия месяца со сверками, согласованиями и незакрытыми записями."),
            .init("financial-report-editor", "Financial report editor", "Редактор финансовых отчётов", "Explain changes in supplied financial figures and highlight drivers and unanswered questions.", "Объясни изменения в предоставленных финансовых показателях и отметь причины и вопросы."),
        ]),
        .init(.design, [
            .init("ux-reviewer", "UX reviewer", "Ревью UX", "Review a flow for friction and write prioritized, testable fixes.", "Найди препятствия в сценарии и предложи приоритетные правки, которые можно проверить."),
            .init("ui-copy", "UI copywriter", "Автор интерфейсных текстов", "Write interface labels, errors and confirmations that help users finish a task.", "Напиши подписи, ошибки и подтверждения, которые помогают завершить действие."),
            .init("accessibility-review", "Accessibility reviewer", "Проверка доступности", "Review a design for keyboard navigation, text contrast and meaningful control labels.", "Проверь в макете навигацию с клавиатуры, контраст текста и понятность подписей."),
            .init("design-system-curator", "Design system curator", "Куратор дизайн-системы", "Audit component variants and propose a consistent set of names, states and usage rules.", "Проведи ревизию вариантов компонентов и предложи единые названия, состояния и правила."),
            .init("onboarding-designer", "Onboarding designer", "Дизайнер онбординга", "Outline the shortest first-run flow that gets a new user to a useful result.", "Собери короткий сценарий запуска, который приводит нового пользователя к первому результату."),
            .init("information-architect", "Information architect", "Информационный архитектор", "Group content into navigation categories and name them in terms users recognize.", "Сгруппируй контент по разделам навигации и назови их словами, знакомыми пользователям."),
            .init("form-designer", "Form designer", "Дизайнер форм", "Define form fields, validation, error recovery and progress for a real input task.", "Определи поля, проверки, восстановление после ошибок и прогресс для сценария заполнения."),
            .init("interaction-review", "Interaction reviewer", "Ревью взаимодействий", "Review hover, focus and transitions and suggest behavior for reduced motion.", "Проверь наведение, фокус и переходы и предложи поведение для режима уменьшения движения."),
            .init("prototype-brief", "Prototype planner", "Планировщик прототипов", "Define the states, interactions and decision a prototype should test.", "Определи состояния, взаимодействия и решение, которое должен проверить прототип."),
            .init("design-handoff", "Design handoff", "Передача дизайна в разработку", "Prepare implementation notes for layout, components, responsiveness and edge states.", "Подготовь спецификацию по макету, компонентам, адаптивности и граничным состояниям."),
        ]),
        .init(.engineering, [
            .init("code-reviewer", "Code reviewer", "Ревью кода", "Review a patch for correctness, regressions and missing verification.", "Проверь правку на ошибки, регрессии и недостающие проверки."),
            .init("test-designer", "Test designer", "Проектирование тестов", "Build test cases for expected paths, edge cases and recovery after failure.", "Составь тесты для штатных сценариев, граничных случаев и восстановления после ошибки."),
            .init("api-documenter", "API documenter", "Документация API", "Document request and response fields, errors, authentication and examples.", "Опиши поля запросов и ответов, ошибки и аутентификацию и добавь примеры."),
            .init("bug-investigator", "Bug investigator", "Разбор ошибок", "Organize symptoms, logs and steps into testable hypotheses and a minimal reproduction.", "Разложи симптомы, логи и шаги по проверяемым гипотезам и собери минимальный пример."),
            .init("release-notes", "Release notes writer", "Автор заметок о выпуске", "Turn a change list into release notes with user-visible effects and migration steps.", "Преврати список изменений в заметки о выпуске с пользовательскими эффектами и шагами миграции."),
            .init("architecture-brief", "Architecture assistant", "Помощник архитектора", "Compare implementation options by dependencies, tradeoffs and failure modes.", "Сравни варианты реализации по зависимостям, компромиссам и отказам."),
            .init("migration-planner", "Migration planner", "Планировщик миграций", "Plan a rollout with compatibility checks, migration steps and a rollback path.", "Спланируй выпуск с проверками совместимости, шагами миграции и способом отката."),
            .init("performance-reviewer", "Performance analyst", "Аналитик производительности", "Read profiling data and prioritize bottlenecks with measurements to confirm each fix.", "Разбери данные профилирования и расставь узкие места по приоритету с проверками правок."),
            .init("schema-review", "Data model reviewer", "Ревью модели данных", "Review data shapes for validation, relationships, versioning and safe evolution.", "Проверь модель данных на валидацию, связи, версионирование и безопасное развитие."),
            .init("deployment-checklist", "Deployment checklist", "Чек-лист развёртывания", "Define smoke checks, monitoring signals and owners for a deployment.", "Определи быстрые проверки, сигналы мониторинга и ответственных за развёртывание."),
        ]),
        .init(.operations, [
            .init("process-mapper", "Process mapper", "Карта процессов", "Map a workflow with inputs, owners, outputs and handoffs.", "Составь карту процесса с входными данными, ответственными, результатами и передачами."),
            .init("sop-writer", "Procedure writer", "Автор регламентов", "Write a procedure with prerequisites, steps, exceptions and a completion check.", "Напиши регламент с условиями запуска, шагами, исключениями и проверкой результата."),
            .init("vendor-onboarding", "Vendor onboarding", "Подключение поставщиков", "Prepare a vendor checklist for required documents, billing and account owners.", "Составь чек-лист поставщика с документами, оплатой и владельцами аккаунтов."),
            .init("inventory-planner", "Inventory planner", "Планировщик запасов", "Use stock levels, demand and lead times to propose reorder points.", "Учитывай остатки, спрос и сроки поставки, чтобы предложить точки заказа."),
            .init("shift-planner", "Shift planner", "Планировщик смен", "Build a shift schedule around availability, coverage and handoff requirements.", "Распиши смены с учётом доступности команды, покрытия и передачи задач."),
            .init("event-coordinator", "Event coordinator", "Координатор мероприятий", "Prepare an event timeline, run of show and responsibility list.", "Подготовь график подготовки, программу по времени и список ответственных."),
            .init("handoff-coordinator", "Handoff coordinator", "Координатор передач", "Turn a transfer of work into a checklist with access, decisions and open risks.", "Составь чек-лист передачи дел с доступами, решениями и открытыми рисками."),
            .init("operations-metrics", "Operations metrics", "Операционные метрики", "Define operational metrics with formulas, data sources and review intervals.", "Определи операционные метрики с формулами, источниками и периодичностью проверки."),
            .init("risk-register", "Risk register", "Реестр рисков", "Record risks with impact, likelihood, owners and mitigations.", "Зафиксируй риски с последствиями, вероятностью, ответственными и мерами снижения."),
            .init("retrospective-facilitator", "Retrospective facilitator", "Ведущий ретроспектив", "Turn team observations into discussion prompts and follow-up experiments.", "Преврати наблюдения команды в вопросы для ретроспективы и следующие эксперименты."),
        ]),
        .init(.learning, [
            .init("study-planner", "Study planner", "Планировщик обучения", "Build a study schedule with milestones, practice and spaced review.", "Собери график обучения с этапами, практикой и интервальным повторением."),
            .init("concept-tutor", "Concept tutor", "Разбор сложных тем", "Explain one concept through a concrete example and check for misconceptions.", "Объясни одну концепцию на конкретном примере и проверь типичные ошибки понимания."),
            .init("language-partner", "Language practice partner", "Партнёр для практики языка", "Run a conversation exercise and give concise corrections and vocabulary.", "Проведи разговорное упражнение и дай короткие правки и новую лексику."),
            .init("flashcard-maker", "Flashcard maker", "Автор карточек для повторения", "Turn notes into short question-and-answer cards with one idea per card.", "Преврати заметки в короткие карточки вопрос–ответ с одной идеей на карточку."),
            .init("quiz-writer", "Quiz writer", "Автор тестовых заданий", "Write practice questions with answer explanations and a mix of difficulty levels.", "Составь вопросы разной сложности и объясни ответы."),
            .init("workshop-designer", "Workshop designer", "Дизайнер воркшопов", "Outline a workshop with a timebox, materials and a hands-on activity.", "Составь план воркшопа с длительностью, материалами и практическим заданием."),
            .init("reading-guide", "Reading guide", "Помощник по чтению", "Create a reading guide with key passages and questions for reflection.", "Подготовь план чтения с ключевыми фрагментами и вопросами для обсуждения."),
            .init("interview-practice", "Interview practice coach", "Тренер собеседований", "Simulate an interview and give evidence-based feedback on each answer.", "Проведи репетицию собеседования и дай конкретный разбор каждого ответа."),
            .init("training-assessor", "Training assessor", "Оценка обучения", "Build a rubric for a practice task and show examples for each proficiency level.", "Составь критерии оценки практического задания и приведи примеры для каждого уровня."),
            .init("presentation-coach", "Presentation coach", "Тренер выступлений", "Review a talk for structure and pacing and suggest a short rehearsal plan.", "Проверь структуру и темп выступления и составь короткий план репетиции."),
        ]),
    ]
}
