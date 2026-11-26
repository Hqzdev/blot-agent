import BlotDesign
import BlotWorkspace
import SwiftUI

struct WorkspaceFileChangeCard: View {
    let id: UUID
    @Environment(WorkspaceStore.self) private var store
    @State private var change: WorkspaceFileChange?
    @State private var failure: String?
    #if os(iOS)
    @State private var showingFile = false
    @State private var showingChanges = false
    #endif
    @State private var saving = false
    @State private var undone = false
    private var ru: Bool { store.language == "ru" }
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                BlotIcon(symbol: "doc.text", size: 23).foregroundStyle(.secondary).frame(width: 42, height: 42)
                    .background(WorkspaceStyle.ink.opacity(0.04), in: RoundedRectangle(cornerRadius: 13))
                    .allowsHitTesting(false)
                VStack(alignment: .leading, spacing: 5) {
                    Text(title).font(.system(size: 14, weight: .medium)).lineLimit(2)
                    if let change {
                        if change.before != nil || change.created {
                            WorkspaceChangeCounts(difference: change.difference)
                        } else { Text(change.path).font(.caption).foregroundStyle(.secondary).lineLimit(1) }
                    }
                }.frame(maxWidth: .infinity, alignment: .leading).allowsHitTesting(false)
                if let change, change.canUndo {
                    Button { _Concurrency.Task { await undo() } } label: {
                        BlotLabel(undone ? (ru ? "Отменено" : "Undone") : (ru ? "Отменить" : "Undo"), symbol: "arrow.uturn.backward")
                    }.buttonStyle(BlotPlainButtonStyle()).disabled(saving || undone).padding(6)
                }
                Button(ru ? "Изменения" : "View changes") {
                    #if os(macOS)
                    store.showChanges(.init(kind: .fileWrite, id: id))
                    #else
                    showingChanges = true
                    #endif
                }.buttonStyle(WorkspaceButtonStyle(.secondary)).disabled(change == nil)
            }
            if let failure { Text(failure).font(.caption).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true) }
        }.padding(12).background {
            Button {
                #if os(iOS)
                showingFile = true
                #else
                store.showFileChange(id, title: change?.path ?? title)
                #endif
            } label: {
                RoundedRectangle(cornerRadius: 18).fill(WorkspaceStyle.canvas).contentShape(RoundedRectangle(cornerRadius: 18))
                    .blotHover(in: RoundedRectangle(cornerRadius: 18))
            }.buttonStyle(.plain).disabled(change == nil)
                .accessibilityLabel((ru ? "Открыть файл " : "Open file ") + title)
                .accessibilityIdentifier("workspace.chat.file-change.open.\(id)")
        }
            .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(WorkspaceStyle.ink.opacity(0.1)))
            .task(id: id) {
                do { change = try await store.fileCommands?.workspaceFileChange(id) }
                catch { failure = ru ? "Журнал изменений недоступен на этом устройстве." : "The change record is unavailable on this device." }
            }
            #if os(iOS)
            .sheet(isPresented: $showingFile) { WorkspaceFileChangePreview(id: id).presentationDragIndicator(.visible) }
            .workspacePanelSheet(isPresented: $showingChanges) {
                if let change { WorkspaceFileDifferenceView(title: change.path, before: change.before, after: change.after, created: change.created) }
            }
            #endif
            .accessibilityIdentifier("workspace.chat.file-change.\(id)")
    }
    private var title: String {
        guard let change else { return ru ? "Изменения файла" : "File changes" }
        return (change.created ? (ru ? "Создан " : "Created ") : (ru ? "Изменён " : "Edited ")) + (change.path as NSString).lastPathComponent
    }
    private func undo() async {
        guard !saving, !undone, let files = store.fileCommands else { return }
        saving = true; failure = nil; defer { saving = false }
        do { try await files.undoWorkspaceFileChange(id); undone = true; try await store.refreshContent() }
        catch { failure = ru ? "Не удалось отменить: файл уже изменён, доступ отозван или исходная версия недоступна. Текущий файл сохранён." : "Could not undo: the file changed, access was revoked, or the original is unavailable. The current file is retained." }
    }
}

struct WorkspaceChangeCounts: View {
    let difference: WorkspaceTextDifference
    var body: some View {
        HStack(spacing: 7) {
            Text("+\(difference.added)").foregroundStyle(.green)
            if difference.removed > 0 { Text("−\(difference.removed)").foregroundStyle(.red) }
        }.font(.system(size: 12)).monospacedDigit()
    }
}

#if os(iOS)
struct WorkspaceFileDifferenceView: View {
    let title: String
    let before: String?
    let after: String
    let created: Bool
    @WorkspacePresentationDismiss private var dismiss
    @Environment(WorkspaceStore.self) private var store
    private var ru: Bool { store.language == "ru" }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            WorkspacePanelFormHeader(title: title) { Button(store.t("Close")) { dismiss() } }
            if before != nil || created { WorkspaceChangeCounts(difference: .init(before: before ?? "", after: after)) }
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if let before { textBlock(ru ? "До изменения" : "Before", text: before, color: .red) }
                    else if !created { Text(ru ? "Предыдущая версия слишком велика для журнала." : "The previous version exceeds the change log limit.").font(.callout).foregroundStyle(.secondary) }
                    textBlock(created ? (ru ? "Созданный файл" : "Created file") : (ru ? "После изменения" : "After"), text: after, color: .green)
                }
            }
        }.padding(22).frame(minWidth: 380, idealWidth: 700, minHeight: 360, idealHeight: 560)
            .background(WorkspaceStyle.canvas).workspacePanelControls()
    }
    private func textBlock(_ title: String, text: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.callout.weight(.medium)).foregroundStyle(color)
            Text(text.isEmpty ? "∅" : text).font(.system(size: 12, design: .monospaced)).textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading).fixedSize(horizontal: false, vertical: true)
        }.padding(14).background(color.opacity(0.045), in: RoundedRectangle(cornerRadius: 16))
    }
}
#endif
