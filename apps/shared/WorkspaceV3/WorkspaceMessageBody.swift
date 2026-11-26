import BlotDesign
import BlotDomain
import BlotWorkspace
import SwiftUI

struct WorkspaceMessageBody: View {
    let text: String
    let markdown: Bool
    let agents: [BlotV3.AgentProfile]
    let skills: [BlotV3.Skill]
    var onAccentSurface = false
    var report = false
    @Environment(WorkspaceStore.self) private var store
    var body: some View {
        if markdown {
            VStack(alignment: .leading, spacing: blockSpacing) {
                ForEach(Array(WorkspaceMessageBlocksCache.blocks(text).enumerated()), id: \.offset) { _, block in
                    switch block {
                    case .text(let value): inline(value)
                    case .heading(let level, let value): inline(value)
                        .font(report ? .system(size: level == 1 ? 30 : level == 2 ? 23 : 18, weight: .semibold) : level <= 2 ? .title3.weight(.semibold) : .headline)
                        .accessibilityAddTraits(.isHeader)
                    case .code(let language, let value): code(language: language, value: value)
                    case .table(let headers, let rows): table(headers: headers, rows: rows)
                    }
                }
            }
        } else { inline(text) }
    }
    private var blockSpacing: CGFloat {
        if report { return 22 }
        #if os(macOS)
        return 6
        #else
        return 12
        #endif
    }
    private func inline(_ value: String) -> some View { WorkspaceMessageText(text: value, markdown: markdown, agents: agents, skills: skills, onAccentSurface: onAccentSurface) }
    private func code(language: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(language.isEmpty ? (store.language == "ru" ? "Код" : "Code") : language).lineLimit(1)
                Spacer()
                Button { WorkspaceClipboard.copy(value) } label: { BlotLabel(store.language == "ru" ? "Копировать" : "Copy", symbol: "doc.on.doc") }.buttonStyle(.plain)
            }.font(.caption).foregroundStyle(.secondary)
            ScrollView(.horizontal) { Text(value).font(.system(.callout, design: .monospaced)).textSelection(.enabled).fixedSize(horizontal: true, vertical: false) }
        }.padding(12).background(WorkspaceStyle.ink.opacity(0.045), in: RoundedRectangle(cornerRadius: 16))
    }
    private func table(headers: [String], rows: [[String]]) -> some View {
        ScrollView(.horizontal) {
            Grid(alignment: .topLeading, horizontalSpacing: 0, verticalSpacing: 0) {
                GridRow { ForEach(Array(headers.enumerated()), id: \.offset) { _, header in inline(header).font(.callout.weight(.semibold)).frame(minWidth: 100, maxWidth: 220, alignment: .leading).padding(10) } }
                    .background(WorkspaceStyle.ink.opacity(0.055))
                ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                    GridRow { ForEach(Array(row.enumerated()), id: \.offset) { _, cell in inline(cell).frame(minWidth: 100, maxWidth: 220, alignment: .leading).padding(10) } }
                        .background(WorkspaceStyle.ink.opacity(index.isMultiple(of: 2) ? 0.015 : 0.035))
                }
            }
        }.clipShape(RoundedRectangle(cornerRadius: 14))
    }
}

@MainActor private enum WorkspaceMessageBlocksCache {
    private final class Entry {
        let blocks: [WorkspaceMarkdownBlock]
        init(_ blocks: [WorkspaceMarkdownBlock]) { self.blocks = blocks }
    }
    private static let cache: NSCache<NSString, Entry> = { let value = NSCache<NSString, Entry>(); value.countLimit = 128; value.totalCostLimit = 4 * 1024 * 1024; return value }()
    static func blocks(_ text: String) -> [WorkspaceMarkdownBlock] {
        let key = text as NSString
        if let saved = cache.object(forKey: key) { return saved.blocks }
        let blocks = WorkspaceMarkdownBlocks().parse(text)
        cache.setObject(Entry(blocks), forKey: key, cost: text.utf8.count * 3 + 256)
        return blocks
    }
}
