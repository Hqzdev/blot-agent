#if DEBUG
import Foundation
/// Records UI-test input and feedback requests without changing accessibility labels.
@MainActor
final class PhoneTabInteractionRecorder {
    private struct Event: Codable {
        let route: String
        let sequence: Int
    }
    private struct Snapshot: Codable {
        var taps: [Event] = []
        var feedback: [Event] = []
    }

    private let url: URL
    private var snapshot = Snapshot()

    init?() {
        guard ProcessInfo.processInfo.arguments.contains("--tab-interaction-probe"),
              let directory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first else { return nil }
        url = directory.appendingPathComponent("tab-interactions.json")
        save()
    }

    func tapped(_ route: WorkspaceRoute, sequence: Int) {
        snapshot.taps.append(Event(route: route.rawValue, sequence: sequence))
        save()
    }

    func requestedFeedback(_ route: WorkspaceRoute, sequence: Int) {
        snapshot.feedback.append(Event(route: route.rawValue, sequence: sequence))
        save()
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        try? data.write(to: url, options: .atomic)
    }
}
#endif
