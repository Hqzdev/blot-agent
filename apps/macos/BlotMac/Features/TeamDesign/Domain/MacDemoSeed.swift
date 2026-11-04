import Foundation

enum MacDemoSeed {
    static func make() -> MacDemoState {
        let agents: [MacDemoAgent] = [
            .init(
                id: "chief", name: "Blot", role: "Координатор",
                instructions: "Координируй команду, собирай короткие обзоры. Согласовывай отправку писем.",
                color: "purple", avatarShape: "round", preview: "Утренний обзор готов", unread: true),
            .init(
                id: "inbox", name: "Eagle Eye", role: "Почта",
                instructions: "Проверяй почту, выделяй важное и готовь ответы в моём стиле.", color: "red",
                avatarShape: "star", preview: "Два письма требуют ответа"),
            .init(
                id: "finance", name: "Dough", role: "Финансы",
                instructions: "Категоризируй расходы и следи за неоплаченными счетами.", color: "purple",
                avatarShape: "square", preview: "Три операции к проверке"),
            .init(
                id: "support", name: "Glaze", role: "Поддержка",
                instructions: "Готовь ответы по регламенту поддержки. Возвраты согласовывай.", color: "orange",
                avatarShape: "pill", preview: "Готов ответ по доставке"),
            .init(
                id: "research", name: "Scout", role: "Исследования",
                instructions: "Сравнивай варианты по цене, характеристикам и отзывам.", color: "teal",
                avatarShape: "drop", preview: "Подборка саундбаров до $500"),
            .init(
                id: "content", name: "Penny", role: "Контент", instructions: "Готовь контент-план и короткие рассылки.",
                color: "blue", avatarShape: "cloud", preview: "Черновик рассылки готов"),
        ]
        let routines: [MacDemoRoutine] = [
            .init(
                id: "brief", title: "Утренний обзор", agentID: "chief",
                instructions:
                    "Проверь три пространства Slack, почту и календарь. Покажи вопросы, требующие моего решения."),
            .init(
                id: "orders", title: "Новые заказы", agentID: "inbox",
                instructions: "Проверь письма и подготовь ответы на новые заказы.", frequency: "Каждый час"),
            .init(
                id: "tickets", title: "Очередь поддержки", agentID: "support",
                instructions: "Подготовь ответы по регламенту.", frequency: "Каждый день", time: "10:00"),
            .init(
                id: "expenses", title: "Проверка расходов", agentID: "finance",
                instructions: "Сверь операции и подготовь недельный отчёт.", enabled: false, frequency: "По пятницам",
                time: "16:00", weekdays: ["Пт"]),
        ]
        return MacDemoState(
            agents: agents,
            groups: [.init(id: "orders", name: "Заказы и финансы", agentIDs: ["chief", "finance", "inbox"])],
            routines: routines,
            threads: [
                "agent:chief": [
                    .init(
                        authorID: "chief", text: "Доброе утро! Команда подготовила обзор. С чего начнём?",
                        kind: .briefing)
                ],
                "agent:inbox": [
                    .init(
                        authorID: "inbox", text: "В двух почтовых аккаунтах есть письма, которым нужен ответ.",
                        kind: .email, referenceID: "anna"),
                    .init(
                        authorID: "inbox",
                        text: "Лиза прислала согласованный план. Можно поблагодарить её в той же цепочке.",
                        kind: .email, referenceID: "lisa"),
                ],
                "agent:finance": [
                    .init(
                        authorID: "finance",
                        text: "Подобрал категории для трёх операций. Проверьте перед согласованием.",
                        kind: .transactions)
                ],
                "agent:support": [
                    .init(
                        authorID: "support", text: "Подготовил ответ по регламенту поддержки.", kind: .email,
                        referenceID: "support")
                ],
                "agent:research": [
                    .init(
                        authorID: "research", text: "Сравнил три саундбара дешевле $500 на сохранённых демо-данных.",
                        kind: .products)
                ],
                "agent:content": [
                    .init(
                        authorID: "content",
                        text: "Подготовил черновик пятничной рассылки. Его можно отредактировать и сохранить.",
                        kind: .document, referenceID: "newsletter")
                ],
                "group:orders": [
                    .init(
                        authorID: "chief",
                        text: "Команда готова. Поручите нам общую задачу — например, разберите неоплаченные счета.")
                ],
            ],
            memories: [
                .init(id: "short", text: "Пиши коротко и по делу", agentID: nil),
                .init(id: "approval", text: "Перед отправкой показывай черновик", agentID: "inbox"),
            ],
            skills: [
                .init(
                    id: "brief", title: "Подготовить утренний обзор",
                    instructions: "Проверь почту, три пространства Slack и встречи. Выдели три главных действия.",
                    agentID: "chief"),
                .init(
                    id: "expenses", title: "Категоризировать расходы",
                    instructions: "Определи контрагента, выбери категорию и запроси согласование.", agentID: "finance"),
                .init(
                    id: "support", title: "Ответить по регламенту",
                    instructions: "Прочитай обращение, сверь регламент и подготовь короткий ответ.", agentID: "support"),
            ],
            connections: [
                .init(
                    id: "gmail-personal", pluginID: "gmail", label: "Личная почта", account: "personal@demo.blot",
                    allowSend: true),
                .init(
                    id: "gmail-work", pluginID: "gmail", label: "Рабочая почта", account: "work@demo.blot",
                    allowSend: true),
                .init(id: "calendar", pluginID: "calendar", label: "Мой календарь", account: "work@demo.blot"),
                .init(id: "drive", pluginID: "drive", label: "Рабочий диск", account: "work@demo.blot"),
                .init(id: "slack", pluginID: "slack", label: "Blot Team", account: "Команда · Проекты · Клиенты"),
                .init(id: "quickbooks", pluginID: "quickbooks", label: "Мой бизнес", account: "Demo Company"),
                .init(
                    id: "freshdesk", pluginID: "freshdesk", label: "Поддержка", account: "support@demo.blot",
                    allowSend: true),
            ],
            emails: [
                .init(
                    id: "invoice-north", sender: "North Studio", address: "accounts@north.demo.blot",
                    subject: "Напоминание · счёт #208", incoming: "Счёт на $1,240 ожидает оплаты уже пять дней.",
                    reply:
                        "Здравствуйте! Напоминаю о счёте #208 на $1,240. Подскажите, пожалуйста, когда можно ожидать оплату. Спасибо!",
                    agentID: "inbox"),
                .init(
                    id: "invoice-green", sender: "Green Market", address: "accounts@green.demo.blot",
                    subject: "Счёт #209 · срок в пятницу", incoming: "Счёт на $600, срок оплаты — в пятницу.",
                    reply: "Здравствуйте! Напоминаю, что срок оплаты счёта #209 на $600 — в пятницу. Спасибо!",
                    agentID: "inbox"),
                .init(
                    id: "anna", sender: "Анна", address: "anna@demo.blot", subject: "Заказ к пятнице",
                    incoming: "Здравствуйте! Нам нужны шесть коробок к пятнице. Можно оформить доставку?",
                    reply:
                        "Анна, здравствуйте! Спасибо за новый заказ. Уточните время и адрес доставки. Нужны ли снова коробки с логотипом?",
                    agentID: "inbox"),
                .init(
                    id: "lisa", sender: "Лиза", address: "lisa@demo.blot", subject: "План согласован",
                    incoming: "Привет! План согласован, можем начинать в понедельник.",
                    reply: "Лиза, спасибо! План получил, начинаем в понедельник.", agentID: "inbox",
                    accountLabel: "Личная почта"),
                .init(
                    id: "support", sender: "Клиент", address: "customer@demo.blot",
                    subject: "#104 · Уточнение доставки", incoming: "Подскажите время доставки моего заказа.",
                    reply:
                        "Здравствуйте! Уточните номер заказа и удобный интервал доставки. Мы проверим детали и вернёмся с подтверждением.",
                    agentID: "support"),
            ],
            documents: [
                .init(
                    id: "sop", title: "Регламент поддержки.docx",
                    body:
                        "Доставка\nУточняйте номер заказа, дату и адрес.\n\nОтветы клиентам\nПишите коротко и вежливо.\n\nВозвраты\nСогласовывайте сумму с ответственным до подтверждения.",
                    agentID: "support"),
                .init(
                    id: "newsletter", title: "Пятничная рассылка.md",
                    body:
                        "Что мы сделали за неделю\n\nПривет! Собрали три полезных обновления:\n\n1. Единый обзор писем и встреч.\n2. Меньше повторяющихся задач.\n3. Команда агентов, которая работает с общим контекстом.\n\nОтветьте на это письмо: что вы хотели бы автоматизировать?",
                    agentID: "content"),
            ],
            transactions: [
                .init(id: "water", vendor: "East Bay Water", category: "Коммунальные услуги", amount: 74.18),
                .init(id: "boxes", vendor: "BoxCraft Packaging", category: "Упаковка", amount: 96.75),
                .init(id: "flour", vendor: "Bay Area Flour", category: "Продукты", amount: 486.20),
            ],
            products: [
                .init(
                    id: "jbl", name: "JBL Bar 500", price: 349.95, rating: "4.6 · 738 отзывов",
                    detail: "5.1 · беспроводной сабвуфер · Dolby Atmos"),
                .init(
                    id: "tcl", name: "TCL Q65H", price: 297.99, rating: "4.6 · 62 отзыва",
                    detail: "5.1 · Atmos + DTS:X · HDMI eARC"),
                .init(
                    id: "samsung", name: "Samsung HW-Q600F", price: 364.99, rating: "Рейтинг не указан",
                    detail: "3.1.2 · Atmos · Q-Symphony"),
            ]
        )
    }
}
