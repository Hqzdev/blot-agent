import BlotDesign
import BlotDomain
import Foundation

struct MacChatTaskExample {
    let title: String
    let prompt: String
    let glyph: BlotGlyph

    static func suggestions(for agent: BlotV3.AgentProfile?, skills: [String], group: Bool, russian: Bool) -> [Self] {
        func task(_ glyph: BlotGlyph, _ ru: String, _ en: String, _ ruPrompt: String, _ enPrompt: String) -> Self {
            .init(title: russian ? ru : en, prompt: russian ? ruPrompt : enPrompt, glyph: glyph)
        }
        if group {
            return [
                task(.people, "Разделить работу", "Divide the work", "Помогите разделить задачу между участниками. Сначала уточните цель и срок.", "Help divide the work among the team. First ask about the goal and deadline."),
                task(.list, "Собрать решения", "Compare proposals", "Предложите решения с позиции каждого участника и соберите их в одну рекомендацию.", "Suggest a solution from each team member’s perspective and combine them into one recommendation."),
                task(.flag, "Согласовать план", "Agree on a plan", "Помогите согласовать порядок работы, точки проверки и итоговый результат. Сначала уточните сроки и зависимости.", "Agree on the work sequence, checkpoints and deliverable. First ask about deadlines and dependencies."),
                task(.checkCircle, "Проверить результат", "Review the result", "Проверьте результат с позиции каждого участника и соберите правки по приоритету. Попросите материалы и критерии готовности.", "Review the work from each team member’s perspective and prioritize the fixes. Ask for the materials and acceptance criteria.")
            ]
        }
        let assigned = skills.map { name in
            Self(title: name, prompt: russian ? "@\(name) Помоги применить этот скилл к моей задаче. Что тебе нужно для начала?" : "@\(name) Help me use this skill for my task. What do you need to get started?", glyph: .skill)
        }
        let catalog = agent.flatMap { agent in
            catalogProfiles.first { $0.identifiers.contains(agent.name) || $0.identifiers.contains(agent.instructions) }
        }
        let catalogTasks = (catalog?.template.skills ?? []).map { skill in
            let title = WorkspaceCopy.text(skill, language: russian ? "ru" : "en")
            return Self(title: title, prompt: russian ? "Помоги с задачей «\(title)». Уточни, какие материалы нужны для начала." : "Help me with this task: \(title). Ask what information you need to get started.", glyph: .skill)
        }
        func specialtyTasks(for specialty: Specialty?) -> [Self] {
            switch specialty {
            case .editor:
                [task(.email, "Сократить письмо", "Shorten an email", "Помоги сократить письмо вдвое, сохранив мой тон. Я пришлю текст.", "Help cut my email in half while keeping my tone. I’ll paste the text."),
                 task(.compose, "Предложить заголовки", "Suggest headlines", "Предложи три заголовка для моего текста. Сначала спроси, для кого я пишу.", "Suggest three headlines for my piece. Start by asking who the audience is."),
                 task(.note, "Отредактировать черновик", "Edit a draft", "Улучши ясность и связность текста, сохранив смысл. Попроси черновик и уточни желаемый тон.", "Edit my draft for clarity and flow while preserving its meaning. Ask for the draft and desired tone."),
                 task(.list, "Составить план текста", "Outline a piece", "Предложи структуру текста с ключевыми тезисами. Спроси тему, аудиторию и цель.", "Outline a piece with its main points. Ask about the topic, audience and purpose.")]
            case .kitchen:
                [task(.calendar, "Ужины на три дня", "Plan three dinners", "Составь меню ужинов на три дня. Сначала уточни мои предпочтения и сколько времени есть на готовку.", "Plan three dinners. First ask about my preferences and how much time I have to cook."),
                 task(.list, "Список покупок", "Build a grocery list", "Собери список покупок по моему рецепту. Спроси рецепт и количество порций.", "Turn my recipe into a grocery list. Ask for the recipe and number of servings."),
                 task(.refresh, "Использовать остатки", "Use up leftovers", "Предложи два блюда из продуктов, которые уже есть дома. Спроси, что осталось и в каком количестве.", "Suggest two meals using what I already have. Ask what’s left and how much."),
                 task(.clock, "Найти быстрый рецепт", "Find a quick dinner", "Подбери рецепт ужина, который я успею приготовить. Уточни время, продукты и ограничения в питании.", "Find a dinner recipe I can make in time. Ask about the time available, ingredients and dietary needs.")]
            case .inbox:
                [task(.tray, "Разобрать входящие", "Triage my inbox", "Помоги разобрать письма по срочности. Я пришлю темы и короткие выдержки.", "Help sort my emails by urgency. I’ll share the subjects and short excerpts."),
                 task(.reply, "Набросать ответ", "Draft a reply", "Подготовь короткий ответ в моём тоне. Попроси исходное письмо и уточни, о чём мы хотим договориться.", "Draft a short reply in my voice. Ask for the original email and the outcome I want."),
                 task(.list, "Собрать дайджест писем", "Summarize emails", "Собери из писем дайджест с решениями, сроками и открытыми вопросами. Попроси письма или выдержки из них.", "Summarize my emails into decisions, deadlines and open questions. Ask for the emails or excerpts."),
                 task(.clock, "Написать напоминание", "Draft a follow-up", "Напиши короткое напоминание по переписке без ответа. Попроси переписку и уточни, к какому сроку нужен ответ.", "Draft a short follow-up for an unanswered thread. Ask for the thread and when I need a reply.")]
            case .design:
                [task(.computer, "Разобрать экран", "Review a screen", "Разбери мой экран и предложи три правки, которые упростят главное действие. Попроси скриншот.", "Review my screen and suggest three changes that make its main action easier. Ask for a screenshot."),
                 task(.layout, "Сравнить макеты", "Compare layouts", "Помоги выбрать между двумя макетами. Сначала уточни задачу пользователя.", "Help choose between two layouts. First ask what the user is trying to do."),
                 task(.checkCircle, "Проверить пустой экран", "Review an empty state", "Проверь, понятно ли, что делать на пустом экране. Попроси скриншот и уточни, какое действие пользователь должен сделать первым.", "Review whether the next step is clear in an empty state. Ask for a screenshot and what the user should do first."),
                 task(.people, "Подготовить тест интерфейса", "Plan a usability test", "Составь задания для тестирования сценария и отметь, за чем наблюдать. Спроси, кто будет участвовать и какой сценарий проверяем.", "Write usability tasks and what to observe for a flow. Ask who will participate and which flow we’re testing.")]
            case .research:
                [task(.spreadsheet, "Сравнить варианты", "Compare options", "Сравни варианты в таблице и отметь, какие данные стоит проверить. Спроси, между чем я выбираю.", "Compare my options in a table and flag what needs verification. Ask which options I’m considering."),
                 task(.chat, "Вопросы для интервью", "Draft interview questions", "Составь пять вопросов для интервью. Уточни, кого мы хотим опросить и что узнать.", "Write five interview questions. Ask whom we’re interviewing and what we want to learn."),
                 task(.book, "Свести наблюдения", "Summarize findings", "Сгруппируй наблюдения по темам и укажи, на каких данных основан каждый вывод. Попроси заметки.", "Group observations by theme and cite the evidence for each finding. Ask for my notes."),
                 task(.flag, "Проверить гипотезу", "Test a hypothesis", "Предложи способ проверки гипотезы и критерии для принятия решения. Спроси, какие данные уже есть.", "Propose a way to test a hypothesis and criteria for a decision. Ask what data I already have.")]
            case .engineering:
                [task(.warning, "Разобрать ошибку", "Diagnose an error", "Помоги разобраться в ошибке. Попроси сообщение об ошибке и минимальный пример кода.", "Help diagnose an error. Ask for the error message and a minimal code example."),
                 task(.pullRequest, "Проверить изменение", "Review a change", "Посмотри моё изменение кода и предложи тесты для граничных случаев. Я пришлю diff.", "Review my code change and suggest tests for edge cases. I’ll share the diff."),
                 task(.list, "Разбить задачу на шаги", "Plan a feature", "Разбей реализацию на небольшие шаги и предложи критерии готовности. Спроси про ожидаемое поведение и ограничения.", "Split the feature into implementation steps with acceptance criteria. Ask about the intended behavior and constraints."),
                 task(.document, "Описать модуль", "Document a module", "Подготовь описание модуля с примером использования и обработкой ошибок. Попроси код и уточни, кто будет читать документацию.", "Document a module with a usage example and error behavior. Ask for the code and who will read it.")]
            case .planning:
                [task(.flag, "Приоритеты на сегодня", "Prioritize today", "Помоги выбрать три приоритета на сегодня с учётом встреч и сроков. Спроси, что уже запланировано.", "Help choose my top three priorities around meetings and deadlines. Ask what’s on my schedule."),
                 task(.calendar, "Подготовиться к встрече", "Plan a meeting", "Составь короткую повестку встречи. Уточни участников и какое решение нам нужно принять.", "Draft a short meeting agenda. Ask who’s attending and what decision we need to make."),
                 task(.checkCircle, "Проверить готовность", "Check readiness", "Составь чек-лист для проверки готовности к сроку. Уточни дату и что должно быть готово к этому моменту.", "Write a readiness checklist for a deadline. Ask for the date and what needs to be ready by then."),
                 task(.warning, "Найти риски проекта", "Identify project risks", "Отметь риски по срокам и зависимостям и предложи меры для каждого. Попроси текущий план.", "Flag risks in the timeline and dependencies, and suggest a mitigation for each. Ask for the current plan.")]
            case nil:
                [task(.sparkle, "Подобрать первую задачу", "Find a first task", "Предложи три конкретные задачи из своей области и покажи, какой результат я получу в каждой.", "Suggest three specific tasks in your specialty and show the result I’d get from each."),
                 task(.list, "Составить чек-лист", "Make a checklist", "Помоги составить чек-лист для задачи из твоей области. Сначала уточни мою цель.", "Help build a checklist for a task in your specialty. Start by asking about my goal."),
                 task(.chat, "Уточнить задачу", "Clarify a task", "Помоги сформулировать задачу. Уточни цель, какие материалы у меня есть и как я пойму, что результат готов.", "Help me define a task. Ask about my goal, what materials I have and how I’ll know it’s done."),
                 task(.compose, "Сделать первый черновик", "Make a first draft", "Подготовь черновик для моей задачи. Сначала спроси, какой результат нужен и что использовать как исходный материал.", "Make a first draft for my task. First ask what I want to produce and what materials you can work from.")]
            }
        }
        var seen = Set<String>()
        let examples = assigned + catalogTasks + specialtyTasks(for: agent.flatMap(Specialty.init))
        return Array(examples.filter { seen.insert($0.title.lowercased()).inserted }.prefix(4))
    }

