import BlotDesign
import SwiftUI

struct MacTeamComposer: View {
    let onInputFrameChange: (CGRect) -> Void
    let onSend: () -> Void
    @Environment(MacTeamPresentation.self) private var presentation
    @FocusState private var focused: Bool
    @State private var attachmentsExpanded = false
    @AppStorage(MacTeamPreferenceKey.sendOnReturn) private var sendOnReturn = true
    @AppStorage(MacTeamPreferenceKey.composerHints) private var composerHints = true
    private var canSend: Bool { !presentation.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    private var showsSkills: Bool { presentation.draft.hasPrefix("/") && !presentation.selectedSkill }
    var body: some View {
        @Bindable var presentation = presentation
        VStack(alignment: .leading, spacing: 8) {
            if let original = presentation.replyingTo {
                HStack(spacing: 12) {
                    MacTeamReplyQuote(message: original)
                    Spacer(minLength: 0)
                    MacTeamIconButton(title: "Отменить ответ", symbol: "xmark") { presentation.replyToID = nil }
                }.padding(.horizontal, 16).padding(.vertical, 10)
                    .background(WorkspaceStyle.surface.opacity(0.6), in: RoundedRectangle(cornerRadius: 16))
                    .transition(.kAppear)
            }
            if showsSkills {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Навыки агента").font(.system(size: 10)).foregroundStyle(.secondary).padding(8)
                    ForEach(
                        presentation.relevantSkills.filter {
                            presentation.draft.count <= 1
                                || $0.title.localizedCaseInsensitiveContains(String(presentation.draft.dropFirst()))
                        }
                    ) { skill in
                        Button {
                            presentation.draft = "/" + skill.title
                            presentation.selectedSkill = true
                            focused = true
                        } label: {
                            HStack {
                                BlotIcon(symbol: "shippingbox", size: BlotIconSize.control).foregroundStyle(WorkspaceStyle.ink)
                                Text(skill.title)
                                Spacer()
                                BlotIcon(symbol: "return", size: BlotIconSize.inline).foregroundStyle(WorkspaceStyle.ink)
                            }.padding(8).contentShape(Rectangle())
                        }.buttonStyle(BlotPlainButtonStyle())
                    }
                }.font(.system(size: 12)).teamCard(padding: 5).shadow(color: .black.opacity(0.05), radius: 10, y: 2)
                    .transition(.kAppear)
            }
            ForEach(presentation.attachedDocumentIDs, id: \.self) { id in
                if let document = presentation.demo.state.documents.first(where: { $0.id == id }) {
                    HStack(spacing: 8) {
                        MacTeamFileIcon(filename: document.title, size: 20)
                        Text(document.title).font(.system(size: 11))
                        MacTeamIconButton(title: "Убрать файл", symbol: "xmark.circle.fill") {
                            presentation.attachedDocumentIDs.removeAll { $0 == id }
                        }
                    }.padding(.horizontal, 10).background(WorkspaceStyle.surface, in: RoundedRectangle(cornerRadius: 8))
                }
            }
            HStack(alignment: .bottom, spacing: 8) {
                Button { attachmentsExpanded.toggle() } label: {
                    BlotIcon(.plus, size: BlotIconSize.navigation)
                        .foregroundStyle(WorkspaceStyle.ink).frame(width: 31, height: 31)
                        .contentShape(Circle())
                }
                .buttonStyle(BlotPlainButtonStyle()).help("Добавить").accessibilityLabel("Добавить")
                .popover(isPresented: $attachmentsExpanded, arrowEdge: .top) { attachmentActions }
                TextField(
                    "Сообщение \(presentation.group != nil ? "команде" : presentation.agent.name)…",
                    text: $presentation.draft, axis: .vertical
                )
                .textFieldStyle(.plain).lineLimit(1...5).padding(.vertical, 7).frame(minHeight: 31).focused($focused)
                .onSubmit {
                    if sendOnReturn { if canSend { onSend() } }
                    else { presentation.draft += "\n" }
                }
                .onKeyPress(.return, phases: .down) { event in
                    guard event.modifiers.contains(.command) else { return .ignored }
                    if canSend { onSend() }
                    return .handled
                }
                .accessibilityLabel("Сообщение агенту")
                .onGeometryChange(for: CGRect.self) {
                    $0.frame(in: .named(MacTeamMessageMotion.coordinateSpace))
                } action: { onInputFrameChange($0) }
                Button(action: onSend) {
                    BlotIcon(.arrowUp, size: BlotIconSize.control)
                        .foregroundStyle(Color.white)
                        .frame(width: 31, height: 31).background(Color.black, in: Circle())
                        .contentShape(Circle())
                }
                .buttonStyle(BlotPlainButtonStyle(disabledOpacity: 1))
                .disabled(!canSend).help("Отправить").accessibilityLabel("Отправить")
            }.padding(9).background(WorkspaceStyle.canvas, in: RoundedRectangle(cornerRadius: 24))
                .overlay(RoundedRectangle(cornerRadius: 24).strokeBorder(BlotColor.edge))
                .shadow(color: .black.opacity(0.035), radius: 8, y: 2)
            if composerHints {
                Text("/ для навыков · прикрепите файл или задайте расписание сообщением")
                    .font(.system(size: 10)).foregroundStyle(.tertiary).padding(.horizontal, 14)
            }
        }
        .kAnimation(KMotion.standard, value: composerHints)
        .kAnimation(KMotion.standard, value: presentation.replyToID)
        .kAnimation(KMotion.standard, value: showsSkills)
        .kAnimation(KMotion.standard, value: presentation.attachedDocumentIDs)
        .onChange(of: presentation.composerFocusRequest) { _, _ in focused = true }
    }

    private var attachmentActions: some View {
        VStack(spacing: 3) {
            attachmentAction("Прикрепить файл", symbol: "paperclip") { presentation.sheet = .attachment }
            attachmentAction("Использовать навык", symbol: "shippingbox") {
                presentation.draft = "/"
                presentation.selectedSkill = false
                focused = true
            }
            attachmentAction("Подключить приложение", symbol: "puzzlepiece.extension") {
                presentation.open(.library(.marketplace))
            }
            Divider()
            attachmentAction("Новый навык", symbol: "plus") { presentation.editSkill() }
        }.padding(6).frame(width: 250).background(MacTeamStyle.panel)
    }

    private func attachmentAction(_ title: String, symbol: String, action: @escaping () -> Void) -> some View {
        MacTeamNavigationButton {
            attachmentsExpanded = false
            action()
        } label: {
            BlotLabel(title, symbol: symbol, size: BlotIconSize.control).font(.system(size: 12))
        }
    }
}
