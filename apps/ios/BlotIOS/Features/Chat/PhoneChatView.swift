import BlotAPI
import BlotDesign
import SwiftUI

struct PhoneChatView: View {
    let client: BackendClient
    let conversation: UUID
    var title = "Conversation"
    @State private var messages: [BackendEntity<Message>] = []
    @State private var text = ""
    @State private var loadError: String?
    @State private var sendError: String?
    @State private var loading = true
    @State private var pending: UUID?
    @State private var pendingContent: String?
    @State private var sending = false
    @State private var reactions = BlotReactionController()
    @FocusState private var composing: Bool
    nonisolated private struct Message: Codable, Sendable { let role: String; let content: String; let ordinal: Int64 }
    nonisolated private struct Send: Encodable, Sendable { let conversationId: UUID; let content: String }

    var body: some View {
        ScrollViewReader { proxy in
            List {
                if loading && messages.isEmpty {
                    BlotLoadingState("Loading conversation…")
                        .listRowSeparator(.hidden).listRowBackground(Color.clear)
                }
                if let loadError {
                    BlotErrorState(loadError) { Task { await refresh() } }
                        .listRowSeparator(.hidden).listRowBackground(Color.clear)
                } else if !loading && messages.isEmpty {
                    BlotEmptyState(symbol: "bubble.left.and.bubble.right", title: "Start a conversation",
                                   message: "Send a message to Blot using the field below.")
                        .listRowSeparator(.hidden).listRowBackground(Color.clear)
                }
                ForEach(messages.sorted { $0.data.ordinal < $1.data.ordinal }, id: \.id) { row in
                    PhoneMessageRow(role: row.data.role, content: row.data.content)
                        .id(row.id)
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets(top: BlotSpace.element, leading: BlotSpace.panel,
                                                  bottom: BlotSpace.element, trailing: BlotSpace.panel))
                }
            }
            .phonePlainList()
            .scrollDismissesKeyboard(.interactively)
            .defaultScrollAnchor(.bottom)
            .onChange(of: sending) { _, value in
                if !value, sendError == nil, let last = messages.max(by: { $0.data.ordinal < $1.data.ordinal }) {
                    proxy.scrollTo(last.id, anchor: .bottom)
                }
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) { composer }
        .navigationTitle(title.isEmpty ? "Conversation" : title)
        .task(id: conversation) {
            while !Task.isCancelled {
                await refresh()
                try? await Task.sleep(for: .seconds(1))
            }
        }
        .onDisappear { reactions.cancel() }
    }

    private var composer: some View {
        VStack(alignment: .leading, spacing: BlotSpace.element) {
            PhoneComposerBlot(reactions: reactions)
                .padding(.leading, BlotSpace.s10)
            if let sendError { PhoneErrorText(sendError) }
            HStack(alignment: .bottom, spacing: BlotSpace.s8) {
                TextField("Message Blot", text: $text, axis: .vertical)
                    .blotFont(.body)
                    .foregroundStyle(BlotColor.text)
                    .lineLimit(1...6)
                    .padding(.horizontal, BlotSpace.s12)
                    .padding(.vertical, BlotSpace.s10)
                    .frame(minHeight: BlotLayout.minimumTapTarget)
                    .focused($composing)
                    .disabled(sending || pending != nil)
                    .accessibilityLabel("Message Blot")
                BlotSendButton(phase: sending ? .sending : pending == nil ? .ready : .retry,
                               size: BlotLayout.minimumTapTarget - 8, action: send)
                    .frame(width: BlotLayout.minimumTapTarget, height: BlotLayout.minimumTapTarget)
                    .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && pending == nil)
            }
            .padding(.trailing, BlotSpace.element)
            .blotPanel(fill: BlotColor.panel, border: composing ? BlotColor.focusRing : BlotColor.hairlineStrong)
            .contentShape(Rectangle())
            .onTapGesture { composing = true }
        }
        .padding(.horizontal, BlotSpace.panel)
        .padding(.top, BlotSpace.element)
        .padding(.bottom, BlotSpace.s10)
        .background(BlotColor.canvas)
        .onChange(of: text) { _, value in
            if !value.isEmpty { reactions.receive(.typing) }
        }
    }

    private func refresh() async {
        defer { loading = false }
        do {
            let records = try await client.records("MESSAGE", parentId: conversation, as: Message.self)
            guard !Task.isCancelled else { return }
            messages = records
            loadError = nil
        } catch is CancellationError { }
        catch { loadError = error.localizedDescription }
    }

    private func send() {
        guard !sending else { return }
        let id = pending ?? UUID()
        pending = id
        let content = pendingContent ?? text
        pendingContent = content
        sending = true
        reactions.receive(.sent)
        Task {
            defer { sending = false }
            do {
                _ = try await client.command("conversation.send_message", payload: Send(conversationId: conversation, content: content), commandId: id)
                pending = nil; pendingContent = nil; text = ""; sendError = nil
                await refresh()
            } catch let failure as BackendFailure {
                if failure.isDefiniteRejection { pending = nil; pendingContent = nil }
                sendError = failure.localizedDescription
                reactions.receive(.sendFailed)
            } catch {
                sendError = error.localizedDescription
                reactions.receive(.sendFailed)
            }
        }
    }
}

/// 40 pt Blot above the composer. Reacts to typing, sending and a failed send; idles otherwise.
private struct PhoneComposerBlot: View {
    let reactions: BlotReactionController
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        BlotCharacterView(state: reactions.state(over: .idle), size: BlotLayout.phoneCharacterSize,
                          replay: reactions.generation, behavior: .subtle, reduceMotion: reduceMotion)
            .accessibilityHidden(true)
            .task(id: reactions.generation) {
                // Typing extends the current reaction, so wait until it has really run out.
                while let remaining = reactions.remaining {
                    do { try await Task.sleep(for: .seconds(remaining + 0.05)) } catch { return }
                    reactions.expire()
                }
            }
    }
}

private struct PhoneMessageRow: View {
    let role: String
    let content: String

    private var isUser: Bool { role.uppercased() == "USER" }
    private var author: String {
        switch role.uppercased() {
        case "USER": "You"
        case "ASSISTANT": "Blot"
        case "SYSTEM": "System"
        case "TOOL": "Tool"
        default: phoneStatusLabel(role)
        }
    }

    var body: some View {
        Group {
            if isUser {
                HStack {
                    Spacer(minLength: 48)
                    Text(content)
                        .blotFont(.body)
                        .foregroundStyle(BlotColor.text)
                        .padding(.horizontal, BlotSpace.panel)
                        .padding(.vertical, BlotSpace.s10)
                        .background(RoundedRectangle(cornerRadius: BlotRadius.control, style: .continuous).fill(BlotColor.fill))
                        .textSelection(.enabled)
                }
            } else {
                VStack(alignment: .leading, spacing: BlotSpace.element) {
                    Text(author).blotFont(.caption, weight: .medium).foregroundStyle(BlotColor.textSecondary)
                    Text(content).blotFont(.body).foregroundStyle(BlotColor.text)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(author): \(content)")
    }
}
