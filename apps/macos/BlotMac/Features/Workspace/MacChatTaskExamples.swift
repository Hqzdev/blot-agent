import BlotDomain
import Foundation

struct MacChatTaskExample {
    let title: String
    let prompt: String

    static func suggestions(for agent: BlotV3.AgentProfile?, skills: [String], group: Bool, russian: Bool) -> [Self] {
        func task(_ ru: String, _ en: String, _ ruPrompt: String, _ enPrompt: String) -> Self {
            .init(title: russian ? ru : en, prompt: russian ? ruPrompt : enPrompt)
        }
        if group {
            return [
                task("Разделить работу", "Divide the work", "Помогите разделить задачу между участниками. Сначала уточните цель и срок.", "Help divide the work among the team. First ask about the goal and deadline."),
                task("Собрать решения", "Compare proposals", "Предложите решения с позиции каждого участника и соберите их в одну рекомендацию.", "Suggest a solution from each team member’s perspective and combine them into one recommendation.")
            ]
        }
        let assigned = skills.map { name in
            Self(title: name, prompt: russian ? "@\(name) Помоги применить этот скилл к моей задаче. Что тебе нужно для начала?" : "@\(name) Help me use this skill for my task. What do you need to get started?")
        }
        let catalog = agent.flatMap { agent in
            catalogProfiles.first { $0.identifiers.contains(agent.name) || $0.identifiers.contains(agent.instructions) }
        }
        let catalogTasks = (catalog?.template.skills ?? []).map { skill in
            let title = WorkspaceCopy.text(skill, language: russian ? "ru" : "en")
            return Self(title: title, prompt: russian ? "Помоги с задачей «\(title)». Уточни, какие материалы нужны для начала." : "Help me with this task: \(title). Ask what information you need to get started.")
        }
        func pair(for specialty: Specialty?) -> [Self] {
            switch specialty {
            case .editor:
                [task("Сократить письмо", "Shorten an email", "Помоги сократить письмо вдвое, сохранив мой тон. Я пришлю текст.", "Help cut my email in half while keeping my tone. I’ll paste the text."),
                 task("Предложить заголовки", "Suggest headlines", "Предложи три заголовка для моего текста. Сначала спроси, для кого я пишу.", "Suggest three headlines for my piece. Start by asking who the audience is.")]
            case .kitchen:
                [task("Ужины на три дня", "Plan three dinners", "Составь меню ужинов на три дня. Сначала уточни мои предпочтения и сколько времени есть на готовку.", "Plan three dinners. First ask about my preferences and how much time I have to cook."),
                 task("Список покупок", "Build a grocery list", "Собери список покупок по моему рецепту. Спроси рецепт и количество порций.", "Turn my recipe into a grocery list. Ask for the recipe and number of servings.")]
            case .inbox:
                [task("Разобрать входящие", "Triage my inbox", "Помоги разобрать письма по срочности. Я пришлю темы и короткие выдержки.", "Help sort my emails by urgency. I’ll share the subjects and short excerpts."),
                 task("Набросать ответ", "Draft a reply", "Подготовь короткий ответ в моём тоне. Попроси исходное письмо и уточни, о чём мы хотим договориться.", "Draft a short reply in my voice. Ask for the original email and the outcome I want.")]
            case .design:
                [task("Разобрать экран", "Review a screen", "Разбери мой экран и предложи три правки, которые упростят главное действие. Попроси скриншот.", "Review my screen and suggest three changes that make its main action easier. Ask for a screenshot."),
                 task("Сравнить макеты", "Compare layouts", "Помоги выбрать между двумя макетами. Сначала уточни задачу пользователя.", "Help choose between two layouts. First ask what the user is trying to do.")]
            case .research:
                [task("Сравнить варианты", "Compare options", "Сравни варианты в таблице и отметь, какие данные стоит проверить. Спроси, между чем я выбираю.", "Compare my options in a table and flag what needs verification. Ask which options I’m considering."),
                 task("Вопросы для интервью", "Draft interview questions", "Составь пять вопросов для интервью. Уточни, кого мы хотим опросить и что узнать.", "Write five interview questions. Ask whom we’re interviewing and what we want to learn.")]
            case .engineering:
                [task("Разобрать ошибку", "Diagnose an error", "Помоги разобраться в ошибке. Попроси сообщение об ошибке и минимальный пример кода.", "Help diagnose an error. Ask for the error message and a minimal code example."),
                 task("Проверить изменение", "Review a change", "Посмотри моё изменение кода и предложи тесты для граничных случаев. Я пришлю diff.", "Review my code change and suggest tests for edge cases. I’ll share the diff.")]
            case .planning:
                [task("Приоритеты на сегодня", "Prioritize today", "Помоги выбрать три приоритета на сегодня с учётом встреч и сроков. Спроси, что уже запланировано.", "Help choose my top three priorities around meetings and deadlines. Ask what’s on my schedule."),
                 task("Подготовиться к встрече", "Plan a meeting", "Составь короткую повестку встречи. Уточни участников и какое решение нам нужно принять.", "Draft a short meeting agenda. Ask who’s attending and what decision we need to make.")]
            case nil:
                [task("Подобрать первую задачу", "Find a first task", "Предложи три конкретные задачи из своей области и покажи, какой результат я получу в каждой.", "Suggest three specific tasks in your specialty and show the result I’d get from each."),
                 task("Составить чек-лист", "Make a checklist", "Помоги составить чек-лист для задачи из твоей области. Сначала уточни мою цель.", "Help build a checklist for a task in your specialty. Start by asking about my goal.")]
            }
        }
        var seen = Set<String>()
        let examples = assigned + catalogTasks + pair(for: agent.flatMap(Specialty.init))
        return Array(examples.filter { seen.insert($0.title.lowercased()).inserted }.prefix(2))
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
