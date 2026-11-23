import BlotDesign
import SwiftUI

enum MacChatTaskTopic: CaseIterable {
    case agent, documents, tables, presentations, websites, planning, meetings, research, development

    private var label: (ru: String, en: String, glyph: BlotGlyph) {
        switch self {
        case .agent: ("Для этого чата", "For this chat", .sparkle)
        case .documents: ("Документы", "Documents", .document)
        case .tables: ("Таблицы", "Tables", .spreadsheet)
        case .presentations: ("Презентации", "Slides", .presentation)
        case .websites: ("Сайты", "Websites", .globe)
        case .planning: ("Планирование", "Planning", .list)
        case .meetings: ("Встречи", "Meetings", .people)
        case .research: ("Исследования", "Research", .search)
        case .development: ("Разработка", "Development", .code)
        }
    }

    var glyph: BlotGlyph { label.glyph }

    var colors: (ink: Color, tint: Color) {
        let (ink, tint): (BlotColorPair, UInt32) = switch self {
        case .agent: (.init(light: 0x0B6094FF, dark: 0x78CEFFFF), 0x1099EFFF)
        case .documents: (.init(light: 0x1B4CAFFF, dark: 0xA3BCFFFF), 0x3867FFFF)
        case .tables: (.init(light: 0x066634FF, dark: 0x66E7A0FF), 0x08C557FF)
        case .presentations: (.init(light: 0x7035B9FF, dark: 0xD3A7FFFF), 0xA059FFFF)
        case .websites: (.init(light: 0x006359FF, dark: 0x78EFE1FF), 0x0EC8B6FF)
        case .planning: (.init(light: 0x934C05FF, dark: 0xFFB962FF), 0xF49521FF)
        case .meetings: (.init(light: 0x9B2B64FF, dark: 0xFFABE0FF), 0xEF4595FF)
        case .research: (.init(light: 0x6B5200FF, dark: 0xFDE17DFF), 0xEAC11AFF)
        case .development: (.init(light: 0xA1312FFF, dark: 0xFFAA9FFF), 0xF35D56FF)
        }
        return (BlotColor.dynamic(ink), BlotColor.dynamic(.init(tint)))
    }

    func title(russian: Bool) -> String { russian ? label.ru : label.en }

