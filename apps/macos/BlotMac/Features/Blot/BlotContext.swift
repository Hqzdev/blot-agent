import BlotAPI
import BlotDesign
import SwiftUI

enum BlotContext: Hashable {
    case home, workHome, workChat(String), newRun, task(String), run(String), gallery
}

extension AppState {
    var activeBlotContext: BlotContext {
        if product == .work {
            if case let .chat(id) = workRoute { return .workChat(id) }
            return workRoute == .blot ? .gallery : .workHome
        }
        if isMotes { return teamRoute == .newRun ? .newRun : .run(selectedRunID) }
        switch codeRoute {
        case let .task(project, task): return .task(project + ":" + task)
        case .blot: return .gallery
        default: return .home
        }
    }
    var activeBlotState: BlotState {
        if product == .work { return .idle }
        if !isMotes {
            guard let task = currentTask else { return .idle }
            if task.thread.contains(where: { if case .approval = $0 { return true }; return false }) { return .waiting }
            return task.isRunning ? .working : .idle
        }
        if teamRoute == .newRun { return .idle }
        guard currentWorkSession?.status == .running else { return .idle }
        if workspace.rows("PREPARED_ACTION").contains(where: { $0.data.text("status") == "PREPARED" && team.contains { $0.state == .blocked } }) { return .waiting }
        if !team.isEmpty && team.allSatisfy({ $0.state == .blocked || $0.state == .idle }) && team.contains(where: { $0.state == .blocked }) { return .blocked }
        if team.allSatisfy({ $0.state == .idle || $0.state == .done }) { return .idle }
        return team.contains(where: { $0.stateLabel.contains("planning") }) ? .thinking : .working
    }
}

/// A stimulus addressed to the character on one screen.
struct BlotStimulus: Equatable {
    var kind: BlotStimulusKind = .none
    var id = 0
    var context: BlotContext = .home
    var createdAt = Date()
}

private struct BlotNamespaceKey: EnvironmentKey { static let defaultValue: Namespace.ID? = nil }
extension EnvironmentValues {
    var blotNamespace: Namespace.ID? {
        get { self[BlotNamespaceKey.self] }
        set { self[BlotNamespaceKey.self] = newValue }
    }
}

struct ComposerBlot: View {
    @Environment(AppState.self) private var app
    @Environment(\.blotNamespace) private var namespace
    @Environment(\.scenePhase) private var phase
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    let context: BlotContext
    @State private var reaction: BlotState?
    @State private var eventID = -1
    var body: some View {
        let base = app.activeBlotState
        let state = [.waiting, .blocked, .error].contains(base) ? base : (reaction ?? base)
        Group {
            if let namespace {
                pet(state).matchedGeometryEffect(id: "primary-blot", in: namespace)
            } else { pet(state) }
        }
        .onAppear { receive(app.blotStimulus) }
        .onChange(of: app.blotStimulus) { _, event in receive(event) }
        .onChange(of: phase) { _, phase in if phase != .active { reaction = nil } }
        .task(id: "\(eventID)-\(phase)-\(app.settings.reduceMotion)-\(systemReduceMotion)") {
            guard phase == .active && !app.settings.reduceMotion && !systemReduceMotion else { return }
            guard let current = reaction else { return }
            let id = eventID
            do { try await Task.sleep(for: .seconds((current.duration ?? 0.4) + 0.25)) } catch { return }
            if eventID == id { reaction = nil }
        }
    }
    private func pet(_ state: BlotState) -> some View {
        BlotView(state: state, size: K.composerBlotSize, replay: eventID, followsPointer: true,
                 behavior: .lively, tappable: true, context: context)
    }
    private func receive(_ event: BlotStimulus) {
        guard event.context == context, event.id != eventID, Date().timeIntervalSince(event.createdAt) < 2 else { return }
        eventID = event.id
        switch event.kind {
        case .sent: reaction = .jump
        case .success: reaction = .happy
        case .failure: reaction = .error
        case .none: reaction = nil
        case .typing: if app.settings.reduceMotion || systemReduceMotion { reaction = nil }
        }
    }
}
