//
//  Composer.swift
//  BlotMac
//
//  Composer: one flat card (panel fill, hairline border, 10 pt corners) with an optional
//  context line at the top, a multi-line input and a compact toolbar. The toolbar only shows controls that do something: the approval chip
//  and the model chip open their settings pages, the send button shows progress while a message
//  is on its way, and Stop appears while the agent is working.
//

import BlotDesign
import SwiftUI

struct Composer<Context: View, Tools: View>: View {
    @Environment(AppState.self) private var app
    @Binding var text: String
    var placeholder: String
    var petContext: BlotContext?
    var canSend: Bool
    var sending: Bool
    var showsApproval: Bool
    var showsModel: Bool
    var status: String?
    var statusTone: InlineFeedback.Tone
    var onStop: (() -> Void)?
    var onSend: () -> Void
    @ViewBuilder var context: () -> Context
    @ViewBuilder var tools: () -> Tools

    @FocusState private var focused: Bool

    init(text: Binding<String>, placeholder: String, petContext: BlotContext? = nil, canSend: Bool = true,
         sending: Bool = false, showsApproval: Bool = false, showsModel: Bool = true, status: String? = nil,
         statusTone: InlineFeedback.Tone = .information, onStop: (() -> Void)? = nil,
         onSend: @escaping () -> Void, @ViewBuilder context: @escaping () -> Context,
         @ViewBuilder tools: @escaping () -> Tools) {
        _text = text
        self.placeholder = placeholder
        self.petContext = petContext
        self.canSend = canSend
        self.sending = sending
        self.showsApproval = showsApproval
        self.showsModel = showsModel
        self.status = status
        self.statusTone = statusTone
        self.onStop = onStop
        self.onSend = onSend
        self.context = context
        self.tools = tools
    }

    var body: some View {
        VStack(alignment: .leading, spacing: KSpace.sm) {
            if let status {
                InlineFeedback(text: status, tone: statusTone).padding(.horizontal, KSpace.md)
                    .transition(.kAppear)
            }
            input
        }
        .kAnimation(value: status)
        .onChange(of: text) { _, _ in
            if !text.isEmpty, let petContext { app.pokeBlot(.typing, context: petContext) }
        }
        .overlay(alignment: .topTrailing) {
            if let petContext { ComposerBlot(context: petContext).offset(x: -24, y: -43) }
        }
    }

    private var input: some View {
        VStack(spacing: 0) {
            if Context.self != EmptyView.self {
                // Context is its own line inside the card, separated by a hairline.
                HStack(spacing: KSpace.element) {
                    context()
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, KSpace.sm)
                .frame(minHeight: K.composerContextHeight)
                .kBorder(.bottom)
            }
            TextField("", text: $text, prompt: Text(placeholder).foregroundColor(K.disabled), axis: .vertical)
                .textFieldStyle(.plain)
                .font(KFont.body())
                .foregroundStyle(K.text)
                .lineLimit(1...8)
                .lineSpacing(4)
                .focused($focused)
                .accessibilityLabel(placeholder)
                .accessibilityHint(canSend ? "Return — отправить" : status ?? "Отправка недоступна")
                .onSubmit(send)
                .frame(minHeight: 44, alignment: .topLeading)
                .padding(EdgeInsets(top: 14, leading: 16, bottom: 0, trailing: 16))

            HStack(spacing: 4) {
                tools()
                if showsApproval {
                    Button { app.openProfileSettings(.permissions) } label: {
                        Chip(icon: "checkmark.shield", label: "С подтверждением", chevron: false)
                    }
                    .buttonStyle(KIconButtonStyle()).kFocusRing(radius: K.rMd)
                    .help("Every command, file change, commit and push waits for your approval. Open Permissions.")
                }
                Spacer(minLength: 0)
                if showsModel {
                    Button { app.openProfileSettings(.models) } label: {
                        Chip(icon: nil, label: app.settings.model.isEmpty ? "Модель" : app.settings.model, chevron: false)
                    }
                    .buttonStyle(KIconButtonStyle()).kFocusRing(radius: K.rMd)
                    .help("Model and token limits are set in Settings › Models.")
                }
                if let onStop {
                    IconButton(icon: "stop", help: "Остановить", action: onStop)
                        .transition(.opacity)
                }
                SendButton(enabled: canSend && !trimmed.isEmpty, sending: sending, action: send).padding(.leading, 4)
            }
            .padding(EdgeInsets(top: 4, leading: 8, bottom: 12, trailing: 10))
            .kAnimation(KMotion.quick, value: onStop == nil)
        }
        .frame(minHeight: K.composerHeight, alignment: .top)
        .background(K.composer, in: RoundedRectangle(cornerRadius: K.composerRadius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: K.composerRadius, style: .continuous)
            .strokeBorder(focused ? K.focus : K.borderStrong, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: K.composerRadius, style: .continuous))
        .contentShape(Rectangle())
        .onTapGesture { focused = true }
        .kAnimation(KMotion.quick, value: focused)
    }

    private var trimmed: String { text.trimmingCharacters(in: .whitespacesAndNewlines) }

    private func send() {
        guard canSend, !sending, !trimmed.isEmpty else { return }
        onSend()
    }
}

extension Composer where Context == EmptyView, Tools == EmptyView {
    init(text: Binding<String>, placeholder: String, petContext: BlotContext? = nil, canSend: Bool = true,
         sending: Bool = false, showsApproval: Bool = false, showsModel: Bool = true, status: String? = nil,
         statusTone: InlineFeedback.Tone = .information, onStop: (() -> Void)? = nil,
         onSend: @escaping () -> Void) {
        self.init(text: text, placeholder: placeholder, petContext: petContext, canSend: canSend, sending: sending,
                  showsApproval: showsApproval, showsModel: showsModel, status: status, statusTone: statusTone,
                  onStop: onStop, onSend: onSend, context: { EmptyView() }, tools: { EmptyView() })
    }
}

extension Composer where Tools == EmptyView {
    init(text: Binding<String>, placeholder: String, petContext: BlotContext? = nil, canSend: Bool = true,
         sending: Bool = false, showsApproval: Bool = false, showsModel: Bool = true, status: String? = nil,
         statusTone: InlineFeedback.Tone = .information, onStop: (() -> Void)? = nil,
         onSend: @escaping () -> Void, @ViewBuilder context: @escaping () -> Context) {
        self.init(text: text, placeholder: placeholder, petContext: petContext, canSend: canSend, sending: sending,
                  showsApproval: showsApproval, showsModel: showsModel, status: status, statusTone: statusTone,
                  onStop: onStop, onSend: onSend, context: context, tools: { EmptyView() })
    }
}
