import BlotDesign
import BlotDomain
import BlotWorkspace
import SwiftUI
import UniformTypeIdentifiers

struct WorkspaceSkillMarketplaceButton: View {
    @Environment(WorkspaceStore.self) private var store
    @State private var showing = false
    var body: some View {
        Button { showing = true } label: { BlotLabel("Marketplace", symbol: "square.grid.2x2") }
            .workspacePanelSheet(isPresented: $showing) { WorkspaceSkillMarketplace().environment(store) }
    }
}

private struct WorkspaceSkillMarketplace: View {
    @Environment(WorkspaceStore.self) private var store
    @WorkspacePresentationDismiss private var dismiss
    @State private var importing = false
    @State private var bundle: WorkspaceSkillBundle?
    @State private var working = false
    @State private var failure: String?
    private var ru: Bool { store.language == "ru" }
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text(ru ? "Установленные шаблоны становятся обычными навыками: их можно редактировать, назначать агентам, запускать из чата и по расписанию." : "Installed templates become editable skills. Assign them to agents, run them from chat, or schedule them.").foregroundStyle(.secondary)
                    ForEach(WorkspaceSkillBundle.catalog) { item in
                        WorkspaceCard { Text(item.name).font(.headline); Text(item.instructions).lineLimit(4); Button(ru ? "Просмотреть и установить" : "Review and install") { bundle = item } }
                    }
                    Button(ru ? "Импорт навыка из файла" : "Import skill file") { importing = true }
                    if let bundle {
                        Divider(); Text(bundle.name).font(.title2)
                        Text(bundle.instructions).textSelection(.enabled)
                        Text(ru ? "Требуемые инструменты" : "Required tools").font(.headline)
                        ForEach(bundle.tools, id: \.self) { Text($0).font(.caption.monospaced()) }
                        Text(ru ? "Установка не выдаёт новых прав. Подключите сервисы и назначьте навык агенту в его настройках." : "Installing grants no permissions. Connect services and assign the skill to an agent in its settings.").font(.caption).foregroundStyle(.secondary)
                        Button(ru ? "Установить навык" : "Install skill") { install(bundle) }.disabled(working)
                    }
                    if let failure { Text(failure).foregroundStyle(.red) }
                }.padding(24)
            }

            .safeAreaInset(edge: .top, spacing: 0) {
                WorkspacePanelFormHeader(title: "Marketplace") {
                    Button(store.t("Close")) { dismiss() }.disabled(working)
                }
            }.workspaceEditorChrome()
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { result in
            do {
                let url = try result.get(), scoped = url.startAccessingSecurityScopedResource(); defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                let handle = try FileHandle(forReadingFrom: url); defer { try? handle.close() }
                bundle = try WorkspaceSkillBundle.decode(handle.read(upToCount: 64_001) ?? Data()); failure = nil
            } catch { failure = ru ? "Это не поддерживаемый файл навыка Ori." : "This is not a supported Ori skill file." }
        }
        #if os(macOS)
        .frame(minWidth: 550, minHeight: 560)
        #endif
    }
    private func install(_ bundle: WorkspaceSkillBundle) {
        guard !working, let commands = store.skillCommands else { return }; working = true
        _Concurrency.Task {
            defer { working = false }
            do { _ = try await commands.saveSkill(id: nil, version: 0, name: bundle.name, instructions: bundle.instructions, parameters: bundle.parameters, tools: bundle.tools); try await store.refreshSkills(); dismiss() }
            catch { failure = WorkspaceSkillFailure.text(error, russian: ru) }
        }
    }
}

struct WorkspaceSkillExport: Transferable {
    let data: Data
    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .json) { $0.data }.suggestedFileName("Ori Skill.json")
    }
}

struct WorkspaceSkillShareButton: View {
    let skill: BlotV3.Skill
    let revision: BlotV3.SkillRevision
    var body: some View {
        if let parameters = try? WorkspaceSkillService.parameters(revision),
           let data = try? JSONEncoder().encode(WorkspaceSkillBundle(name: skill.name, instructions: revision.instructions, parameters: parameters, tools: revision.toolIds)) {
            WorkspacePublishButton(kind: "skill", title: skill.name, data: data)
            ShareLink(item: WorkspaceSkillExport(data: data), preview: SharePreview(skill.name)) { BlotLabel("Share", symbol: "square.and.arrow.up") }
        }
    }
}
