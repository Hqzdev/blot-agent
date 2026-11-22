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
        case .tables: (.init(light: 0x066634FF, dark: 0x66E7A0FF), 0x08C557FF)
        case .documents, .research: (.init(light: 0x1B55B5FF, dark: 0x96B9FFFF), 0x297CFFFF)
        case .presentations, .websites: (.init(light: 0x7035B9FF, dark: 0xD3A7FFFF), 0xA059FFFF)
        case .planning, .meetings: (.init(light: 0x934C05FF, dark: 0xFFB962FF), 0xF49521FF)
        case .agent, .development: (.init(light: 0x0B6094FF, dark: 0x78CEFFFF), 0x1099EFFF)
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
            task(.list, "Собрать инструкцию", "Write a how-to", "Преврати мои заметки в пошаговую инструкцию с проверкой результата. Попроси заметки.", "Turn my notes into step-by-step instructions with a final check. Ask me for the notes.")]
        case .tables: return [
            task(.spreadsheet, "Сравнить предложения", "Compare quotes", "Подготовь таблицу для сравнения предложений подрядчиков по цене, срокам и условиям. Спроси, какие предложения у меня есть.", "Build a table comparing vendor quotes by price, turnaround and terms. Ask me for the quotes."),
            task(.calendar, "Распределить смены", "Schedule shifts", "Составь недельную таблицу смен. Уточни часы работы, состав команды и ограничения по дням.", "Build a weekly shift table. Ask about opening hours, the team and availability.")]
        case .presentations: return [
            task(.presentation, "Подготовить демо", "Outline a demo", "Собери план пяти слайдов для демонстрации продукта. Спроси, кому показываем продукт и какое действие ждём после демо.", "Outline five slides for a product demo. Ask about the audience and what we want them to do next."),
            task(.usage, "Показать итоги", "Present results", "Предложи структуру короткой презентации об итогах проекта. Уточни цель проекта и какие результаты уже измерены.", "Outline a short presentation on project results. Ask about the original goal and the results we measured.")]
        case .websites: return [
            task(.globe, "Составить карту сайта", "Map out a site", "Предложи карту сайта и главное действие на каждой странице. Сначала спроси, что посетитель должен найти.", "Map out a website and one main action per page. First ask what visitors need to find."),
            task(.layout, "Написать первый экран", "Draft a homepage", "Предложи три варианта заголовка, подзаголовка и кнопки для главной страницы. Спроси про продукт и аудиторию.", "Draft three headline, subheading and button combinations for a homepage. Ask about the product and audience.")]
        case .planning: return [
            task(.flag, "Разбить проект на этапы", "Plan milestones", "Помоги разбить проект на этапы с проверяемым результатом. Уточни цель, срок и доступные ресурсы.", "Break a project into milestones with a clear outcome for each. Ask about the goal, deadline and available resources."),
            task(.calendar, "Спланировать неделю", "Plan my week", "Собери план недели с резервом времени. Попроси список дел, встреч и жёстких сроков.", "Plan my week with time to spare. Ask for my tasks, meetings and fixed deadlines.")]
        case .meetings: return [
            task(.list, "Собрать повестку", "Build an agenda", "Составь повестку с временем на каждый вопрос. Уточни длительность встречи и решение, которое нужно принять.", "Build a timed agenda. Ask how long the meeting is and what decision we need to reach."),
            task(.checkCircle, "Выделить поручения", "Extract action items", "Выдели из заметок решения, поручения, ответственных и сроки. Попроси заметки и отметь, где деталей не хватает.", "Extract decisions, action items, owners and dates from my meeting notes. Ask for the notes and flag missing details.")]
        case .research: return [
            task(.chat, "Подготовить интервью", "Prepare an interview", "Составь вопросы для исследовательского интервью. Уточни гипотезу и кого я собираюсь опросить.", "Draft research interview questions. Ask about my hypothesis and who I plan to interview."),
            task(.book, "Разобрать источники", "Review sources", "Сопоставь выводы моих источников и отметь противоречия. Попроси материалы и вопрос исследования.", "Compare the conclusions in my sources and flag disagreements. Ask for the material and research question.")]
        case .development: return [
            task(.checkCircle, "Продумать тесты", "Design test cases", "Составь набор тестов для функции, включая граничные случаи. Попроси описание ожидаемого поведения.", "Design test cases for a feature, including boundary cases. Ask how the feature should behave."),
            task(.code, "Объяснить код", "Explain some code", "Объясни, как данные проходят через мой код, и разбери один пример. Попроси фрагмент кода.", "Trace how data moves through my code and walk through one example. Ask me for the snippet.")]
        }
    }
}
