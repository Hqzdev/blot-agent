import SwiftUI

struct MacChatWorkStatus: View {
    let title: String
    let start: Date
    var end: Date?
    let russian: Bool

    var body: some View {
        if let end {
            label(at: end)
        } else {
            TimelineView(.periodic(from: .now, by: 1)) { tick in label(at: tick.date) }
        }
    }

    private func label(at date: Date) -> some View {
        let seconds = Int(max(0, date.timeIntervalSince(start)))
        let minutes = seconds / 60
        let prefix = minutes > 0 ? "\(minutes)" + (russian ? "м " : "m ") : ""
        let duration = prefix + "\(seconds % 60)" + (russian ? "с" : "s")
        return Text(title + " · " + duration).monospacedDigit()
    }
}
