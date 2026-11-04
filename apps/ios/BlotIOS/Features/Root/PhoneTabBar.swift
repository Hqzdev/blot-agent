import BlotDesign
import SwiftUI

struct PhoneTabBar: View {
    private struct Item: Identifiable {
        let route: WorkspaceRoute
        let title: String
        let symbol: String
        var id: WorkspaceRoute { route }
    }

    private static let items: [Item] = [
        .init(route: .chats, title: "Chats", symbol: "bubble.left.and.bubble.right"),
        .init(route: .agents, title: "Agents", symbol: "person.2"),
        .init(route: .files, title: "Files", symbol: "folder"),
        .init(route: .settings, title: "Settings", symbol: "slider.horizontal.3")
    ]

    @Environment(WorkspaceStore.self) private var store
    @Namespace private var selection

    static func isTab(_ route: WorkspaceRoute) -> Bool { items.contains { $0.route == route } }
    static func isVisible(on route: WorkspaceRoute) -> Bool {
        !route.isAuthentication && ![WorkspaceRoute.chat, .search, .newChat, .createAgent, .editAgent,
                                    .createSchedule, .pair, .browser, .approval, .review].contains(route)
    }

    var body: some View {
        GlassEffectContainer {
            HStack(spacing: 0) {
                ForEach(Self.items) { item in
                    Button {
                        withAnimation(.smooth(duration: 0.22)) { store.selectTab(item.route) }
                    } label: {
                        VStack(spacing: 5) {
                            BlotIcon(symbol: item.symbol, size: 23).font(.system(size: 20))
                            Text(store.t(item.title)).font(.caption2).lineLimit(1)
                        }
                        .frame(maxWidth: .infinity, minHeight: 50)
                        .foregroundStyle(store.tab == item.route ? WorkspaceStyle.ink : WorkspaceStyle.secondary)
                        .background {
                            if store.tab == item.route {
                                Capsule().fill(WorkspaceStyle.ink.opacity(0.08))
                                    .matchedGeometryEffect(id: "selected-tab", in: selection)
                            }
                        }
                        .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(store.tab == item.route ? .isSelected : [])
                    .accessibilityIdentifier("workspace.tab.\(item.route.rawValue)")
                }
            }
            .padding(5)
            .glassEffect(.regular.interactive(), in: .capsule)
        }
        .padding(.horizontal, 16).padding(.top, 2).padding(.bottom, 2)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(store.t("Main navigation"))
    }
}
