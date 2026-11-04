import BlotDesign
import SwiftUI

struct MacTeamEmailReview: View {
    @Environment(MacTeamPresentation.self) private var presentation
    @Environment(\.dismiss) private var dismiss
    @State private var bodyText = ""
    @State private var subject = ""
    var body: some View {
        VStack(spacing: 0) {
            MacTeamSheetHeader(
                title: presentation.pendingEmail?.sent == true ? "Демо-письмо отправлено" : "Проверка письма")
            Divider()
            if let email = presentation.pendingEmail {
                VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        Text("Кому").foregroundStyle(.secondary).frame(width: 45, alignment: .leading)
                        Text(email.sender + " · " + email.address)
                        Spacer()
                    }
                    Text(email.accountLabel).font(.system(size: 11)).foregroundStyle(.secondary)
                    TextField("Тема письма", text: $subject).disabled(email.sent)
                    Text(email.incoming).font(.system(size: 11)).foregroundStyle(.secondary).lineSpacing(4)
                    Divider()
                    TextEditor(text: $bodyText).font(.system(size: 14)).lineSpacing(6).scrollContentBackground(.hidden)
                        .frame(height: 240).disabled(email.sent)
                    BlotLabel(
                        presentation.canSendEmail
                            ? "Демо-отправка меняет только локальную переписку."
                            : "Отправка отключена в разрешениях демо-аккаунта.", symbol: "checkmark.shield"
                    , size: BlotIconSize.inline).font(
                        .system(size: 11)
                    ).foregroundStyle(.secondary)
                }.font(.system(size: 12)).padding(24)
                Divider()
                HStack {
                    Button(email.sent ? "Закрыть" : "Сохранить черновик") {
                        if !email.sent { presentation.demo.saveEmailDraft(email.id, subject: subject, reply: bodyText) }
                        dismiss()
                    }.buttonStyle(WorkspaceButtonStyle(.secondary))
                    Spacer()
                    if !email.sent {
                        Button("Отправить в демо") {
                            presentation.demo.sendEmail(
                                email.id, subject: subject, reply: bodyText, conversation: presentation.conversationKey)
                            dismiss()
                        }.buttonStyle(WorkspaceButtonStyle()).disabled(
                            !presentation.canSendEmail
                                || bodyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }.padding(18)
            }
        }.frame(width: 650)
            .onAppear {
                subject = presentation.pendingEmail?.subject ?? ""
                bodyText = presentation.pendingEmail?.reply ?? ""
            }
    }
}

struct MacTeamTransactionReview: View {
    @Environment(MacTeamPresentation.self) private var presentation
    @Environment(\.dismiss) private var dismiss
    @State private var transactions: [MacDemoTransaction] = []
    @State private var saveRule = true
    var body: some View {
        VStack(spacing: 0) {
            MacTeamSheetHeader(title: "Проверка операций")
            Divider()
            VStack(alignment: .leading, spacing: 18) {
                Text("Категории сохранятся в демо-реестре QuickBooks.").foregroundStyle(.secondary)
                ForEach($transactions) { $item in
                    VStack(spacing: 12) {
                        HStack {
                            TextField("Контрагент", text: $item.vendor)
                            Text(item.amount, format: .currency(code: "USD")).monospacedDigit()
                        }
                        MacTeamSelect(
                            title: "Категория", selection: $item.category,
                            values: ["Коммунальные услуги", "Упаковка", "Продукты", "Прочие расходы"])
                    }.teamCard()
                }
                Toggle("Сохранить правило для похожих операций", isOn: $saveRule).toggleStyle(MacTeamCheckboxStyle())
            }.font(.system(size: 12)).padding(24)
            Divider()
            HStack {
                Button("Отмена") { dismiss() }.buttonStyle(WorkspaceButtonStyle(.secondary))
                Spacer()
                Button("Согласовать категории") {
                    let thread = presentation.conversationKey
                    presentation.demo.update { state in
                        state.transactions = transactions.map {
                            var row = $0
                            row.approved = true
                            return row
                        }
                        if saveRule && !state.memories.contains(where: { $0.id == "expense-rule" }) {
                            state.memories.append(
                                .init(
                                    id: "expense-rule",
                                    text: "Используй согласованные категории расходов для похожих операций",
                                    agentID: "finance"))
                        }
                        state.threads[thread, default: []].append(
                            .init(
                                authorID: "finance",
                                text: "Три операции согласованы. Категории сохранены в демо-реестре.",
                                kind: .transactions))
                    }
                    dismiss()
                }.buttonStyle(WorkspaceButtonStyle()).disabled(transactions.contains { $0.vendor.isEmpty })
            }.padding(18)
        }.frame(width: 630).onAppear { transactions = presentation.demo.state.transactions }
    }
}

struct MacTeamAttachmentPicker: View {
    @Environment(MacTeamPresentation.self) private var presentation
    @Environment(\.dismiss) private var dismiss
    @State private var selected = "sop"
    private var document: MacDemoDocument? { presentation.demo.state.documents.first { $0.id == selected } }
    var body: some View {
        VStack(spacing: 0) {
            MacTeamSheetHeader(title: "Файлы пространства")
            Divider()
            HStack(spacing: 0) {
                ScrollView {
                    VStack(spacing: 4) {
                        ForEach(presentation.demo.state.documents) { document in
                            MacTeamNavigationButton(selected: selected == document.id) {
                                selected = document.id
                            } label: {
                                HStack(spacing: 8) {
                                    MacTeamFileIcon(filename: document.title, size: 24)
                                    Text(document.title).font(.system(size: 12)).lineLimit(2)
                                }
                            }
                        }
                    }.padding(10)
                }.frame(width: 240).background(MacTeamStyle.sidebar)
                Divider()
                ScrollView {
                    if let document {
                        VStack(alignment: .leading, spacing: 18) {
                            HStack(spacing: 10) {
                                MacTeamFileIcon(filename: document.title)
                                Text(document.title).font(.system(size: 19, weight: .medium))
                            }
                            Text(document.body).font(.system(size: 13)).lineSpacing(6).textSelection(.enabled)
                        }.padding(24).frame(maxWidth: .infinity, alignment: .leading)
                    }
                }.frame(maxWidth: .infinity)
            }.frame(height: 370)
            Divider()
            HStack {
                Button("Открыть документ") {
                    presentation.selectedDocumentID = selected
                    presentation.sheet = .document
                }.buttonStyle(WorkspaceButtonStyle(.secondary)).disabled(document == nil)
                Spacer()
                Button("Прикрепить к сообщению") {
                    if !presentation.attachedDocumentIDs.contains(selected) {
                        presentation.attachedDocumentIDs.append(selected)
                    }
                    dismiss()
                }.buttonStyle(WorkspaceButtonStyle()).disabled(document == nil)
            }.padding(18)
        }.frame(width: 760)
            .onAppear { if document == nil { selected = presentation.demo.state.documents.first?.id ?? "" } }
    }
}
