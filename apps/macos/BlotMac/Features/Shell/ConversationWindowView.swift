import Foundation
import BlotDesign
import SwiftUI

struct ConversationWindowRequest: Codable, Hashable {
    let id: String
    let title: String
    let transcript: String
    var chatID: String?
}

struct ConversationWindowView: View {
    @Environment(AppState.self) private var app
    let request: ConversationWindowRequest
    private var exportedText: String {
        if let id = request.chatID, let session = app.workChat.session(id) {
            return app.transcript(for: SidebarConversation(id: "chat:" + id, title: session.title,
                project: session.projectID ?? "", taskID: id, running: false, kind: .chat))
        }
        return request.transcript
    }

    var body: some View {
        VStack(alignment: .leading, spacing: KSpace.lg) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(request.title).font(KFont.sheetTitle()).foregroundStyle(K.text).lineLimit(2)
                    if request.chatID == nil {
                        Text("Snapshot · read-only").font(KFont.caption()).foregroundStyle(K.text3)
                    }
                }
                Spacer()
                CopyButton(text: exportedText, title: "Copy conversation")
            }
            if let id = request.chatID, let session = app.workChat.session(id) {
                SideChatContent(session: session)
            } else {
                ScrollView {
                    Text(request.transcript).font(KFont.body()).foregroundStyle(K.text).lineSpacing(4)
                        .textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }.padding(KSpace.xl).frame(minWidth: 560, minHeight: 480).background(K.bg)
            .blotTheme(app.theme).tint(K.inverse)
            .navigationTitle(request.title)
    }
}

private struct SideChatContent: View {
    @Bindable var session: WorkChatSession

    var body: some View {
        VStack(spacing: 16) {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    ForEach(session.messages) { message in
                        if message.fromUser { UserBubble(text: message.text) }
                        else {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("Blot").font(KFont.label()).foregroundStyle(K.text3)
                                AgentText(text: message.text)
                            }
                        }
                    }
                    if session.isSending {
                        HStack(spacing: KSpace.sm) {
                            TypingDots()
                            Text("Blot is writing…").font(KFont.ui(13)).foregroundStyle(K.text3)
                        }
                    }
                }
            }.defaultScrollAnchor(.bottom)
            Composer(text: $session.draft, placeholder: "Message in side chat", sending: session.isSending,
                     showsModel: false, status: session.error, statusTone: .error,
                     onStop: session.isSending ? { session.cancel() } : nil) {
                let text = session.draft.trimmingCharacters(in: .whitespacesAndNewlines)
                if !text.isEmpty { session.send(text) }
            }
        }
    }
}