    func examples(russian: Bool, personal: [MacChatTaskExample]) -> [MacChatTaskExample] {
        func task(_ glyph: BlotGlyph, _ ru: String, _ en: String, _ ruPrompt: String, _ enPrompt: String) -> MacChatTaskExample {
            .init(title: russian ? ru : en, prompt: russian ? ruPrompt : enPrompt, glyph: glyph)
        }
        switch self {
        case .agent: return personal
        case .documents: return [
            task(.document, "Написать бриф", "Write a brief", "Помоги написать бриф на одну страницу. Спроси, для кого он и какое решение нужно принять.", "Help me write a one-page brief. Ask who will read it and what decision they need to make."),
            task(.list, "Собрать инструкцию", "Write a how-to", "Преврати мои заметки в пошаговую инструкцию с проверкой результата. Попроси заметки.", "Turn my notes into step-by-step instructions with a final check. Ask me for the notes."),
            task(.note, "Подготовить отчёт", "Draft a report", "Собери из моих материалов отчёт с выводами и следующими шагами. Уточни период и аудиторию.", "Turn my materials into a report with findings and next steps. Ask about the time period and audience."),
            task(.compose, "Составить предложение", "Draft a proposal", "Оформи предложение с целью, объёмом работ и ожидаемым результатом. Спроси, для кого оно и какие есть ограничения.", "Draft a proposal covering the goal, scope and expected outcome. Ask who it is for and what constraints apply.")]
        case .tables: return [
            task(.spreadsheet, "Сравнить предложения", "Compare quotes", "Подготовь таблицу для сравнения предложений подрядчиков по цене, срокам и условиям. Спроси, какие предложения у меня есть.", "Build a table comparing vendor quotes by price, turnaround and terms. Ask me for the quotes."),
            task(.calendar, "Распределить смены", "Schedule shifts", "Составь недельную таблицу смен. Уточни часы работы, состав команды и ограничения по дням.", "Build a weekly shift table. Ask about opening hours, the team and availability."),
            task(.currency, "Составить бюджет", "Build a budget", "Подготовь таблицу плановых и фактических расходов с итогом по категориям. Спроси период и статьи расходов.", "Build a budget table with planned and actual spending and totals by category. Ask for the time period and expense categories."),
            task(.checkCircle, "Отслеживать задачи", "Track assignments", "Собери таблицу задач со статусами, ответственными и сроками. Спроси, какие задачи и статусы нужны.", "Make a tracker with tasks, owners, due dates and statuses. Ask which tasks and statuses to include.")]
        case .presentations: return [
            task(.presentation, "Подготовить демо", "Outline a demo", "Собери план пяти слайдов для демонстрации продукта. Спроси, кому показываем продукт и какое действие ждём после демо.", "Outline five slides for a product demo. Ask about the audience and what we want them to do next."),
            task(.usage, "Показать итоги", "Present results", "Предложи структуру короткой презентации об итогах проекта. Уточни цель проекта и какие результаты уже измерены.", "Outline a short presentation on project results. Ask about the original goal and the results we measured."),
            task(.flag, "Защитить идею", "Pitch an idea", "Собери слайды о проблеме, решении и необходимых ресурсах. Уточни, кто принимает решение и что нужно согласовать.", "Outline slides covering the problem, solution and resources. Ask who decides and what needs their approval."),
            task(.book, "Подготовить мини-урок", "Build a mini lesson", "Спланируй обучающие слайды с примером и упражнением. Спроси тему, уровень слушателей и сколько времени есть.", "Plan teaching slides with an example and an exercise. Ask for the topic, audience level and available time.")]
        case .websites: return [
            task(.globe, "Составить карту сайта", "Map out a site", "Предложи карту сайта и главное действие на каждой странице. Сначала спроси, что посетитель должен найти.", "Map out a website and one main action per page. First ask what visitors need to find."),
            task(.layout, "Написать первый экран", "Draft a homepage", "Предложи три варианта заголовка, подзаголовка и кнопки для главной страницы. Спроси про продукт и аудиторию.", "Draft three headline, subheading and button combinations for a homepage. Ask about the product and audience."),
            task(.search, "Проверить страницу", "Review a page", "Проверь, понятны ли предложение, навигация и следующее действие. Попроси ссылку или скриншот страницы.", "Review the offer, navigation and next step on a page. Ask for its URL or a screenshot."),
            task(.question, "Написать раздел FAQ", "Write an FAQ", "Собери раздел с короткими ответами на вопросы посетителей. Спроси, что чаще всего нужно объяснять о продукте.", "Draft concise answers to common visitor questions. Ask what people usually need explained about the product.")]
        case .planning: return [
            task(.flag, "Разбить проект на этапы", "Plan milestones", "Помоги разбить проект на этапы с проверяемым результатом. Уточни цель, срок и доступные ресурсы.", "Break a project into milestones with a clear outcome for each. Ask about the goal, deadline and available resources."),
            task(.calendar, "Спланировать неделю", "Plan my week", "Собери план недели с резервом времени. Попроси список дел, встреч и жёстких сроков.", "Plan my week with time to spare. Ask for my tasks, meetings and fixed deadlines."),
            task(.filter, "Расставить приоритеты", "Prioritize a backlog", "Распредели задачи по пользе, срочности и усилиям. Попроси список и уточни главную цель.", "Rank my tasks by impact, urgency and effort. Ask for the list and the main objective."),
            task(.warning, "Подготовить запасной план", "Make a backup plan", "Выдели основные риски и предложи действия на случай задержки. Уточни срок и от чего зависит результат.", "Identify the main risks and what to do if work slips. Ask for the deadline and critical dependencies.")]
        case .meetings: return [
            task(.list, "Собрать повестку", "Build an agenda", "Составь повестку с временем на каждый вопрос. Уточни длительность встречи и решение, которое нужно принять.", "Build a timed agenda. Ask how long the meeting is and what decision we need to reach."),
            task(.checkCircle, "Выделить поручения", "Extract action items", "Выдели из заметок решения, поручения, ответственных и сроки. Попроси заметки и отметь, где деталей не хватает.", "Extract decisions, action items, owners and dates from my meeting notes. Ask for the notes and flag missing details."),
            task(.people, "Подготовиться к обсуждению", "Prepare for a discussion", "Составь краткую справку с вопросами и открытыми решениями. Спроси, кто участвует и что нужно обсудить.", "Make a short briefing with questions and open decisions. Ask who is attending and what needs discussion."),
            task(.email, "Подвести итоги встречи", "Draft a meeting recap", "Напиши письмо с решениями, сроками и открытыми вопросами. Попроси заметки и уточни, кто будет читать письмо.", "Draft a follow-up email with decisions, deadlines and open questions. Ask for the notes and intended recipients.")]
        case .research: return [
            task(.chat, "Подготовить интервью", "Prepare an interview", "Составь вопросы для исследовательского интервью. Уточни гипотезу и кого я собираюсь опросить.", "Draft research interview questions. Ask about my hypothesis and who I plan to interview."),
            task(.book, "Разобрать источники", "Review sources", "Сопоставь выводы моих источников и отметь противоречия. Попроси материалы и вопрос исследования.", "Compare the conclusions in my sources and flag disagreements. Ask for the material and research question."),
            task(.spreadsheet, "Сопоставить альтернативы", "Compare alternatives", "Собери таблицу альтернатив с критериями и поясни, каких данных не хватает. Спроси, какое решение предстоит принять.", "Compare alternatives in a table and flag missing evidence. Ask what decision the comparison should support."),
            task(.flag, "Составить план исследования", "Plan a study", "Разбей вопрос на гипотезы, методы и критерии проверки. Уточни, что мы хотим узнать и сколько времени есть.", "Break the research question into hypotheses, methods and checks. Ask what we need to learn and how much time we have.")]
        case .development: return [
            task(.checkCircle, "Продумать тесты", "Design test cases", "Составь набор тестов для функции, включая граничные случаи. Попроси описание ожидаемого поведения.", "Design test cases for a feature, including boundary cases. Ask how the feature should behave."),
            task(.code, "Объяснить код", "Explain some code", "Объясни, как данные проходят через мой код, и разбери один пример. Попроси фрагмент кода.", "Trace how data moves through my code and walk through one example. Ask me for the snippet."),
            task(.pullRequest, "Проверить правку", "Review a patch", "Проверь изменение на регрессии и предложи, что проверить перед слиянием. Попроси diff и описание задачи.", "Review a patch for regressions and suggest checks before merging. Ask for the diff and intended behavior."),
            task(.branch, "Спланировать реализацию", "Plan a feature", "Разбей реализацию функции на небольшие шаги с критериями готовности. Уточни требования и какие части проекта затронуты.", "Break a feature into small implementation steps with acceptance criteria. Ask what it must do and which parts of the project it affects.")]
        }
    }
}
