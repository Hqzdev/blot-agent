import BlotDesign
import SwiftUI

struct MacCatalogSearchField: View {
    let prompt: String
    @Binding var query: String

    var body: some View {
        HStack(spacing: 9) {
            BlotIcon(.search, size: BlotIconSize.control).foregroundStyle(.secondary)
                .accessibilityHidden(true)
            TextField(prompt, text: $query).textFieldStyle(.plain)
        }
        .padding(12).background(WorkspaceStyle.surface.opacity(0.55), in: RoundedRectangle(cornerRadius: 10))
    }
}

struct MacCatalogCategories<Item: Hashable>: View {
    let items: [Item]
    @Binding var selection: Item
    let title: (Item) -> String

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 6) {
                ForEach(items, id: \.self) { item in
                    let active = item == selection
                    Button {
                        selection = item
                    } label: {
                        Text(title(item)).font(.system(size: 11, weight: active ? .medium : .regular))
                            .padding(.horizontal, 12).padding(.vertical, 7)
                            .foregroundStyle(active ? BlotColor.onInverse : WorkspaceStyle.ink)
                            .background(active ? BlotColor.inverse : WorkspaceStyle.surface, in: Capsule())
                    }.buttonStyle(BlotPlainButtonStyle())
                        .accessibilityAddTraits(active ? .isSelected : [])
                }
            }
        }.scrollIndicators(.hidden)
    }
}

struct MacCatalogTemplateGrid: View {
    let templates: [MacDemoTemplate]
    let select: (MacDemoTemplate) -> Void

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 14)], spacing: 14) {
            ForEach(templates) { template in
                Button {
                    select(template)
                } label: {
                    VStack(alignment: .leading, spacing: 14) {
                        MacCatalogAvatar(template: template, size: 46)
                        WorkspaceLocalizedText(template.name).font(.system(size: 14, weight: .medium))
                            .lineLimit(1)
                        WorkspaceLocalizedText(template.summary).font(.system(size: 11)).foregroundStyle(.secondary)
                            .lineLimit(2, reservesSpace: true)
                        BlotLabel("Посмотреть шаблон", symbol: "arrow.up.right", size: BlotIconSize.inline)
                            .font(.system(size: 10)).foregroundStyle(WorkspaceStyle.ink)
                    }.frame(maxWidth: .infinity, alignment: .leading).teamCard(padding: 18)
                        .contentShape(RoundedRectangle(cornerRadius: 14))
                }.buttonStyle(BlotPlainButtonStyle())
                    .accessibilityIdentifier("workspace.agent-template.\(template.id)")
            }
        }
    }
}

struct MacCatalogAvatar: View {
    let template: MacDemoTemplate
    let size: CGFloat

    var body: some View {
        WorkspaceAvatar(shape: .init(rawValue: template.shape) ?? .round,
            color: WorkspaceAvatarView.color(template.color), size: size)
            .accessibilityHidden(true)
    }
}
