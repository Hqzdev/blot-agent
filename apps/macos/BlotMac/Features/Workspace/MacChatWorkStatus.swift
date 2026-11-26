import SwiftUI

struct MacChatWorkStatus: View {
    let title: String
    let start: Date
    var end: Date?
    let russian: Bool

    var body: some View {
        Group {
            if let end { label(at: end, active: false) }
            else { TimelineView(.periodic(from: .now, by: 1)) { tick in label(at: tick.date, active: true) } }
        }.font(.callout).foregroundStyle(.secondary)
    }

    private func label(at date: Date, active: Bool) -> some View {
        let seconds = Int(max(0, date.timeIntervalSince(start)))
        let minutes = seconds / 60
        let prefix = minutes > 0 ? "\(minutes)" + (russian ? "м " : "m ") : ""
        let duration = prefix + "\(seconds % 60)" + (russian ? "с" : "s")
        return HStack(spacing: 4) {
            if active { MacChatActivityLabel(title: title) }
            else { Text(title) }
            Text("· " + duration).monospacedDigit()
        }.accessibilityElement(children: .ignore).accessibilityLabel(title + " · " + duration)
    }
}
