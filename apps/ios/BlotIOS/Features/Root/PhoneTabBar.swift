import BlotDesign
import SwiftUI

struct PhoneTabBar: View {
    private struct Item: Identifiable {
        let route: WorkspaceRoute
        let title: String
        let icon: BlotGlyph
        var id: WorkspaceRoute { route }
    }

    private static let items: [Item] = [
        .init(route: .chats, title: "Chats", icon: .chats),
        .init(route: .schedules, title: "Schedules", icon: .calendar),
        .init(route: .overview, title: "Overview", icon: .grid),
        .init(route: .settings, title: "Settings", icon: .settings)
    ]

    @Environment(WorkspaceStore.self) private var store
    @State private var availableWidth: CGFloat = 340
    @ScaledMetric(relativeTo: .subheadline) private var minimumLabeledWidth: CGFloat = 340

    static func isTab(_ route: WorkspaceRoute) -> Bool { items.contains { $0.route == route } }

    static func isVisible(on route: WorkspaceRoute) -> Bool {
        !route.isAuthentication && ![WorkspaceRoute.chat, .search, .newChat, .createAgent, .editAgent,
                                    .createSchedule, .pair, .browser, .approval, .review, .connections].contains(route)
    }

    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.blotReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        bar
            .background { surface }
            .padding(.horizontal, 16).padding(.vertical, 2)
            .accessibilityElement(children: .contain)
            .accessibilityLabel(store.t("Main navigation"))
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { availableWidth = $0 }
    }

    @ViewBuilder private var surface: some View {
        if reduceTransparency || ![WorkspaceRoute.chats, .home].contains(store.route) {
            RoundedRectangle(cornerRadius: 28).fill(BlotColor.panel)
                .overlay { RoundedRectangle(cornerRadius: 28).strokeBorder(BlotColor.hairline) }
        } else {
            Color.clear.glassEffect(.regular, in: .rect(cornerRadius: 28))
        }
    }

    private var bar: some View {
        VStack(spacing: 6) {
            HStack(spacing: 4) {
                ForEach(Self.items) { item in tab(item) }
            }
            .backgroundPreferenceValue(PhoneTabSelectionBounds.self) { anchor in
                GeometryReader { geometry in
                    PhoneTabSelectionIndicator(
                        target: anchor.map { geometry[$0] } ?? .zero,
                        color: BlotColor.inverse.opacity(reduceTransparency ? 1 : 0.88),
                        reduceMotion: reduceMotion || systemReduceMotion
                    )
                }
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            }
            if !showsInlineTitle,
               let selected = Self.items.first(where: { $0.route == store.tab }) {
                Text(store.t(selected.title)).font(.body).multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 12).padding(.bottom, 6).accessibilityHidden(true)
            }
        }
        .padding(6).frame(maxWidth: .infinity)
    }

    private var showsInlineTitle: Bool { !dynamicTypeSize.isAccessibilitySize && availableWidth >= minimumLabeledWidth }

    private func tab(_ item: Item) -> some View {
        let selected = store.tab == item.route
        let showsTitle = showsInlineTitle && selected
        return Button {
            store.selectTab(item.route)
            store.navigation.activateTab(item.route)
        } label: {
            HStack(spacing: 9) {
                BlotIcon(item.icon, size: 22)
                if showsTitle {
                    Text(store.t(item.title)).font(.subheadline.weight(.medium))
                        .lineLimit(1).fixedSize(horizontal: true, vertical: false).transition(.opacity)
                }
            }
            .padding(.horizontal, showsTitle ? 14 : 0)
            .frame(minWidth: showsTitle ? 124 : 44,
                   maxWidth: showsTitle ? nil : .infinity, minHeight: 50)
            .foregroundStyle(selected ? BlotColor.onInverse : WorkspaceStyle.ink)
            .anchorPreference(key: PhoneTabSelectionBounds.self, value: .bounds) { selected ? $0 : nil }
            .contentShape(Capsule())
        }
        .layoutPriority(selected ? 1 : 0)
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(store.t(item.title))
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier("workspace.tab.\(item.route.rawValue)")
    }
}
