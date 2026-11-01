import BlotDesign
import SwiftUI

/// Blot Work: a conversation with Blot or one of the user's GPTs, stored on the Blot server.
struct WorkChatView: View {
    @Environment(AppState.self) private var app

    var body: some View {
        @Bindable var app = app
        VStack(spacing: 0) {
            if let chat = app.currentWorkChat {
                ScrollView {
                    ContentColumn {
                        LazyVStack(alignment: .leading, spacing: KSpace.xl) {
                            if let assistant = chat.assistant {
                                VStack(alignment: .leading, spacing: KSpace.md) {
                                    Text(assistant.name).font(KFont.pageTitle()).foregroundStyle(K.text)
                                    KDisclosure("Инструкции") {
                                        Text(assistant.instructions).font(KFont.ui(13)).foregroundStyle(K.text2).lineSpacing(3)
                                            .frame(maxWidth: .infinity, alignment: .leading).textSelection(.enabled)
                                    }
                                }
                            }
                            if chat.messages.isEmpty && !chat.isSending {
                                EmptyState(icon: "message-square", title: "Начните разговор",
                                           detail: "Напишите Blot в поле ниже.")
                            }
                            ForEach(chat.visibleMessages) { message in
                                Group {
                                    if message.fromUser { UserBubble(text: message.text) }
                                    else {
                                        VStack(alignment: .leading, spacing: 6) {
                                            Text(chat.assistant?.name ?? "Blot").font(KFont.label()).foregroundStyle(K.text3)
                                            AgentText(text: message.text)
                                        }
                                    }
                                }
                                .transition(.kAppear)
                            }
                            if chat.isSending {
                                HStack(spacing: KSpace.sm) {
                                    TypingDots()
                                    Text("\(chat.assistant?.name ?? "Blot") пишет…").font(KFont.ui(13)).foregroundStyle(K.text3)
                                }
                                .transition(.opacity)
                            }
                            if let error = chat.error {
                                HStack(spacing: KSpace.md) {
                                    InlineFeedback(text: error, tone: .error).textSelection(.enabled)
                                    if chat.canRetry && !chat.isSending {
                                        KButton(title: "Продолжить ответ", icon: "rotate-ccw", height: 28) { chat.retry() }
                                    }
                                }
                                .transition(.kAppear)
                            }
                        }
                        .padding(.vertical, KSpace.xl)
                        .kAnimation(value: chat.messages.count)
                        .kAnimation(value: chat.isSending)
                    }
                }.defaultScrollAnchor(.bottom)
            } else if let project = app.workChat.selectedProject {
                ProjectOverview(project: project)
            } else {
                StartConversationView()
            }
            if app.currentWorkChat != nil || app.workChat.selectedProject != nil {
                Composer(text: $app.workChatDraft, placeholder: "Напишите Blot…",
                         petContext: app.currentWorkChat == nil ? nil : app.activeBlotContext,
                         sending: app.currentWorkChat?.isSending ?? false,
                         onStop: app.currentWorkChat?.isSending == true ? { app.currentWorkChat?.cancel() } : nil,
                         onSend: { app.sendWorkChatMessage() })
                    .composerPlacement(hasPet: app.currentWorkChat != nil)
            }
        }.id(app.currentWorkChat?.id ?? app.workChat.selectedProjectID ?? "new-work-chat")
    }
}
