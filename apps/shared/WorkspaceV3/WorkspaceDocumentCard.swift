import BlotDesign
import BlotDomain
import BlotWorkspace
import SwiftUI

/// A compact result row mirrors the link's stable artifact, including its latest saved revision.
struct WorkspaceDocumentCard: View {
    let file: BlotV3.Artifact
    @Environment(WorkspaceStore.self) private var store
    @State private var document: WorkspaceEditableDocument?
    @State private var localURL: URL?
    #if os(iOS)
    @State private var showingChanges = false
    #endif
    private var value: WorkspaceEditableDocument? { store.documentEdits[file.metadata.id]?.saved ?? document }
    private var ru: Bool { store.language == "ru" }
    private var kind: String {
        switch value?.kind {
        case .table: ru ? "Таблица" : "Spreadsheet"
        case .presentation: ru ? "Презентация" : "Presentation"
        default: ru ? "Документ" : "Document"
        }
    }
    var body: some View {
        ViewThatFits(in: .horizontal) {
            row(horizontal: true)
            row(horizontal: false)
        }
        .padding(12).frame(maxWidth: .infinity, alignment: .leading)
        .background(WorkspaceStyle.canvas, in: RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(WorkspaceStyle.ink.opacity(0.1)))
        #if os(iOS)
        .workspacePanelSheet(isPresented: $showingChanges) {
            if let text = creationText { WorkspaceFileDifferenceView(title: file.name, before: nil, after: text, created: true) }
        }
        #endif
        .task(id: store.chatContent.documentRevisions[file.metadata.id] ?? []) {
            document = try? await store.fileCommands?.editableWorkspaceDocument(file.metadata.id)
            localURL = try? await store.localFileURL(value?.exportArtifactID ?? file.metadata.id)
        }
    }
    @ViewBuilder private func row(horizontal: Bool) -> some View {
        if horizontal {
            HStack(spacing: 12) { openButton; changesButton; menu.fixedSize() }
        } else {
            VStack(alignment: .leading, spacing: 12) { openButton; HStack { Spacer(); changesButton; menu } }
        }
    }
    private var openButton: some View {
        Button { store.showGeneratedFile(file.metadata.id) } label: {
            HStack(spacing: 12) {
                BlotIcon(symbol: "doc.text", size: 23).foregroundStyle(.blue)
                    .frame(width: 48, height: 48)
                    .background(WorkspaceStyle.ink.opacity(0.045), in: RoundedRectangle(cornerRadius: 14))
                VStack(alignment: .leading, spacing: 5) {
                    Text(file.name).font(.body.weight(.medium)).lineLimit(2)
                    Text(kind + " · " + (file.mediaType == "application/pdf" ? "PDF" : file.name.components(separatedBy: ".").last?.uppercased() ?? ""))
                        .font(.caption).foregroundStyle(.secondary)
                }.frame(maxWidth: .infinity, alignment: .leading)
            }.frame(minWidth: 130, minHeight: 50, alignment: .leading).contentShape(Rectangle())
                .blotHover(in: RoundedRectangle(cornerRadius: 14))
        }.buttonStyle(.plain).accessibilityLabel((ru ? "Открыть документ " : "Open document ") + (value?.title ?? file.name))
    }
    #if os(iOS)
    private var creationText: String? {
        guard let value else { return nil }
        switch value.kind {
        case .markdown, .pdf, .text: return value.body
        case .table: return (try? value.rendered()).flatMap { String(data: $0, encoding: .utf8) }
        case .presentation: return value.slides.map { $0.title + "\n" + $0.body }.joined(separator: "\n\n")
        }
    }
    #endif
    @ViewBuilder private var changesButton: some View {
        #if os(macOS)
        if value != nil {
            Button(ru ? "Изменения" : "View changes") {
                store.showChanges(.init(kind: .creation, id: file.metadata.id))
            }.buttonStyle(WorkspaceButtonStyle(.secondary))
        }
        #else
        if creationText != nil {
            Button(ru ? "Изменения" : "View changes") { showingChanges = true }.buttonStyle(WorkspaceButtonStyle(.secondary))
        }
        #endif
    }
    private var menu: some View {
        WorkspaceFileActionsMenu {
            Button(ru ? "Открыть в Ori" : "Open in Ori") { store.showGeneratedFile(file.metadata.id) }
            if value != nil { Button(ru ? "Редактировать" : "Edit") { store.showGeneratedFile(file.metadata.id, editing: true) } }
            if let localURL {
                ShareLink(item: localURL) { BlotLabel(ru ? "Поделиться файлом" : "Share file", symbol: "square.and.arrow.up") }
                    #if os(macOS)
                    .buttonStyle(MacMenuRowStyle())
                    #endif
            }
            Button(ru ? "Копировать ссылку" : "Copy link") { WorkspaceClipboard.copy(WorkspaceResultLink.url(for: file.metadata.id).absoluteString) }
        } label: { BlotLabel(ru ? "Открыть" : "Open in", symbol: "chevron.down").font(.callout).padding(.horizontal, 10).padding(.vertical, 8).contentShape(Capsule()) }
        .fixedSize()
        .blotHover(in: Capsule())
        .accessibilityLabel((ru ? "Действия с файлом " : "File actions ") + (value?.title ?? file.name))
    }
}

// Match only standalone receipts for the attached file. Preserve commentary and warnings.
enum WorkspaceDocumentReceipt {
    static func matches(_ text: String, fileName: String) -> Bool {
        let stem = (fileName as NSString).deletingPathExtension
        guard !stem.isEmpty else { return false }
        let names = [fileName, stem].map(NSRegularExpression.escapedPattern(for:)).joined(separator: "|")
        let name = "(?:\(names))"
        let russian = #"(?:Локальн(?:ый|ая) )?(?:документ(?: PDF)?|таблица(?: CSV)?|презентация) «\#(name)» (?:успешно )?создан[а]?(?: внутри Blot)?"#
        let pdf = fileName.lowercased().hasSuffix(".pdf") ? "(?: и доступна в формате PDF)?" : ""
        let english = #"(?:The )?(?:(?:local )?(?:document|spreadsheet|presentation) )?["“]?\#(name)["”]? (?:was |has been )?(?:successfully )?created"#
        let pattern = #"\A(?:\#(russian)\#(pdf)|\#(english))\.?\z"#
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
            .range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil
    }
}
