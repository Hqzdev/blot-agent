import BlotDesign
import BlotWidgetSupport
import SwiftUI
import WidgetKit

struct BlotWidgetAvatar: View {
    var agent: WidgetAgent?
    var size: CGFloat = 28
    @Environment(\.widgetRenderingMode) private var rendering
    var body: some View {
        WorkspaceAvatar(shape: .init(rawValue: agent?.shape ?? "round") ?? .round,
                        color: color, size: size, showsEyes: rendering == .fullColor)
            .widgetAccentable()
    }
    private var color: Color { WorkspaceAvatarPalette.color(agent?.color ?? "ink") }
}

struct BlotWidgetHeading: View {
    let title: String
    var detail: String?
    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).font(.subheadline.weight(.semibold)).lineLimit(1)
            Spacer(minLength: 4)
            if let detail { Text(detail).font(.caption2).foregroundStyle(.secondary).lineLimit(1) }
        }
    }
}

struct BlotWidgetState: View {
    let state: WidgetWorkState
    let snapshot: WidgetSnapshot
    var body: some View {
        Label(title, systemImage: symbol).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
    }
    private var title: String {
        switch state {
        case .idle: snapshot.text("Готов", "Ready")
        case .running: snapshot.text("В работе", "Working")
        case .waiting: snapshot.text("Ждёт тебя", "Needs you")
        case .completed: snapshot.text("Готово", "Completed")
        case .failed: snapshot.text("Нужна проверка", "Needs review")
        case .paused: snapshot.text("Приостановлено", "Paused")
        case .offline: snapshot.text("Ждёт подключения", "Waiting for connection")
        }
    }
    private var symbol: String {
        switch state {
        case .idle: "circle"
        case .running: "circle.dotted"
        case .waiting: "bubble.left"
        case .completed: "checkmark"
        case .failed: "exclamationmark.circle"
        case .paused: "pause.circle"
        case .offline: "wifi.slash"
        }
    }
}

struct BlotWidgetEmpty: View {
    let title: String
    let detail: String
    let symbol: String
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: symbol).font(.title3).widgetAccentable().accessibilityHidden(true)
            Spacer(minLength: 0)
            Text(title).font(.subheadline.weight(.semibold)).lineLimit(3)
            Text(detail).font(.caption2).foregroundStyle(.secondary).lineLimit(3)
        }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
}
