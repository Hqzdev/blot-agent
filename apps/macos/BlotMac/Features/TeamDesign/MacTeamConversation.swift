import BlotDesign
import SwiftUI

struct MacTeamConversation: View {
    @Environment(MacTeamPresentation.self) private var presentation
    @Environment(\.blotReduceMotion) private var reduceMotion
    @AppStorage(MacTeamPreferenceKey.compactMessages) private var compactMessages = false
    @State private var timeline: MacTeamMessageTimeline
    @State private var inputFrame: CGRect?
    @State private var sendInputFrame: CGRect?
    @State private var followsLatest = true
    @State private var nearBottom = true
    @State private var scrollPosition = ScrollPosition(edge: .bottom)

    init(initialMessages: [MacDemoMessage]) {
        _timeline = State(initialValue: MacTeamMessageTimeline(messages: initialMessages))
    }

    private var visibleMessages: [MacDemoMessage] {
        presentation.messages.filter { timeline.visibleIDs.contains($0.id) }
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: compactMessages ? 16 : 24) {
                Text("Демо-переписка · сохраняется на этом Mac")
                    .font(.system(size: 10)).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity).padding(.top, 20)
                ForEach(visibleMessages) { message in
                    MacTeamMessageView(
                        message: message, arriving: timeline.entranceIDs.contains(message.id), inputFrame: sendInputFrame ?? inputFrame,
                        compact: compactMessages
                    ).id(message.id).transition(.identity)
                        .onAppear { timeline.didAppear(message.id) }
                }
            }.frame(maxWidth: 680, alignment: .leading).padding(.horizontal, 28).padding(.bottom, 24)
                .frame(maxWidth: .infinity)
                .kAnimation(MacTeamMessageMotion.receive, value: timeline.visibleIDs)
        }
        .defaultScrollAnchor(.bottom)
        .scrollPosition($scrollPosition)
        .onScrollGeometryChange(for: Bool.self) { geometry in
            geometry.visibleRect.maxY >= geometry.contentSize.height - 72
        } action: { _, value in nearBottom = value }
        .onScrollPhaseChange { old, phase in
            if phase == .interacting || phase == .decelerating || (phase == .idle && old != .animating) {
                followsLatest = nearBottom
            }
        }
        .overlay {
            GeometryReader { geometry in
                MacTeamPointerInput(viewportInsets: geometry.safeAreaInsets)
                    .frame(maxWidth: .infinity, maxHeight: .infinity).allowsHitTesting(false)
            }.allowsHitTesting(false)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            MacTeamComposer(onInputFrameChange: { inputFrame = $0 }, onSend: {
                sendInputFrame = inputFrame
                presentation.sendDraft()
            })
                .frame(maxWidth: 730).padding(.horizontal, 24).padding(.bottom, 18).padding(.top, 8)
                .frame(maxWidth: .infinity).background(WorkspaceStyle.canvas)
        }
        .onChange(of: presentation.messageScrollTarget) { _, target in
            guard let target else { return }
            followsLatest = false
            withKAnimation(reduceMotion, KMotion.standard) { scrollPosition.scrollTo(id: target, anchor: .center) }
            presentation.messageScrollTarget = nil
        }
        .onChange(of: timeline.lastRevealedID) { _, _ in
            guard followsLatest else { return }
            let outgoing = presentation.messages.first { $0.id == timeline.lastRevealedID }?.isUser == true
            withKAnimation(reduceMotion, outgoing ? MacTeamMessageMotion.send : MacTeamMessageMotion.receive) {
                scrollPosition.scrollTo(edge: .bottom)
            }
        }
        .task(id: MessageUpdate(ids: presentation.messages.map(\.id), reduceMotion: reduceMotion)) {
            let sent = timeline.synchronize(
                presentation.messages, immediate: reduceMotion, followingLatest: followsLatest)
            if sent { followsLatest = true }
            do {
                if sent && !reduceMotion { try await Task.sleep(for: MacTeamMessageMotion.sendLead) }
                while !Task.isCancelled && timeline.revealNext() {
                    try await Task.sleep(for: MacTeamMessageMotion.replySpacing)
                }
            } catch is CancellationError {
                // The next update resumes pending messages; navigating away discards only UI staging.
            } catch { assertionFailure("Unexpected message animation delay error: \(error)") }
        }
        .coordinateSpace(name: MacTeamMessageMotion.coordinateSpace)
    }

    private struct MessageUpdate: Equatable {
        let ids: [String]
        let reduceMotion: Bool
    }
}
