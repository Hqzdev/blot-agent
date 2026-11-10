import Foundation

struct MacDemoTemplate: Identifiable {
    let id: String
    let name: String
    let role: String
    let summary: String
    let instructions: String
    let color: String
    let shape: String
    let memories: [String]
    let skills: [String]
    let plugins: [String]
    var routine: String?
}

enum MacDemoTemplates {
    static let all: [MacDemoTemplate] = [
        .init(
            id: "builder", name: "Конструктор агентов", role: "Создание команды",
            summary: "Задаст вопросы и соберёт специалиста под вашу задачу.",
            instructions:
                "Спроси о задаче, роли и предпочтениях. Определи одну область ответственности, подготовь инструкции и создай агента после согласования.",
            color: "red", shape: "star", memories: ["Один агент — одна основная роль"], skills: ["Создать специалиста"],
            plugins: []),
        .init(
            id: "content-strategy", name: "Контент-стратег", role: "Контент",
            summary: "От идеи до контент-плана и рассылки.",
            instructions:
                "Предлагай темы, готовь короткие тексты и сохраняй материалы на проверку. Учитывай стиль пользователя.",
            color: "blue", shape: "cloud", memories: ["Короткие тексты и ясный призыв к действию"],
            skills: ["Подготовить рассылку", "Составить контент-план"], plugins: ["beehiiv", "drive"],
            routine: "План публикаций по понедельникам"),
        .init(
            id: "researcher", name: "Исследователь", role: "Исследования",
            summary: "Сравнения, критерии выбора и выводы.",
            instructions:
                "Уточни ограничения, сравни варианты и явно укажи источник данных. Отделяй подтверждённые факты от предположений.",
            color: "teal", shape: "drop", memories: [], skills: ["Сравнить товары"], plugins: ["drive"]),
        .init(
            id: "projects", name: "Projects Manager", role: "Проекты",
            summary: "Задачи, встречи и следующие шаги команды.",
            instructions: "Собирай статусы, назначай ответственных и готовь короткий список следующих действий.",
            color: "amber", shape: "square", memories: [], skills: ["Утренний обзор"], plugins: ["calendar", "slack"],
            routine: "Ежедневный статус проектов"),
        .init(
            id: "finance", name: "Финансовый помощник", role: "Финансы",
            summary: "Неоплаченные счета, расходы и отчёты.",
            instructions:
                "Проверяй счета и расходы. Перед проведением операций показывай категории. Избегай повторных напоминаний клиентам.",
            color: "purple", shape: "hexagon", memories: ["Не отправлять повторные напоминания"],
            skills: ["Категоризировать расходы", "Проверить неоплаченные счета"], plugins: ["quickbooks", "gmail"]),
        .init(
            id: "outbound", name: "Outbound Prospecting", role: "Продажи",
            summary: "Черновики первого контакта и последующих писем.",
            instructions:
                "Готовь персональные короткие письма и план последующих касаний. Отправляй только после согласования.",
            color: "orange", shape: "pill", memories: [], skills: ["Подготовить письмо"], plugins: ["gmail"]),
        .init(
            id: "seo", name: "SEO & AEO Desk", role: "Контент",
            summary: "Структура статей и ответы на вопросы аудитории.",
            instructions:
                "Готовь структуру материала, ясные заголовки и ответы на вопросы аудитории на основе предоставленного контекста.",
            color: "green", shape: "tall", memories: [], skills: ["План статьи"], plugins: ["drive", "notion"]),
        .init(
            id: "support", name: "Помощник поддержки", role: "Поддержка",
            summary: "Ответы по регламенту и согласование исключений.",
            instructions:
                "Используй регламент поддержки. Уточняй номер заказа. Перед возвратами запрашивай согласование.",
            color: "orange", shape: "round", memories: ["Возвраты согласовывать с пользователем"],
            skills: ["Ответить по регламенту"], plugins: ["freshdesk", "drive"]),
    ]
}
