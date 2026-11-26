import BlotAppleIntegrations
import BlotDesign
import BlotDomain
import BlotWorkspace
import SwiftUI
#if os(macOS)
import AppKit
#endif

extension EnvironmentValues {
    @Entry var workspaceCardDemonstration = false
}

struct WorkspaceConversationCards: View {
    let message: BlotV3.Message
    @Environment(WorkspaceStore.self) private var store
    var body: some View {
        ForEach(store.chatContent.cards[message.metadata.id] ?? [], id: \.metadata.id) { card in
            WorkspaceConversationCardView(card: card, fallback: message.content)
        }
    }
}

/// The same content components adapt to a desktop column and the full iPhone chat width.
struct WorkspaceConversationCardView: View {
    let card: BlotV3.ConversationCard
    let fallback: String
    @Environment(WorkspaceStore.self) private var store
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.workspaceCardDemonstration) private var demonstration
    @State private var editedMail: WorkspaceCardContent.MailDraft?
    @State private var editedSlack: String?
    @State private var selection: String?
    @State private var custom = ""
    @State private var secret = ""
    @State private var submitting = false
    @State private var failure: String?
    @State private var expired = false
    @State private var cookieSelection: Set<String>?
    @State private var reviewingMail = false
    private var ru: Bool { store.language == "ru" }
    private var content: WorkspaceCardContent? { try? JSONDecoder().decode(WorkspaceCardContent.self, from: Data(card.payloadJSON.utf8)) }
    private var response: WorkspaceCardResponse? { card.responseJSON.flatMap { try? JSONDecoder().decode(WorkspaceCardResponse.self, from: Data($0.utf8)) } }
    private var action: BlotV3.PreparedAction? { store.snapshot.preparedActions?.first { $0.metadata.id == card.operationId } }
    private var active: Bool { card.state == "pending" && !expired && (card.expiresAt.map { $0 > Date() } ?? true) }
    private var field: Color { colorScheme == .dark ? Color.white.opacity(0.055) : Color.white.opacity(0.8) }

    var body: some View {
        GlassEffectContainer(spacing: 10) {
        VStack(alignment: .leading, spacing: 12) {
            if let content {
                switch content {
                case .subscription, .plugin: EmptyView()
                default: header(content)
                }
                contents(content)
            } else {
                Text(fallback).textSelection(.enabled)
            }
            if let failure { BlotLabel(failure, symbol: "exclamationmark.circle").font(secondaryFont).foregroundStyle(.red).accessibilityAddTraits(.updatesFrequently) }
        }
        .font(cardFont)
        .padding(12)
        .frame(maxWidth: 560, alignment: .leading)
        .blotPanel(fill: WorkspaceStyle.surface, radius: 22)
        }
        .kAnimation(KMotion.standard, value: selection)
        .kAnimation(KMotion.panel, value: card.state)
        .kAnimation(KMotion.panel, value: failure)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("workspace.chat.card.\(card.kind).\(card.metadata.id)")
        .disabled(demonstration)
        .task(id: card.expiresAt) {
            guard let deadline = card.expiresAt else { return }
            do { try await _Concurrency.Task.sleep(for: .seconds(max(0, deadline.timeIntervalSinceNow))); expired = true } catch {}
        }
        .onAppear {
            if case .email(let draft) = content, editedMail == nil {
                editedMail = response?.value.flatMap { try? JSONDecoder().decode(WorkspaceCardContent.MailDraft.self, from: Data($0.utf8)) } ?? draft
            }
            if case .slack(let draft) = content, editedSlack == nil { editedSlack = response?.value ?? draft.body }
        }
        .onDisappear { secret = "" }
        .workspaceConfirmationDialog(text("Проверьте «Отправленные» в Почте", "Check Mail’s Sent folder"), isPresented: $reviewingMail, titleVisibility: .visible) {
            Button(text("Письмо отправлено", "It was sent")) { respond("confirmed_sent") }
            Button(text("Письмо не отправлено", "It wasn't sent")) { respond("confirmed_not_sent") }
            Button(text("Отмена", "Cancel"), role: .cancel) {}
        }
    }

    private var cardFont: Font {
        #if os(macOS)
        .system(size: 14)
        #else
        .callout
        #endif
    }
    private var secondaryFont: Font {
        #if os(macOS)
        .system(size: 12)
        #else
        .caption
        #endif
    }
    private var badgeFont: Font {
        #if os(macOS)
        .system(size: 11)
        #else
        .caption2
        #endif
    }
    private var statusColor: Color {
        if action?.state == .failed || action?.state == .unknown { return .red }
        if case .task(let result) = content { return result.state == "completed" ? .green : .red }
        if active, case .command = content { return .orange }
        return .secondary
    }
    private func text(_ russian: String, _ english: String) -> String { ru ? russian : english }
    private func header(_ content: WorkspaceCardContent) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            if case .slack = content { Image("PluginSlack").resizable().scaledToFit().frame(width: 18, height: 18).accessibilityHidden(true) }
            Text(title(content)).font(cardFont)
            Spacer(minLength: 0)
            if case .question = content, active {
                Button { respond("dismiss") } label: { BlotIcon(symbol: "xmark").font(secondaryFont).frame(width: 20, height: 20).blotHitArea() }
                    .buttonStyle(BlotHitTargetButtonStyle(expansion: 12)).foregroundStyle(.secondary).disabled(submitting).accessibilityLabel(text("Закрыть вопрос", "Dismiss question"))
            } else {
            Text(status).font(badgeFont).foregroundStyle(statusColor).multilineTextAlignment(.trailing)
                .padding(.horizontal, 6).padding(.vertical, 3).background(WorkspaceStyle.ink.opacity(0.035), in: Capsule())
            }
        }
    }
    private var status: String {
        if case .page = content { return text("Сохранено", "Saved") }
        if case .task(let task) = content { return task.state == "completed" ? text("Выполнено", "Completed") : text("Ошибка", "Failed") }
        if case .plugin = content { return "" }
        if let action {
            switch action.state {
            case .running: return text("Выполняется", "Running")
            case .succeeded: return text("Выполнено", "Completed")
            case .failed: return text("Ошибка", "Failed")
            case .unknown: return text("Проверьте результат", "Verify outcome")
            case .denied: return text("Отклонено", "Denied")
            case .expired: return text("Истекло", "Expired")
            default: break
            }
        }
        if submitting { return text("Сохранение…", "Saving…") }
        if let response {
            switch response.action {
            case "submit": return text("Ответ сохранён", "Answered")
            case "allow", "allow_domains": return text("Разрешено один раз", "Allowed once")
            case "allow_rule": return text("Правило сохранено", "Rule saved")
            case "deny", "discard", "skip", "dismiss": return text("Закрыто", "Dismissed")
            case "saved": return text("Сохранено в Связке ключей", "Saved to Keychain")
            default: return text("Передано на выполнение", "Submitted")
            }
        }
        if active {
            switch content {
            case .email, .slack: return text("Готово к отправке", "Ready to send")
            case .command: return text("Нужно разрешение", "Approval needed")
            default: return text("Ожидает вас", "Needs you")
            }
        }
        return text("Истекло", "Expired")
    }

    @ViewBuilder private func contents(_ content: WorkspaceCardContent) -> some View {
        switch content {
        case .email(let draft):
            let savedDraft = response?.value.flatMap { try? JSONDecoder().decode(WorkspaceCardContent.MailDraft.self, from: Data($0.utf8)) }
            mail(active ? editedMail ?? draft : savedDraft ?? draft, editing: active)
            Text(text("Вложения проверьте в черновике в Почте.", "Review attachments in the Mail draft.")).font(secondaryFont).foregroundStyle(.secondary)
            if active {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 12) { mailActions(draft) }
                    VStack(alignment: .leading, spacing: 8) { mailActions(draft) }
                }
            }
        case .question(let question):
            if let answer = response?.value { Text(answer).padding(12).frame(maxWidth: .infinity, alignment: .leading).background(field, in: RoundedRectangle(cornerRadius: 14)) }
            else {
                VStack(spacing: 0) {
                    ForEach(Array(question.choices.enumerated()), id: \.offset) { index, choice in
                        if index > 0 { Divider() }
                        Button { selection = choice } label: {
                            HStack(alignment: .top, spacing: 10) {
                                Text(index < 26 ? String(UnicodeScalar(65 + index)!) : String(index + 1))
                                    .font(.caption2).foregroundStyle(.secondary).frame(width: 20, height: 20)
                                    .background(WorkspaceStyle.ink.opacity(0.055), in: RoundedRectangle(cornerRadius: 8))
                                Text(choice).frame(maxWidth: .infinity, alignment: .leading)
                                if selection == choice { BlotIcon(symbol: "checkmark").accessibilityHidden(true) }
                            }.padding(.horizontal, 10).padding(.vertical, 8).frame(minHeight: minimumHeight)
                                .background(selection == choice ? WorkspaceStyle.ink.opacity(0.06) : .clear).contentShape(Rectangle())
                        }.buttonStyle(BlotPlainButtonStyle()).disabled(!active || submitting).accessibilityAddTraits(selection == choice ? .isSelected : [])
                    }
                }.background(field, in: RoundedRectangle(cornerRadius: 14)).clipShape(RoundedRectangle(cornerRadius: 14))
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .bottom, spacing: 8) { questionActions(question) }
                    VStack(alignment: .leading, spacing: 8) { questionActions(question) }
                }
            }
        case .page(let page):
            Text(page.title).font(cardFont)
            primary(text("Открыть страницу", "Open page"), requiresPending: false) {
                store.selectedPageID = page.id
                #if os(macOS)
                let browser = store.ensureBrowser()
                do { _ = try browser.openLocalPage("page:pages", title: "Library"); browser.presented = true }
                catch { failure = error.localizedDescription }
                #else
                store.navigate(.pages)
                #endif
            }
        case .purchase(let order):
            Text(order.merchant).font(cardFont)
            Text(order.checkoutURL.host ?? "").font(secondaryFont).foregroundStyle(.secondary)
            VStack(spacing: 8) {
                ForEach(Array(order.items.enumerated()), id: \.offset) { _, item in
                    price(item.title, "\(item.quantity) × " + purchaseAmount(item.unitAmountMinor, currency: order.currency))
                }
                if order.taxMinor > 0 { price(text("Налог", "Tax"), purchaseAmount(order.taxMinor, currency: order.currency)) }
                if order.deliveryMinor > 0 { price(text("Доставка", "Delivery"), purchaseAmount(order.deliveryMinor, currency: order.currency)) }
                Divider()
                price(text("Итого", "Total"), purchaseAmount(order.totalMinor, currency: order.currency))
            }.padding(12).background(field, in: RoundedRectangle(cornerRadius: 14))
            Text(text("После подтверждения агент нажмёт оплату этого заказа. Банк может запросить ваше подтверждение.", "After approval the agent will submit this order. Your bank may request verification.")).font(secondaryFont).foregroundStyle(.secondary)
            if active {
                HStack(spacing: 12) {
                    primary(text("Подтвердить покупку", "Approve purchase")) { respond("allow") }
                    secondaryButton(text("Отклонить", "Deny"), action: "deny")
                }
            }
        case .subscription:
            WorkspaceBillingView(showsLimits: false, cardID: card.metadata.id)
        case .command(let command):
            Text(command.details).foregroundStyle(.secondary).textSelection(.enabled)
            if let action, action.resource.hasPrefix("browser:"), let tabID = UUID(uuidString: String(action.resource.dropFirst("browser:".count))),
               card.executorDeviceId == store.snapshot.localDeviceID {
                Button(text("Открыть вкладку", "Open tab")) {
                    do { try store.showBrowserTab(tabID) }
                    catch { failure = text("Вкладка недоступна", "Tab is unavailable") }
                }.font(secondaryFont)
            } else if action?.toolId.hasPrefix("browser_") != true {
                DisclosureGroup(text("Показать команду", "Show command")) {
                    ScrollView(.horizontal) { Text(command.command).font(.system(.caption, design: .monospaced)).textSelection(.enabled).padding(12) }
                        .background(field, in: RoundedRectangle(cornerRadius: 14))
                }.font(secondaryFont)
            }
            if let scope = command.ruleScope {
                Text(text("Только эта команда и агент в проекте «", "Only this command and agent in project “") + scope + text("» на этом Mac. Отзыв — в настройках проекта.", "” on this Mac. Revoke in project settings.")).font(secondaryFont).foregroundStyle(.secondary)
            }
            if active {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 8) { commandButtons(command) }
                    VStack(alignment: .leading, spacing: 8) { commandButtons(command) }
                }
            }
        case .takeover(let handoff):
            Text(handoff.reason).font(cardFont)
            #if os(macOS)
            if card.executorDeviceId == store.snapshot.localDeviceID { MacChatBrowserPreview(tabID: handoff.tabID, height: 200) }
            #endif
            if active {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 8) { takeoverActions(handoff) }
                    VStack(alignment: .leading, spacing: 8) { takeoverActions(handoff) }
                }
            }
            if card.executorDeviceId != store.snapshot.localDeviceID { Text(text("Завершите этот шаг на устройстве выполнения.", "Finish this step on the executor device.")).font(secondaryFont).foregroundStyle(.secondary) }
        case .task(let result):
            Text(result.title).font(cardFont).textSelection(.enabled)
            if let branch = result.branch { BlotLabel(branch, symbol: "arrow.triangle.branch").font(secondaryFont).foregroundStyle(.purple).textSelection(.enabled) }
            if !result.files.isEmpty {
                DisclosureGroup("\(result.files.count) " + text("изменённых файлов", "files changed")) {
                    ForEach(result.files, id: \.self) { file in BlotLabel(file, symbol: "doc.text").font(secondaryFont).textSelection(.enabled) }
                }.font(secondaryFont)
            }
            if let added = result.additions, let deleted = result.deletions {
                HStack(spacing: 8) { Text("+\(added)").foregroundStyle(.green); Text("−\(deleted)").foregroundStyle(.red) }.font(secondaryFont.monospacedDigit())
            }
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) { taskActions(result) }
                VStack(alignment: .leading, spacing: 8) { taskActions(result) }
            }
        case .slack(let draft):
            VStack(alignment: .leading, spacing: 10) {
                mailField(text("Пространство", "Workspace"), draft.workspace); Divider()
                mailField(text("Кому", "To"), draft.channel); Divider()
                if let thread = draft.thread { mailField(text("Ветка", "Thread"), thread); Divider() }
                TextField(text("Сообщение", "Message"), text: Binding(get: { active ? editedSlack ?? draft.body : response?.value ?? draft.body }, set: { editedSlack = $0 }), axis: .vertical)
                    .lineLimit(3...16).textFieldStyle(.plain).disabled(!active || submitting)
            }.padding(12).background(field, in: RoundedRectangle(cornerRadius: 14))
            if active {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 12) { slackActions(draft) }
                    VStack(alignment: .leading, spacing: 8) { slackActions(draft) }
                }
            }
        case .connectionRequest(let request):
            WorkspacePluginRequestView(request: request, card: card, active: active)
        case .plugin(let plugin):
            pluginRow(plugin)
        case .credential(let credential):
            Text(credential.purpose).font(cardFont)
            if active {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 8) { credentialActions(credential) }
                    VStack(alignment: .leading, spacing: 8) { credentialActions(credential) }
                }
                BlotLabel(text("Хранится в Связке ключей устройства выполнения.", "Stored in the executor device's Keychain."), symbol: "checkmark.shield").font(secondaryFont).foregroundStyle(.secondary)
                if card.executorDeviceId != store.snapshot.localDeviceID {
                    Text(text("Откройте эту карточку на устройстве выполнения.", "Open this card on the executor device.")).font(secondaryFont).foregroundStyle(.secondary)
                }
            }
        case .cookies(let transfer):
            Text(text("Перенести вход между профилями браузера Ori", "Transfer sign-in between Ori browser profiles")).font(cardFont)
            cookieDomains(transfer)
            if active {
                HStack(spacing: 8) {
                    primary(text("Разрешить один раз", "Allow once")) {
                        let selected = transfer.domains.filter { (cookieSelection ?? Set(transfer.domains)).contains($0) }
                        guard let data = try? JSONEncoder().encode(selected) else { return }
                        respond("allow_domains", value: String(decoding: data, as: UTF8.self))
                    }.disabled((cookieSelection ?? Set(transfer.domains)).isEmpty)
                    secondaryButton(text("Отклонить", "Deny"), action: "deny")
                }
            }
        case .mailFailure(let failure):
            BlotLabel(failure.detail, symbol: "exclamationmark.circle").foregroundStyle(.red)
            DisclosureGroup(text("Черновик сохранён", "Your draft is saved")) { mail(failure.draft) }.font(secondaryFont)
            Text(failure.outcomeUnknown ? text("Перед повтором проверьте «Отправленные» в Почте.", "Check Mail's Sent folder before retrying.") : text("Проверьте подключение к Почте.", "Check your Mail connection.")).font(secondaryFont).foregroundStyle(.secondary)
            if active {
                HStack(spacing: 8) {
                    primary(text("Проверить результат", "Check outcome")) { reviewingMail = true }
                    secondaryButton(text("Закрыть", "Dismiss"), action: "dismiss")
                }
            }
            if response?.action == "confirmed_not_sent" {
                Button {
                    guard let commands = store.cardCommands, !submitting else { return }
                    submitting = true
                    _Concurrency.Task { @MainActor in
                        defer { submitting = false }
                        do { try await commands.retryMailCard(card.metadata.id) }
                        catch { self.failure = text("Не удалось повторить. Проверьте подключение Почты.", "Couldn't retry. Check your Mail connection.") }
                    }
                } label: {
                    Text(text("Повторить отправку", "Try again")).frame(minHeight: minimumHeight).blotHitArea()
                }.buttonStyle(BlotHitTargetButtonStyle(expansion: 3)).disabled(submitting || card.executorDeviceId != store.snapshot.localDeviceID)
            }
        }
    }

    @ViewBuilder private func takeoverActions(_ handoff: WorkspaceCardContent.Takeover) -> some View {
        if card.executorDeviceId == store.snapshot.localDeviceID {
            primary(text("Открыть браузер", "Take over")) {
                do { try store.showBrowserTab(handoff.tabID) }
                catch { failure = text("Вкладка недоступна", "Tab is unavailable") }
            }
        }
        secondaryButton(text("Я закончил", "I'm done"), action: "done")
        secondaryButton(text("Пропустить", "Skip"), action: "skip")
    }
    @ViewBuilder private func taskActions(_ result: WorkspaceCardContent.TaskResult) -> some View {
        if let url = result.pullRequestURL, url.scheme == "https" { primary(text("Открыть PR", "View PR"), requiresPending: false) { store.openBrowserURL(url) } }
        if result.branch != nil || !result.files.isEmpty {
            Button(text("Открыть проект", "Open project")) {
                #if os(iOS)
                store.navigate(.files)
                #else
                let browser = store.ensureBrowser()
                do { _ = try browser.openLocalPage("projects", title: text("Терминал и Git", "Terminal and Git")); browser.presented = true }
                catch { failure = error.localizedDescription }
                #endif
            }.buttonStyle(WorkspaceButtonStyle(.secondary)).buttonBorderShape(.capsule)
        }
        #if os(macOS)
        if let project = cursorProject {
            Button(text("Открыть в Cursor", "Open in Cursor")) {
                NSWorkspace.shared.open([project.root], withApplicationAt: project.app, configuration: NSWorkspace.OpenConfiguration()) { _, error in
                    if error != nil { _Concurrency.Task { @MainActor in failure = text("Не удалось открыть Cursor", "Couldn't open Cursor") } }
                }
            }.buttonStyle(WorkspaceButtonStyle(.secondary)).buttonBorderShape(.capsule)
        }
        #endif
    }
    #if os(macOS)
    private var cursorProject: (app: URL, root: URL)? {
        guard let task = store.snapshot.tasks?.first(where: { $0.metadata.id == card.operationId }), task.execution.executorDeviceId == store.snapshot.localDeviceID,
              let project = store.snapshot.projects?.first(where: { $0.metadata.id == task.projectId }), project.repositoryPath.hasPrefix("/"),
              FileManager.default.fileExists(atPath: project.repositoryPath),
              let app = ["/Applications/Cursor.app", NSHomeDirectory() + "/Applications/Cursor.app"].first(where: { FileManager.default.fileExists(atPath: $0) }) else { return nil }
        return (URL(fileURLWithPath: app), URL(fileURLWithPath: project.repositoryPath))
    }
    #endif
    @ViewBuilder private func credentialActions(_ credential: WorkspaceCardContent.Credential) -> some View {
        SecureField(credential.name, text: $secret).textFieldStyle(.plain).privacySensitive().padding(10).background(field, in: RoundedRectangle(cornerRadius: 14))
        primary(text("Сохранить защищённо", "Save securely")) { saveSecret() }.fixedSize().disabled(secret.isEmpty || card.executorDeviceId != store.snapshot.localDeviceID)
    }
    private func cookieDomains(_ transfer: WorkspaceCardContent.CookieTransfer) -> some View {
        let source = store.browser?.profiles.first { $0.id == transfer.sourceProfileID }?.name ?? text("Исходный профиль", "Source profile")
        let destination = store.browser?.profiles.first { $0.id == transfer.destinationProfileID }?.name ?? text("Целевой профиль", "Destination profile")
        return VStack(alignment: .leading, spacing: 8) {
            Text(source + " → " + destination).font(secondaryFont.weight(.medium))
            ForEach(transfer.domains, id: \.self) { domain in
                Toggle(domain, isOn: Binding(get: {
                    if let response, let raw = response.value, let saved = try? JSONDecoder().decode([String].self, from: Data(raw.utf8)) { return saved.contains(domain) }
                    return (cookieSelection ?? Set(transfer.domains)).contains(domain)
                }, set: { value in
                    var selection = cookieSelection ?? Set(transfer.domains)
                    if value { selection.insert(domain) } else { selection.remove(domain) }; cookieSelection = selection
                })).font(secondaryFont).disabled(!active || submitting)
                #if os(macOS)
                .toggleStyle(.checkbox)
                #endif
            }
        }.padding(12).frame(maxWidth: .infinity, alignment: .leading).background(field, in: RoundedRectangle(cornerRadius: 14))
    }
    private func purchaseAmount(_ minor: Int, currency: String) -> String {
        (Double(minor) / 100).formatted(.currency(code: currency))
    }
    private func price(_ name: String, _ price: String) -> some View {
        HStack { Text(name); Spacer(); Text(price).foregroundStyle(.secondary) }
    }
    private func mail(_ draft: WorkspaceCardContent.MailDraft, editing: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            mailField(text("От", "From"), draft.sender); Divider()
            if editing {
                HStack { Text(text("Кому", "To")).foregroundStyle(.secondary); TextField(text("Кому", "To"), text: mailBinding(\.recipient)).textFieldStyle(.plain) }; Divider()
                HStack { Text(text("Тема", "Subject")).foregroundStyle(.secondary); TextField(text("Тема", "Subject"), text: mailBinding(\.subject)).textFieldStyle(.plain) }; Divider()
                TextField(text("Текст письма", "Message"), text: mailBinding(\.body), axis: .vertical).lineLimit(5...20).textFieldStyle(.plain)
            } else {
                mailField(text("Кому", "To"), draft.recipient); Divider()
                mailField(text("Тема", "Subject"), draft.subject); Divider()
                Text(draft.body).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
            }
        }.padding(12).background(field, in: RoundedRectangle(cornerRadius: 14))
    }
    private func mailBinding(_ key: WritableKeyPath<WorkspaceCardContent.MailDraft, String>) -> Binding<String> {
        Binding(get: { editedMail?[keyPath: key] ?? "" }, set: { editedMail?[keyPath: key] = $0 })
    }
    private func mailField(_ title: String, _ value: String) -> some View {
        HStack(alignment: .top, spacing: 12) { Text(title).foregroundStyle(.secondary); Text(value).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) }
    }
    private func primary(_ title: String, requiresPending: Bool = true, perform: @escaping () -> Void) -> some View {
        Button(action: perform) {
            Text(title).font(cardFont).padding(.horizontal, 8).frame(minHeight: minimumHeight)
        }.buttonStyle(WorkspaceButtonStyle()).tint(WorkspaceStyle.ink).buttonBorderShape(.capsule)
            .disabled((requiresPending && !active) || submitting)
    }
    private var minimumHeight: CGFloat {
        #if os(iOS)
        44
        #else
        30
        #endif
    }
    @ViewBuilder private func buttons(primary title: String, action: String, secondary: String, secondaryAction: String) -> some View {
        if active {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) { primary(title) { respond(action) }; secondaryButton(secondary, action: secondaryAction) }
                VStack(alignment: .leading, spacing: 6) { primary(title) { respond(action) }; secondaryButton(secondary, action: secondaryAction) }
            }
        }
    }
    private func secondaryButton(_ title: String, action: String) -> some View {
        Button { respond(action) } label: {
            Text(title).padding(.horizontal, 6).frame(minHeight: minimumHeight)
        }.buttonStyle(WorkspaceButtonStyle(.secondary)).buttonBorderShape(.capsule).foregroundStyle(WorkspaceStyle.ink).disabled(submitting)
    }
    private func respond(_ action: String, value: String? = nil) {
        guard active, !submitting, let commands = store.cardCommands else { return }
        submitting = true; failure = nil
        _Concurrency.Task { @MainActor in
            defer { submitting = false }
            do { try await commands.respondToCard(card.metadata.id, version: card.metadata.version, response: .init(action: action, value: value)); try await store.refreshMCP() }
            catch { failure = text("Не удалось сохранить. Проверьте актуальное состояние и повторите.", "Couldn't save. Check the current state and try again.") }
        }
    }
    private func saveSecret() {
        guard active, !submitting, let commands = store.cardCommands else { return }
        submitting = true; failure = nil
        let value = secret; secret = ""
        _Concurrency.Task { @MainActor in
            defer { submitting = false }
            do { try await commands.saveCardSecret(card.metadata.id, version: card.metadata.version, secret: value); try await store.refreshMCP() }
            catch { failure = text("Не удалось сохранить ключ. Введите его снова.", "Couldn't save the key. Enter it again.") }
        }
    }
    private func title(_ content: WorkspaceCardContent) -> String {
        switch content {
        case .email: text("Черновик письма", "Email draft")
        case .question(let question): question.prompt
        case .subscription: "Ori"
        case .purchase: text("Покупка", "Purchase")
        case .page: text("Страница", "Page")
        case .command(let command):
            switch action?.toolId {
            case "browser_type": text("Ввести текст на сайте", "Enter text on website")
            case "browser_attach": text("Разрешить управление вкладкой", "Allow control of this tab")
            case "browser_click": text("Подтвердить действие на сайте", "Confirm website action")
            default: command.title
            }
        case .takeover: text("Компьютер", "Computer")
        case .task: text("Результат задачи", "Task result")
        case .slack: text("Сообщение Slack", "Slack message")
        case .connectionRequest: text("Подключение приложения", "Connect app")
        case .plugin: text("Приложение", "App")
        case .credential: text("Защищённый ввод", "Secure input")
        case .cookies: text("Доступ к сайтам", "Website access")
        case .mailFailure: text("Письмо не отправлено", "Email wasn't sent")
        }
    }
    @ViewBuilder private func mailActions(_ draft: WorkspaceCardContent.MailDraft) -> some View {
        primary(text("Отправить", "Send")) {
            guard let raw = try? JSONEncoder().encode(editedMail ?? draft) else { return }
            respond("send", value: String(decoding: raw, as: UTF8.self))
        }
        secondaryButton(text("Удалить черновик", "Discard"), action: "discard")
    }
    @ViewBuilder private func slackActions(_ draft: WorkspaceCardContent.SlackDraft) -> some View {
        primary(text("Отправить сообщение", "Send message")) { respond("send", value: editedSlack ?? draft.body) }
        secondaryButton(text("Удалить", "Discard"), action: "discard")
    }
    @ViewBuilder private func questionActions(_ question: WorkspaceCardContent.Question) -> some View {
        if question.allowsCustomAnswer {
            TextField(text("Введите свой ответ", "Type your own answer"), text: $custom, axis: .vertical).lineLimit(1...6)
                .textFieldStyle(.plain).padding(10).frame(minHeight: minimumHeight)
                .background(field, in: RoundedRectangle(cornerRadius: 14))
                .disabled(!active || submitting).onChange(of: custom) { _, value in if !value.isEmpty { selection = nil } }
        }
        primary(text("Ответить", "Submit")) { respond("submit", value: selection ?? custom.trimmingCharacters(in: .whitespacesAndNewlines)) }
            .fixedSize().disabled((selection ?? custom.trimmingCharacters(in: .whitespacesAndNewlines)).isEmpty)
    }
    private func pluginRow(_ plugin: WorkspaceCardContent.Plugin) -> some View {
        let connection = store.snapshot.mcpConnections.first { $0.metadata.id == plugin.connectionID }
        return Button { store.navigate(.mcp) } label: {
            HStack(spacing: 12) {
                if ["notion", "slack"].contains(plugin.name.lowercased()) {
                    Image(plugin.name.lowercased() == "notion" ? "PluginNotion" : "PluginSlack")
                        .resizable().scaledToFit().frame(width: 32, height: 32).accessibilityHidden(true)
                } else { BlotIcon(symbol: "app.connected.to.app.below.fill").font(.title2).accessibilityHidden(true) }
                VStack(alignment: .leading, spacing: 4) {
                    Text(plugin.name).font(cardFont)
                    if !plugin.detail.isEmpty { Text(plugin.detail).font(secondaryFont).foregroundStyle(.secondary) }
                    if connection?.state != .connected { Text(connectionTitle(connection?.state)).font(.caption2).foregroundStyle(.secondary) }
                }.frame(maxWidth: .infinity, alignment: .leading)
                Text(connection?.state == .connected ? text("Подключено", "Connected") : text("Настроить", "Connect"))
                    .font(secondaryFont).foregroundStyle(.secondary).padding(8)
                    .background(WorkspaceStyle.ink.opacity(0.035), in: Capsule())
            }.contentShape(Rectangle())
        }.buttonStyle(.plain).accessibilityHint(text("Открыть настройки подключения", "Open connection settings"))
    }
    private func connectionTitle(_ state: BlotV3.ConnectionState?) -> String {
        switch state {
        case .connected: text("Подключено", "Connected")
        case .connecting: text("Подключение…", "Connecting…")
        case .expired: text("Войдите снова", "Sign in again")
        case .error: text("Ошибка подключения", "Connection failed")
        case .disconnected, nil: text("Добавлено · требуется подключение", "Added · connection required")
        }
    }
    @ViewBuilder private func commandButtons(_ command: WorkspaceCardContent.Command) -> some View {
        primary(action?.toolId == "browser_type" ? text("Ввести", "Enter text") : text("Разрешить", "Allow")) { respond("allow") }
        if command.ruleScope != nil { secondaryButton(text("Всегда разрешать", "Always allow"), action: "allow_rule") }
        secondaryButton(text("Отклонить", "Deny"), action: "deny")
    }
}
