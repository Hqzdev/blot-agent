import BlotDesign
import BlotDomain
import SwiftUI

struct WorkspaceToolActivityView: View {
    let message: BlotV3.Message
    @Environment(WorkspaceStore.self) private var store
    @State private var showsAll = false
    @State private var expanded = false
    private var russian: Bool { store.language == "ru" }
    var body: some View {
        let rows = store.chatContent.activities(for: message)
        if !rows.isEmpty {
            VStack(alignment: .leading, spacing: 3) {
                #if os(macOS)
                let active = rows.contains { $0.state == .running || $0.state == .queued || $0.state == .approval }
                let failure = rows.contains { [.denied, .failed, .stopped, .unknown].contains($0.state) }
                if active {
                    MacChatWorkStatus(title: russian ? "Работаю" : "Working", start: message.metadata.createdAt, russian: russian)
                        .font(.callout).foregroundStyle(.secondary)
                } else {
                    Button { expanded.toggle() } label: {
                        HStack(spacing: 6) {
                            MacChatWorkStatus(title: failure ? (russian ? "Работа остановлена" : "Work stopped") : (russian ? "Готово" : "Done"),
                                start: message.metadata.createdAt, end: message.metadata.updatedAt, russian: russian)
                            Image(systemName: expanded ? "chevron.down" : "chevron.right").font(.caption2)
                        }.padding(.vertical, 6).contentShape(Rectangle())
                    }.buttonStyle(.plain).foregroundStyle(.secondary)
                }
                if active || expanded { actionRows(rows) }
                #else
                actionRows(rows)
                #endif
            }.accessibilityIdentifier("workspace.chat.tool-activity.\(message.metadata.id)")
        }
    }
    @ViewBuilder private func actionRows(_ rows: [WorkspaceToolActivity]) -> some View {
        ForEach(showsAll ? rows : Array(rows.suffix(4))) { row in
            WorkspaceToolActivityRow(row: row, russian: russian)
        }
        if rows.count > 4 {
            Button(showsAll ? (russian ? "Свернуть действия" : "Show fewer actions") : (russian ? "Все действия (\(rows.count))" : "All actions (\(rows.count))")) { showsAll.toggle() }
                .font(.caption).buttonStyle(.plain).foregroundStyle(.secondary).padding(.leading, 27).padding(.vertical, 5)
        }
        if rows.count == 64 { Text(russian ? "Показаны последние 64 действия" : "Showing the latest 64 actions").font(.caption2).foregroundStyle(.secondary) }
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
                    else { Image(systemName: row.symbol).frame(width: 20, height: 20).accessibilityHidden(true) }
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 5) { name; provider }
                        VStack(alignment: .leading, spacing: 2) { name; provider }
                    }.frame(maxWidth: .infinity, alignment: .leading)
                    if row.state == .running { ProgressView().controlSize(.mini).accessibilityLabel(row.status(russian: russian)) }
                    else if row.state != .succeeded { Text(row.status(russian: russian)).font(.caption2).foregroundStyle(terminalFailure ? .red : .secondary) }
                    Image(systemName: expanded ? "chevron.down" : "chevron.right").font(.system(size: 10)).accessibilityHidden(true)
                }
                .font(.system(size: 12, weight: .regular)).foregroundStyle(WorkspaceStyle.secondary).padding(.horizontal, 7).padding(.vertical, 6)
                .frame(minHeight: minimumHeight).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
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
                            .font(.caption).buttonStyle(.bordered)
                    }
                }.padding(.leading, 35).padding(.bottom, 8)
            }
        }
    }
    @ViewBuilder private var name: some View {
        #if os(macOS)
        if row.state == .running { MacChatActivityLabel(title: displayTitle).multilineTextAlignment(.leading) }
        else { Text(displayTitle).multilineTextAlignment(.leading) }
        #else
        Text(row.title(russian: russian)).multilineTextAlignment(.leading)
        #endif
    }
    @ViewBuilder private var provider: some View {
        if let provider = row.provider {
            Text("@" + provider).foregroundStyle(row.plugin?.color ?? .secondary).multilineTextAlignment(.leading)
        }
    }
}
