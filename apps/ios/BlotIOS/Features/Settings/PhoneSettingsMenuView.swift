import BlotDesign
import Foundation
import SwiftUI

struct PhoneSettingsMenuView: View {
    private struct Item: Identifiable {
        let route: WorkspaceRoute
        let title: String
        let symbol: String
        var id: WorkspaceRoute { route }
    }

    private static let assistant: [Item] = [
        .init(route: .models, title: "AI models", symbol: "cpu"),
        .init(route: .personalization, title: "Personalization", symbol: "sliders"),
        .init(route: .usage, title: "Usage", symbol: "tablecells"),
        .init(route: .connections, title: "Connections", symbol: "puzzlepiece.extension")
    ]
    private static let workspace: [Item] = [
        .init(route: .schedules, title: "Schedules", symbol: "calendar"),
        .init(route: .devices, title: "Computers", symbol: "desktopcomputer")
    ]

    @Environment(WorkspaceStore.self) private var store
    @AppStorage(ThemeStore.defaultsKey) private var theme: ThemePreference = .system
    @State private var editingEmail = false
    @AppStorage("blot.v3.reduceMotion") private var reduceMotion = false

    var body: some View {
        @Bindable var store = store
        ScrollView {
            VStack(spacing: 28) {
                profile.padding(.vertical, 12)
                if !store.unresolvedConflicts.isEmpty {
                    Button { store.conflictsVisible = true } label: {
                        PhoneSettingsRow(title: "Review conflicting changes", symbol: "arrow.triangle.branch")
                    }.buttonStyle(.plain)
                }
                PhoneSettingsGroup(title: "Configure Blot Agent") { links(Self.assistant) }
                PhoneSettingsGroup(title: "Workspace") { links(Self.workspace) }
                PhoneSettingsGroup(title: "Account") {
                    Button { editingEmail = true } label: {
                        PhoneSettingsRow(title: "Email", symbol: "envelope",
                            detail: store.form.account.email.isEmpty ? store.t("Not specified") : store.form.account.email)
                    }.buttonStyle(.plain)
                    PhoneSettingsDivider()
                    link(.init(route: .account, title: "Security and sign-in", symbol: "lock"))
                }
                PhoneSettingsGroup(title: "App preferences") {
                    preferenceRow("Appearance", symbol: "sun.max") {
                        Picker(store.t("Appearance"), selection: $theme) {
                            ForEach(ThemePreference.allCases) { option in Text(store.t(option.title)).tag(option) }
                        }.labelsHidden().pickerStyle(.menu).tint(WorkspaceStyle.secondary)
                    }
                    PhoneSettingsDivider()
                    preferenceRow("Language", symbol: "character.bubble") {
                        Picker(store.t("Language"), selection: $store.language) {
                            Text("Русский").tag("ru")
                            Text("English").tag("en")
                        }.labelsHidden().pickerStyle(.menu).tint(WorkspaceStyle.secondary)
                    }
                    PhoneSettingsDivider()
                    link(.init(route: .notifications, title: "Notifications", symbol: "bell"))
                    PhoneSettingsDivider()
                    preferenceRow("Motion", symbol: "sparkle") {
                        Picker(store.t("Motion"), selection: $reduceMotion) {
                            Text(store.t("Full motion")).tag(false)
                            Text(store.t("Reduced motion")).tag(true)
                        }.labelsHidden().pickerStyle(.menu).tint(WorkspaceStyle.secondary)
                    }
                }
                PhoneSettingsGroup(title: "Privacy and access") {
                    link(.init(route: .permissions, title: "Access and permissions", symbol: "checkmark.shield"))
                }
                Button { store.signOut() } label: {
                    PhoneSettingsRow(title: "Sign out", symbol: "rectangle.portrait.and.arrow.right", showsChevron: false)
                        .foregroundStyle(.red)
                }
                .buttonStyle(.plain).frame(maxWidth: .infinity)
                .background(PhoneSettingsStyle.row, in: RoundedRectangle(cornerRadius: 28))
                Text("Blot Agent · " + (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"))
                    .font(.footnote).foregroundStyle(WorkspaceStyle.secondary)
            }.padding(.horizontal, 20).padding(.top, 12).padding(.bottom, 28)
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            if !store.history.isEmpty {
                HStack {
                    PhoneGlassCircleButton(symbol: "chevron.left", title: store.t("Back")) { store.back() }
                    Spacer()
                }.padding(.horizontal, 18).padding(.top, 6)
            }
        }
        .scrollPosition(store.navigation.position(for: .settings))
        .onAppear { store.navigation.restorePosition(for: .settings) }
        .onScrollGeometryChange(for: CGFloat.self) { max(0, $0.contentOffset.y + $0.contentInsets.top) } action: { old, new in
            if abs(old - new) > 0.5 { store.navigation.recordOffset(new, for: .settings) }
        }
        .background(PhoneSettingsStyle.canvas.ignoresSafeArea())
        .sheet(isPresented: $editingEmail) { PhoneEmailEditor().environment(store).presentationDetents([.medium]) }
        .accessibilityLabel(store.t("Settings"))
    }

    private var profile: some View {
        Button { store.profileEditorVisible = true } label: {
            VStack(spacing: 10) {
                PhoneProfileAvatar(data: store.profile.avatar, size: 76)
                    .overlay(alignment: .bottomTrailing) {
                        BlotIcon(.compose, size: 12).frame(width: 26, height: 26)
                            .background(PhoneSettingsStyle.row, in: Circle())
                            .overlay(Circle().strokeBorder(PhoneSettingsStyle.canvas, lineWidth: 2))
                    }
                Text(store.profileName).font(.title3.weight(.semibold)).lineLimit(2)
            }.frame(maxWidth: .infinity)
        }.buttonStyle(.plain).accessibilityLabel(store.t("Edit profile")).accessibilityValue(store.profileName)
    }

    private func links(_ items: [Item]) -> some View {
        ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
            if index > 0 { PhoneSettingsDivider() }
            link(item)
        }
    }

    private func link(_ item: Item) -> some View {
        Button { store.navigate(item.route) } label: { PhoneSettingsRow(title: item.title, symbol: item.symbol) }
            .buttonStyle(.plain).accessibilityIdentifier("workspace.settings.\(item.route.rawValue)")
    }

    private func preferenceRow<Control: View>(_ title: String, symbol: String, @ViewBuilder control: () -> Control) -> some View {
        HStack(spacing: 14) {
            BlotIcon(symbol: symbol, size: 22).frame(width: 24)
            Text(store.t(title)).font(.body)
            Spacer(minLength: 8)
            control()
        }.padding(.horizontal, 18).padding(.vertical, 8).frame(minHeight: 54)
    }
}
