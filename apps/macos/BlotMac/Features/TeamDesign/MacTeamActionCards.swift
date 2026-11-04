import BlotDesign
import SwiftUI

struct MacTeamMessageCard: View {
    let message: MacDemoMessage
    @Environment(MacTeamPresentation.self) private var presentation
    @ViewBuilder var body: some View {
        switch message.kind {
        case .onboarding:
            VStack(alignment: .leading, spacing: 12) {
                Text("За что отвечать агенту?").fontWeight(.semibold)
                Text("Выберите направление или опишите свою задачу в сообщении.").foregroundStyle(.secondary)
                ForEach(["Повседневные задачи", "Финансы", "Контент", "Исследования", "Поддержка"], id: \.self) {
                    role in
                    MacTeamNavigationButton {
                        presentation.demo.configureAgent(message.authorID ?? presentation.agent.id, role: role)
                    } label: {
                        HStack {
                            Text(role)
                            Spacer()
                            BlotIcon(symbol: "arrow.up.left", size: BlotIconSize.inline).foregroundStyle(WorkspaceStyle.ink)
                        }
                    }
                }
            }.font(.system(size: 12)).teamCard()
        case .briefing:
            VStack(spacing: 4) {
                cardAction("Письма, которым нужен ответ", detail: "Два демо-аккаунта Gmail", symbol: "envelope", pluginID: "gmail") {
                    presentation.send("Покажи письма без ответа")
                }
                cardAction("Неоплаченные счета", detail: "Два счёта · $1,840", symbol: "creditcard") {
                    presentation.send("Покажи неоплаченные счета")
                }
                cardAction(
                    "Встречи и следующий шаг", detail: presentation.demo.state.events.first ?? "Нет встреч",
                    symbol: "calendar"
                ) { presentation.send("Покажи календарь") }
                Text("Slack: Команда · Проекты · Клиенты. Макеты ждут согласования, запуск проекта — в понедельник.")
                    .font(.system(size: 11)).foregroundStyle(.secondary).padding(10)
            }.teamCard(padding: 6)
        case .connection:
            if let plugin = presentation.plugins.first(where: { $0.id == message.referenceID }) {
                Button {
                    presentation.sheet = .plugin(plugin)
                } label: {
                    HStack(spacing: 12) {
                        MacTeamPluginIcon(plugin: plugin)
                        VStack(alignment: .leading, spacing: 5) {
                            Text(plugin.name).fontWeight(.medium)
                            Text(
                                plugin.accounts.isEmpty
                                    ? "Добавить демо-аккаунт" : "Аккаунтов: \(plugin.accounts.count)"
                            ).foregroundStyle(.secondary)
                        }
                        Spacer()
                        BlotIcon(symbol: "arrow.up.right", size: BlotIconSize.inline)
                    }.font(.system(size: 12)).teamCard()
                }.buttonStyle(BlotPlainButtonStyle())
            }
        case .email:
            if let email = presentation.demo.state.emails.first(where: { $0.id == message.referenceID }) {
                MacTeamEmailCard(email: email)
            }
        case .routine:
            if let routine = presentation.routines.first(where: { $0.id == message.referenceID }) {
                cardAction(routine.title, detail: routine.schedule, symbol: "clock.arrow.circlepath") {
                    presentation.sheet = .routine(routine.id)
                }.teamCard(padding: 4)
            }
        case .products: MacTeamProductResults(initialBudget: Double(message.referenceID ?? "500") ?? 500)
        case .transactions: MacTeamTransactionCard()
        case .invoices:
            VStack(alignment: .leading, spacing: 14) {
                Text("Открытые счета").fontWeight(.semibold)
                HStack {
                    Text("North Studio · 5 дней просрочки")
                    Spacer()
                    Text("$1,240")
                }
                Divider()
                HStack {
                    Text("Green Market · срок в пятницу")
                    Spacer()
                    Text("$600")
                }
                Button("Подготовить напоминание") { presentation.showEmail("invoice-north") }.buttonStyle(
                    WorkspaceButtonStyle())
            }.font(.system(size: 12)).teamCard()
        case .document:
            if let document = presentation.demo.state.documents.first(where: { $0.id == message.referenceID }) {
                cardAction(
                    document.title,
                    detail: document.published ? "Сохранён в демо-рассылках" : "Черновик · можно редактировать",
                    symbol: "doc.text", filename: document.title
                ) { presentation.showDocument(document.id) }.teamCard(padding: 4)
            }
        case .suggestions:
            VStack(spacing: 4) {
                ForEach(
                    [
                        "Проверь почту", "Каждое утро в 9:00 присылай обзор почты и Slack",
                        "Создай агента для контента", "Подготовь контент-план",
                    ], id: \.self
                ) { text in
                    MacTeamNavigationButton {
                        presentation.send(text)
                    } label: {
                        HStack {
                            Text(text)
                            Spacer()
                            BlotIcon(symbol: "arrow.up.left", size: BlotIconSize.inline).foregroundStyle(WorkspaceStyle.ink)
                        }
                    }
                }
            }.font(.system(size: 12)).teamCard(padding: 6)
        case .agentCreated:
            if let id = message.referenceID {
                Button("Открыть агента") { presentation.open(.agent(id)) }.buttonStyle(WorkspaceButtonStyle(.secondary))
            }
        case .event:
            VStack(alignment: .leading, spacing: 10) {
                ForEach(presentation.demo.state.events, id: \.self) { BlotLabel($0, symbol: "calendar", size: BlotIconSize.inline) }
            }.font(.system(size: 12)).teamCard()
        case .text: EmptyView()
        }
    }
    private func cardAction(_ title: String, detail: String, symbol: String, pluginID: String? = nil, filename: String? = nil,
                            action: @escaping () -> Void) -> some View
    {
        MacTeamNavigationButton(action: action) {
            HStack(spacing: 12) {
                if let filename {
                    MacTeamFileIcon(filename: filename)
                } else if let plugin = presentation.plugins.first(where: { $0.id == pluginID && !$0.accounts.isEmpty }) {
                    MacTeamPluginIcon(plugin: plugin, size: 28)
                } else {
                    BlotIcon(symbol: symbol, size: BlotIconSize.navigation).frame(width: 28)
                }
                VStack(alignment: .leading, spacing: 5) {
                    Text(title).font(.system(size: 12, weight: .medium))
                    Text(detail).font(.system(size: 11)).foregroundStyle(.secondary)
                }
                Spacer()
                BlotIcon(symbol: "chevron.right", size: BlotIconSize.inline).foregroundStyle(WorkspaceStyle.ink)
            }
        }
    }
}

