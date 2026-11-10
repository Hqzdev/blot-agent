import BlotDesign
import SwiftUI

struct MacMarketplaceTemplateDetail: View {
    let template: MacDemoTemplate
    @Environment(WorkspaceStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Environment(\.macSheetSize) private var sheetSize
    @State private var commandID = UUID()
    @State private var saveError: String?

    private var requiredPlugins: [MacTeamPlugin] {
        template.plugins.compactMap { id in MacTeamSamples.plugins.first { $0.id == id } }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            MacTeamSheetHeader(title: "Шаблон агента")
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    HStack(spacing: 18) {
                        WorkspaceAvatar(shape: .init(rawValue: template.shape) ?? .round,
                            color: WorkspaceAvatarView.color(template.color), size: 64)
                        VStack(alignment: .leading, spacing: 6) {
                            WorkspaceLocalizedText(template.name).font(.title2.weight(.semibold))
                            WorkspaceLocalizedText(template.role).foregroundStyle(.secondary)
                        }
                    }
                    WorkspaceLocalizedText(template.summary).foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Инструкции").font(.headline)
                        WorkspaceLocalizedText(template.instructions).lineSpacing(4).textSelection(.enabled)
                    }.padding(18).frame(maxWidth: .infinity, alignment: .leading)
                        .background(WorkspaceStyle.surface, in: RoundedRectangle(cornerRadius: 16))
                    if !requiredPlugins.isEmpty {
                        Text("Приложения для работы").font(.headline)
                        ForEach(requiredPlugins) { plugin in
                            HStack(spacing: 12) {
                                MacTeamPluginIcon(plugin: plugin, size: 34)
                                WorkspaceLocalizedText(plugin.name)
                                Spacer()
                            }
                        }
                        Text("Доступ к этим сервисам подключается отдельно.").font(.caption).foregroundStyle(.secondary)
                    }
                    if let saveError {
                        Label(saveError, systemImage: "exclamationmark.triangle").font(.callout).foregroundStyle(.red)
                    }
                }.padding(24)
            }
            Divider()
            HStack {
                Button("Отмена") { dismiss() }.buttonStyle(WorkspaceButtonStyle(.secondary)).keyboardShortcut(.cancelAction)
                Spacer()
                Button(action: addAgent) {
                    HStack(spacing: 8) {
                        if store.busy { ProgressView().controlSize(.small) }
                        Text("Добавить в команду")
                    }
                }.buttonStyle(WorkspaceButtonStyle()).keyboardShortcut(.defaultAction)
            }.padding(18).disabled(store.busy)
        }.frame(width: min(620, sheetSize.width), height: min(610, sheetSize.height)).background(WorkspaceStyle.canvas)
            .interactiveDismissDisabled(store.busy)
    }

    private func addAgent() {
        saveError = nil
        let draft = WorkspaceAgentForm(name: store.t(template.name), instructions: store.t(template.instructions),
            shape: template.shape, color: template.color)
        _Concurrency.Task {
            if await store.addCatalogAgent(draft, commandID: commandID) { dismiss() }
            else { saveError = store.error ?? "Не удалось добавить агента. Попробуйте ещё раз." }
        }
    }
}