    private static let catalogProfiles = MacDemoTemplates.all.map { template in
        let fields = [template.name, template.instructions]
        return (template: template, identifiers: Set(fields + fields.map { WorkspaceCopy.text($0, language: "en") }))
    }

    private enum Specialty: CaseIterable {
        case editor, kitchen, inbox, design, research, engineering, planning

        var keywords: [String] {
            switch self {
            case .editor: ["editor", "writer", "content", "редактор", "редактир", "контент", "копирайт"]
            case .kitchen: ["chef", "meal", "recipe", "dinner", "grocery", "повар", "шеф", "рецепт", "ужин"]
            case .inbox: ["inbox", "e-mail", "email", "почт", "входящ"]
            case .design: ["design", "дизайн", "интерфейс"]
            case .research: ["research", "исслед", "аналитик"]
            case .engineering: ["developer", "engineer", "programmer", "программи", "разработ", "инженер"]
            case .planning: ["ceo", "project", "night shift", "morning digest", "проект", "утренн", "руководит"]
            }
        }

        init?(_ agent: BlotV3.AgentProfile) {
            for field in [agent.roleId, agent.name, agent.instructions] {
                if let match = Self.allCases.first(where: { role in role.keywords.contains(where: field.localizedCaseInsensitiveContains) }) {
                    self = match
                    return
                }
            }
            return nil
        }
    }
}