struct MacTeamEmailCard: View {
    let email: MacDemoEmail
    @Environment(MacTeamPresentation.self) private var presentation
    private var gmail: MacTeamPlugin? {
        guard email.agentID != "support",
              presentation.demo.state.connections.contains(where: { $0.pluginID == "gmail" && $0.label == email.accountLabel }) else { return nil }
        return presentation.plugins.first { $0.id == "gmail" }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                if let gmail {
                    HStack(spacing: 8) {
                        MacTeamPluginIcon(plugin: gmail, size: 24)
                        Text(email.sender).fontWeight(.semibold)
                    }
                } else {
                    BlotLabel(email.sender, symbol: "envelope", size: BlotIconSize.inline).fontWeight(.semibold)
                }
                Spacer()
                MacTeamBadge(text: email.sent ? "Отправлено в демо" : "Черновик")
            }
            Text(email.subject).fontWeight(.medium)
            Text(email.sent ? email.reply : email.incoming).lineSpacing(4)
            HStack {
                Text(email.accountLabel).font(.system(size: 10)).foregroundStyle(.secondary)
                Spacer()
                Button(email.sent ? "Посмотреть ответ" : "Проверить ответ") { presentation.showEmail(email.id) }
                    .buttonStyle(WorkspaceButtonStyle(.secondary))
            }
        }.font(.system(size: 12)).teamCard()
    }
}

struct MacTeamTransactionCard: View {
    @Environment(MacTeamPresentation.self) private var presentation
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Операции QuickBooks · демо").fontWeight(.semibold)
            ForEach(presentation.demo.state.transactions) { row in
                HStack {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(row.vendor)
                        Text(row.category).font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(row.amount, format: .currency(code: "USD"))
                    if row.approved { BlotIcon(symbol: "checkmark.circle", size: BlotIconSize.inline).accessibilityHidden(false).accessibilityLabel("Согласовано") }
                }
            }
            Button("Проверить категории") { presentation.sheet = .transactions }.buttonStyle(
                WorkspaceButtonStyle(.secondary))
        }.font(.system(size: 12)).teamCard()
    }
}

