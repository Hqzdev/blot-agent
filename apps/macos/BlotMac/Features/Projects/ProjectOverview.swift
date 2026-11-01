import BlotAPI
import BlotDesign
import SwiftUI

struct ProjectOverview: View {
    @Environment(AppState.self) private var app
    let project: WorkChatProject
    @State private var addingMaterial = false
    @State private var expandedMaterial: UUID?

    private var materials: [WorkspaceRow] {
        app.workspace.rows("MEMORY", projectID: UUID(uuidString: project.id)).filter {
            $0.data.text("scope") == "project" && $0.data.text("status") == "active"
        }
    }

    var body: some View {
        ScrollView {
            ContentColumn {
                VStack(alignment: .leading, spacing: KSpace.xl) {
                    HStack(alignment: .top, spacing: KSpace.md) {
                        Image(systemName: "folder").font(.system(size: 26, weight: .light)).foregroundStyle(K.text2)
                        VStack(alignment: .leading, spacing: 6) {
                            Text(project.name).font(KFont.pageTitle()).textSelection(.enabled)
                            Text("Чаты и материалы в одном месте")
                                .font(KFont.body()).foregroundStyle(K.text2)
                        }.frame(maxWidth: .infinity, alignment: .leading)
                    }
                    HStack {
                        Text("Материалы").font(KFont.label())
                        Spacer()
                        KButton(title: "Добавить", icon: "plus") { addingMaterial = true }
                    }
                    if materials.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Дайте Blot контекст").font(KFont.body(.medium))
                            Text("Добавьте описание задачи, заметки или документы. Затем напишите в поле ниже.")
                                .font(KFont.body()).foregroundStyle(K.text2)
                                .fixedSize(horizontal: false, vertical: true)
                        }.padding(KSpace.lg).frame(maxWidth: .infinity, alignment: .leading)
                            .background(K.surface2, in: RoundedRectangle(cornerRadius: K.rLg))
                    }
                    ForEach(materials, id: \.id) { material in
                        let parts = material.data.text("content").components(separatedBy: "\n\n")
                        DisclosureGroup(isExpanded: Binding(get: { expandedMaterial == material.id },
                                                           set: { expandedMaterial = $0 ? material.id : nil })) {
                            Text(parts.dropFirst().joined(separator: "\n\n")).font(KFont.body())
                                .foregroundStyle(K.text2).textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading).padding(.top, 8)
                        } label: {
                            Label(parts.first ?? "Материал", systemImage: "doc.text").font(KFont.body())
                        }
                    }
                }.padding(.vertical, KSpace.section)
            }
        }
        .sheet(isPresented: $addingMaterial) {
            if let id = UUID(uuidString: project.id) { ProjectMaterialEditor(projectID: id) }
        }
    }
}
