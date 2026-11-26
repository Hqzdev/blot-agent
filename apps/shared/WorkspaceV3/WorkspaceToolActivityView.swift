import Foundation
import BlotDesign
import BlotDomain
import SwiftUI

struct WorkspaceToolActivityView: View {
    let message: BlotV3.Message
    var inline = false
    @Environment(WorkspaceStore.self) private var store
    @State private var showsAll = false
    private var russian: Bool { store.language == "ru" }
    var body: some View {
        let rows = store.chatContent.activities(for: message)
        let hasBrowserSteps = rows.contains { $0.tool.hasPrefix("browser_") }
        let showsLiveBrowserSteps = hasBrowserSteps && message.delivery != .completed
        if !rows.isEmpty {
            VStack(alignment: .leading, spacing: 3) {
                if message.delivery == .completed && !inline {
                    Button { showsAll.toggle() } label: {
                        HStack(spacing: 7) {
                            Text(summary(rows: rows))
                            BlotIcon(symbol: showsAll ? "chevron.down" : "chevron.right", size: 12)
                        }.font(.callout).frame(minHeight: 32, alignment: .leading).contentShape(Rectangle())
                    }.buttonStyle(BlotSecondaryTextButtonStyle()).accessibilityLabel(summary(rows: rows))
                }
                if inline || message.delivery != .completed || showsAll {
                    ForEach(inline || showsAll || showsLiveBrowserSteps ? rows : Array(rows.suffix(4))) { row in WorkspaceToolActivityRow(row: row, russian: russian) }
                    if message.delivery != .completed, rows.count > 4, !showsLiveBrowserSteps {
                        Button(showsAll ? (russian ? "Свернуть действия" : "Show fewer actions") : (russian ? "Все действия (\(rows.count))" : "All actions (\(rows.count))")) { showsAll.toggle() }
                            .font(.caption).buttonStyle(BlotSecondaryTextButtonStyle()).padding(.leading, 27).padding(.vertical, 5)
                    }
                    if rows.count == 64 { Text(russian ? "Показаны последние 64 действия" : "Showing the latest 64 actions").font(.caption2).foregroundStyle(.secondary) }
                }
            }.kAnimation(KMotion.standard, value: showsAll)
                .accessibilityIdentifier("workspace.chat.tool-activity.\(message.metadata.id)")
        }
    }
    private func summary(rows: [WorkspaceToolActivity]) -> String {
        let steps = (store.snapshot.modelSteps ?? []).filter { $0.responseMessageId == message.metadata.id }
        guard let start = steps.map(\.metadata.createdAt).min(), let end = steps.map(\.metadata.updatedAt).max() else {
            return russian ? "Действия: \(rows.count)" : "Actions: \(rows.count)"
        }
        let seconds = max(1, Int(ceil(end.timeIntervalSince(start))))
        let duration = seconds >= 60 ? "\(seconds / 60)" + (russian ? "м " : "m ") + "\(seconds % 60)" + (russian ? "с" : "s") : "\(seconds)" + (russian ? "с" : "s")
        if rows.contains(where: { $0.tool.hasPrefix("browser_") }) {
            return (russian ? "Действия" : "Actions") + " (\(rows.count)) · " + duration
        }
        let failed = rows.contains { [.failed, .denied, .unknown].contains($0.state) }
        return (failed ? (russian ? "Завершено с ошибками · " : "Completed with errors · ") : (russian ? "Работа заняла " : "Worked for ")) + duration
    }

}

private struct WorkspaceToolActivityRow: View {
    let row: WorkspaceToolActivity
    let russian: Bool
    @Environment(WorkspaceStore.self) private var store
    @State private var expanded = false
    private var minimumHeight: CGFloat {
        #if os(iOS)
        44
        #else
        30
        #endif
    }
    private var displayTitle: String {
        #if os(macOS)
        if russian && row.state == .running && row.tool == "document_create" { return "Создаю документ" }
        #endif
        return row.title(russian: russian)
    }
    private var terminalFailure: Bool { row.state == .failed || row.state == .denied || row.state == .unknown }
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button { expanded.toggle() } label: {
                HStack(alignment: .center, spacing: 8) {
                    if let plugin = row.plugin { WorkspacePluginLogo(plugin: plugin, size: 20).clipShape(RoundedRectangle(cornerRadius: 4)) }
                    else { BlotIcon(symbol: row.symbol).frame(width: 20, height: 20).accessibilityHidden(true) }
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 5) { name; provider }
                        VStack(alignment: .leading, spacing: 2) { name; provider }
                    }.frame(maxWidth: .infinity, alignment: .leading)
                    if row.state == .running { ProgressView().controlSize(.mini).accessibilityLabel(row.status(russian: russian)) }
                    else if row.state != .succeeded { Text(row.status(russian: russian)).font(.caption2).foregroundStyle(terminalFailure ? .red : .secondary) }
                    BlotIcon(symbol: expanded ? "chevron.down" : "chevron.right", size: 10).accessibilityHidden(true)
                }
                .font(.system(size: 12, weight: .regular)).padding(.horizontal, 7).padding(.vertical, 6)
                .frame(minHeight: minimumHeight).contentShape(Rectangle())
            }
            .buttonStyle(BlotSecondaryTextButtonStyle())
            .accessibilityLabel(displayTitle + ", " + row.status(russian: russian))
            .accessibilityValue(expanded ? (russian ? "Развёрнуто" : "Expanded") : (russian ? "Свёрнуто" : "Collapsed"))
            .accessibilityIdentifier("workspace.chat.tool-action.\(row.id)")
            if expanded {
                VStack(alignment: .leading, spacing: 7) {
                    Text(row.status(russian: russian)).font(.caption.weight(.medium))
                    ForEach(Array(row.details.enumerated()), id: \.offset) { _, item in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(russian ? (item.label.components(separatedBy: " / ").first ?? item.label) : (item.label.components(separatedBy: " / ").last ?? item.label)).font(.caption2).foregroundStyle(.secondary)
                            Text(item.label == "Журнал / Log" ? (russian ? "Показан фрагмент" : "Output truncated") : item.value).font(.caption.monospaced()).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    if row.details.isEmpty { Text(russian ? "Статус получен из журнала выполнения." : "Status comes from the execution log.").font(.caption).foregroundStyle(.secondary) }
                    if let id = row.logArtifactID, store.chatContent.artifacts[id] != nil {
                        Button(russian ? "Открыть полный журнал" : "Open full log") { store.selectedRecordID = id; store.navigate(.file) }
                            .font(.caption).buttonStyle(WorkspaceButtonStyle(.secondary))
                    }
                }.padding(.leading, 35).padding(.bottom, 8)
            }
        }
    }
    @ViewBuilder private var name: some View {
        #if os(macOS)
        if row.state == .running {
            MacChatActivityLabel(title: displayTitle)
                .multilineTextAlignment(.leading)
        } else {
            Text(row.title(russian: russian)).multilineTextAlignment(.leading)
        }
        #else
        Text(row.title(russian: russian)).multilineTextAlignment(.leading)
            .modifier(WorkspaceActivityShimmer(active: row.state == .running))
        #endif
    }
    @ViewBuilder private var provider: some View {
        if let provider = row.provider {
            Text("@" + provider).foregroundStyle(row.plugin?.color ?? .secondary).multilineTextAlignment(.leading)
        }
    }
}
