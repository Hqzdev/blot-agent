import BlotDesign
import SwiftUI

/// Shared leading header controls for sidebar visibility and creation.
struct MacTeamWindowControls: View {
    @Environment(MacTeamPresentation.self) private var presentation
    @Environment(\.blotReduceMotion) private var reduceMotion
    @State private var creating = false

    var body: some View {
        GlassEffectContainer(spacing: 6) {
            HStack(spacing: 6) {
                Button { presentation.sidebarVisible.toggle() } label: {
                    BlotIcon(.layout, size: BlotIconSize.control).frame(width: 36, height: 36)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .glassEffect(.regular.interactive(), in: .circle)
                .help(presentation.sidebarVisible ? "Скрыть команду" : "Показать команду")
                .accessibilityLabel(presentation.sidebarVisible ? "Скрыть команду" : "Показать команду")

                Button { creating.toggle() } label: {
                    BlotIcon(.plus, size: BlotIconSize.control)
                        .frame(width: 36, height: 36).contentShape(Circle())
                }
                .buttonStyle(.plain).help("Создать")
                .glassEffect(.regular.interactive(), in: .circle)
                .opacity(creating ? 0 : 1)
                .accessibilityLabel("Создать")
                .accessibilityValue(creating ? "Раскрыто" : "Скрыто")
                .background {
                    MacTeamToolbarExpansion(isPresented: $creating, size: CGSize(width: 192, height: 128)) {
                        MacTeamCreateMenu(close: { creating = false }) { sheet in
                            creating = false
                            presentation.sheet = sheet
                        }
                        .environment(\.blotReduceMotion, reduceMotion)
                    }
                    .frame(width: 36, height: 36)
                }
            }.foregroundStyle(WorkspaceStyle.ink)
        }
        .onChange(of: presentation.sheet?.id) { _, _ in creating = false }
        .onChange(of: presentation.selection) { _, _ in creating = false }
    }
}

struct MacTeamCreateMenu: View {
    let close: () -> Void
    let create: (MacTeamSheet) -> Void
    @Environment(\.blotReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Button(action: close) {
                BlotIcon(.plus, size: BlotIconSize.control)
                    .rotationEffect(.degrees(expanded ? 45 : 0))
                    .frame(width: 36, height: 36).contentShape(Circle())
            }.buttonStyle(.plain).accessibilityLabel("Закрыть создание")
            VStack(spacing: 2) {
                createButton("Агент", glyph: .personAdd, sheet: .newAgent)
                createButton("Группа", glyph: .people, sheet: .group(nil))
            }.padding(5).opacity(expanded ? 1 : 0)
        }
        .frame(width: expanded ? 192 : 36, height: expanded ? 128 : 36, alignment: .topLeading)
        .clipped()
        .foregroundStyle(WorkspaceStyle.ink)
        .glassEffect(.regular.interactive(), in: .rect(cornerRadius: expanded ? 22 : 18))
        .frame(width: 192, height: 128, alignment: .topLeading)
        .onAppear {
            withAnimation(reduceMotion || systemReduceMotion ? nil : .spring(response: 0.36, dampingFraction: 0.84)) {
                expanded = true
            }
        }
    }

    private func createButton(_ title: String, glyph: BlotGlyph, sheet: MacTeamSheet) -> some View {
        MacTeamNavigationButton { create(sheet) } label: {
            HStack(spacing: 6) {
                BlotIcon(glyph, size: BlotIconSize.control)
                Text(title).font(.system(size: 12, weight: .medium))
            }
        }.accessibilityLabel(title == "Агент" ? "Новый агент" : "Новый групповой чат")
    }
}