private struct MacTeamProductResults: View {
    let initialBudget: Double
    @Environment(MacTeamPresentation.self) private var presentation
    @State private var budgetText = "500"
    @State private var sort = "По отзывам"
    private var products: [MacDemoProduct] {
        let budget = Double(budgetText.replacingOccurrences(of: ",", with: ".")) ?? 0
        return presentation.demo.state.products.filter { $0.price <= budget }.sorted {
            sort == "По цене"
                ? $0.price < $1.price : (Double($0.rating.prefix(3)) ?? 0) > (Double($1.rating.prefix(3)) ?? 0)
        }
    }
    private var cart: [MacDemoProduct] {
        presentation.demo.state.products.filter { (presentation.demo.state.cart ?? []).contains($0.id) }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Сравнение саундбаров").font(.system(size: 14, weight: .semibold))
            Text("Сохранённая подборка из видео · демонстрационные цены").font(.system(size: 10)).foregroundStyle(
                .secondary)
            HStack(spacing: 10) {
                Text("Бюджет, $")
                TextField("500", text: $budgetText).frame(width: 80).accessibilityLabel("Бюджет сравнения")
                Spacer()
                MacTeamSelect(
                    title: "Сортировка", selection: $sort, values: ["По отзывам", "По цене"], showsTitle: false)
            }
            ForEach(products) { product in
                VStack(alignment: .trailing, spacing: 6) {
                    MacTeamNavigationButton(selected: product.selected) {
                        presentation.demo.update { state in
                            for index in state.products.indices {
                                state.products[index].selected = state.products[index].id == product.id
                            }
                            state.threads[presentation.conversationKey, default: []].append(
                                .init(
                                    authorID: presentation.agent.id,
                                    text: "Выбран \(product.name). \(product.detail). Выбор сохранён в демо-подборке."))
                        }
                    } label: {
                        HStack(spacing: 12) {
                            BlotIcon(symbol: "hifispeaker.2", size: BlotIconSize.illustration).frame(width: 42, height: 50)
                            VStack(alignment: .leading, spacing: 5) {
                                HStack {
                                    Text(product.name).fontWeight(.medium)
                                    Spacer()
                                    Text(product.price, format: .currency(code: "USD"))
                                }
                                Text(product.detail).foregroundStyle(.secondary)
                                Text(product.rating).font(.system(size: 10)).foregroundStyle(.secondary)
                                Text(product.referenceURL).font(.system(size: 10)).foregroundStyle(.secondary)
                                    .textSelection(.enabled).help("Ссылка для поиска. В демо сайты не открываются.")
                            }
                        }
                    }
                    Button(cart.contains(where: { $0.id == product.id }) ? "В демо-корзине" : "Добавить в демо-корзину")
                    { presentation.demo.addToCart(product.id) }
                    .buttonStyle(WorkspaceButtonStyle(.secondary)).disabled(cart.contains { $0.id == product.id })
                }
            }
            if products.isEmpty {
                Text("В сохранённой подборке нет вариантов с таким бюджетом.").foregroundStyle(.secondary).padding(
                    .vertical, 12)
            }
            if !cart.isEmpty {
                Divider()
                Text("Демо-корзина").fontWeight(.semibold)
                ForEach(cart) { product in
                    HStack {
                        Text(product.name)
                        Spacer()
                        Text(product.price, format: .currency(code: "USD"))
                        MacTeamIconButton(title: "Убрать из корзины", symbol: "xmark") {
                            presentation.demo.update { $0.cart = ($0.cart ?? []).filter { $0 != product.id } }
                        }
                    }
                }
                HStack {
                    Text(cart.reduce(0) { $0 + $1.price }, format: .currency(code: "USD")).fontWeight(.semibold)
                    Spacer()
                    Button("Оформить демо-заказ") {
                        presentation.demo.checkoutDemoOrder(
                            conversation: presentation.conversationKey, agentID: presentation.agent.id)
                    }.buttonStyle(WorkspaceButtonStyle())
                }
                Text("Без оплаты, обращения в магазин и доставки.").font(.system(size: 10)).foregroundStyle(.secondary)
            }
        }.font(.system(size: 12)).teamCard(padding: 14)
            .kAnimation(KMotion.standard, value: products.map(\.id))
            .kAnimation(KMotion.standard, value: cart.map(\.id))
            .onAppear { budgetText = String(format: "%.0f", initialBudget) }
    }
}
