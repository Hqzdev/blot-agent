import BlotAppleIntegrations
import BlotDesign
import BlotWorkspace
import SwiftUI
import WebKit
import QuickLook
#if os(macOS)
import AppKit
#else
import UIKit
#endif

#if os(macOS)
struct WorkspaceBrowserView: View {
    let controller: WorkspaceBrowserController
    var trailingTabInset: CGFloat = 0
    @Environment(WorkspaceStore.self) private var store
    @State private var address = ""
    @State private var closing: UUID?
    @State private var showsDownloads = false
    @State private var systemAuthentication = false
    @State private var preview: URL?
    @State private var pendingNavigation: (() throws -> Void)?
    @State private var navigationTab: UUID?
    @State private var menuVisible = false
    @FocusState private var addressFocused: Bool
    private var toolNavigation: WorkspacePanelNavigation { store.panelNavigations.navigation(for: controller.selectedTab) }
    private var showsBrowserToolbar: Bool {
        switch toolNavigation.path.last {
        case .page(.file), .fileChange, .changes: false
        default: true
        }
    }

    private var ru: Bool { store.language == "ru" }
    private func text(_ ru: String, _ en: String) -> String { self.ru ? ru : en }
    var body: some View {
        VStack(spacing: 0) {
            tabs
            if showsBrowserToolbar { toolbar }
            WorkspaceBrowserManualControl(controller: controller)
            Divider().opacity(0.45)
            NavigationStack { page }.id(controller.selectedID)
        }
        .environment(\.workspacePanelNavigation, toolNavigation)
        .workspacePanelControls()
        .background(WorkspaceStyle.canvas)
        .task(id: controller.activeSession) {
            if controller.sessionTabs.isEmpty { work { try controller.newTab() } }
            else if let tab = controller.selectedTab, !tab.isLive, tab.url != nil { work { try controller.select(tab.id) } }
        }
        .onChange(of: controller.selectedID, initial: true) { _, _ in address = controller.selectedTab?.url?.absoluteString ?? ""; menuVisible = false; showsDownloads = false; preview = nil; pendingNavigation = nil; closing = nil; systemAuthentication = false }
        .onChange(of: controller.tabs.map(\.id), initial: true) { _, ids in store.panelNavigations.retain(Set(ids)) }
        .onChange(of: toolNavigation.path) { _, path in
            if path.isEmpty, controller.selectedTab?.localPage != nil, let id = controller.selectedID {
                work { _ = try controller.openLocalPage("start", title: text("Новая вкладка", "New tab"), replacing: id) }
            }
        }
        .onChange(of: controller.selectedTab?.url) { _, url in address = url?.absoluteString ?? "" }
        .workspaceConfirmationDialog(text("Покинуть несохранённую форму?", "Leave the unsaved form?"), isPresented: Binding(get: { pendingNavigation != nil }, set: { if !$0 { pendingNavigation = nil } }), titleVisibility: .visible) {
            Button(text("Покинуть без сохранения", "Leave without saving"), role: .destructive) {
                if let action = pendingNavigation, let id = navigationTab, controller.selectedID == id {
                    controller.discardForm(id); pendingNavigation = nil; work(action)
                } else { pendingNavigation = nil }
            }
        }
        .workspaceConfirmationDialog(text("На странице есть несохранённая форма. Закрыть вкладку?", "This page has an unsaved form. Close the tab?"), isPresented: Binding(get: { closing != nil }, set: { if !$0 { closing = nil } }), titleVisibility: .visible) {
            Button(text("Закрыть без сохранения", "Close without saving"), role: .destructive) { if let id = closing { work { try controller.close(id, discard: true) } }; closing = nil }
        }
        .workspaceConfirmationDialog(text("Системный вход", "System sign-in"), isPresented: $systemAuthentication) {
            Button(text("Открыть внешний браузер", "Open external browser")) { openSystemAuthentication() }
            Button(text("Отмена", "Cancel"), role: .cancel) {}
        } message: { Text(text("Будет открыт браузер macOS/iOS только для этого входа. Его cookies не копируются в Ori.", "The system browser will open for this sign-in. Its cookies are not copied into Ori.")) }
        .workspaceConfirmationDialog(controller.dialog?.origin ?? "", isPresented: Binding(get: { controller.dialog != nil }, set: { if !$0 { controller.dialog?.finish(accepted: false) } })) {
            if let dialog = controller.dialog {
                if dialog.kind == .prompt { TextField(text("Ответ", "Response"), text: Binding(get: { dialog.input }, set: { dialog.input = $0 })) }
                if dialog.kind != .alert { Button(text("Отмена", "Cancel"), role: .cancel) { dialog.finish(accepted: false) } }
                Button("OK") { dialog.finish(accepted: true) }
            }
        } message: { Text(controller.dialog?.message ?? "") }
        .accessibilityIdentifier("workspace.browser")
    }
    private var page: some View {
        VStack(spacing: 0) {
            if let center = store.appleIntegrations?.interactions, let pending = center.pending, pending.kind == .confirmation {
                VStack(alignment: .leading, spacing: 8) {
                    Text(pending.title).font(.headline)
                    ScrollView { Text(pending.details).font(.caption).textSelection(.enabled) }.frame(maxHeight: 180)
                    HStack {
                        Button(text("Отклонить", "Deny")) { center.finish(pending.id, result: .success(.bool(false))) }
                        Spacer()
                        Button(text("Разрешить один раз", "Allow once")) { center.finish(pending.id, result: .success(.bool(true))) }
                    }
                }.padding(12).background(.regularMaterial)
            }
            if !toolNavigation.path.isEmpty { WorkspaceBrowserToolPage(navigation: toolNavigation) }
            else if let tab = controller.selectedTab {
                if tab.loading { ProgressView(value: tab.progress).progressViewStyle(.linear) }
                if let error = tab.error { Text(error).font(.caption).foregroundStyle(.secondary).padding(8).frame(maxWidth: .infinity, alignment: .leading) }
                if tab.authenticationURL != nil {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(text("Этот провайдер запрещает встроенный вход. Системный браузер использует отдельную сессию; вход не переносится в Ori автоматически.", "This provider blocks embedded sign-in. The system browser uses a separate session; sign-in does not automatically transfer to Ori.")).font(.caption)
                        Button(text("Выбрать системный браузер…", "Use system browser…")) { systemAuthentication = true }
                    }.padding(10)
                }
                if tab.isLive, let view = controller.webView(for: tab.id) {
                    WorkspaceWebSurface(view: view).id(tab.id).frame(maxWidth: .infinity, maxHeight: .infinity)
                        .overlay { WorkspaceBrowserAgentPointer(pointer: tab.agentPointer) }
                }
                else { empty }
            } else { empty }
            if let error = controller.error { Text(error).font(.caption).foregroundStyle(.red).padding(8) }
        }
        .workspacePanelSheet(isPresented: $showsDownloads) { downloads.frame(minWidth: 280, minHeight: 260).padding(20).quickLookPreview($preview) }
    }
    private var toolbar: some View {
        Group {
            #if os(iOS)
            VStack(spacing: 8) {
                HStack(spacing: 8) {
                    addressField
                    Button { controller.presented = false } label: { BlotIcon(symbol: "xmark").frame(width: 44, height: 44) }.buttonStyle(.plain).accessibilityLabel(text("Закрыть браузер", "Close browser"))
                }
                HStack(spacing: 8) { navigationButtons; Spacer(); downloadButton; browserMenuButton }
            }
            #else
            HStack(spacing: 8) { navigationButtons; addressField; downloadButton; browserMenuButton }
            #endif
        }.padding(.horizontal, 12).padding(.vertical, 10)
    }
    private var navigationButtons: some View {
        HStack(spacing: 0) {
            if controller.agentHasControl || controller.agentPaused {
                button(controller.agentPaused ? "play.fill" : "pause.fill", text(controller.agentPaused ? "Продолжить работу агента" : "Взять управление", controller.agentPaused ? "Resume agent" : "Take control")) {
                    if controller.agentPaused { controller.resumeAgent() } else { controller.pauseAgent() }
                }
            }
            button("chevron.left", text("Назад", "Back"), disabled: toolNavigation.dismissDetail == nil && toolNavigation.path.isEmpty && controller.selectedTab?.canGoBack != true) {
                if let dismiss = toolNavigation.dismissDetail { dismiss() }
                else if !toolNavigation.path.isEmpty { toolNavigation.path.removeLast() }
                else if let id = controller.selectedID { try controller.back(id) }
            }
            button("chevron.right", text("Вперёд", "Forward"), disabled: !toolNavigation.path.isEmpty || controller.selectedTab?.canGoForward != true) { if let id = controller.selectedID { try controller.back(id, forward: true) } }
            Rectangle().fill(WorkspaceStyle.secondary.opacity(0.2)).frame(width: 1, height: 16)
            button(controller.selectedTab?.loading == true ? "xmark" : "arrow.clockwise", text("Обновить или остановить", "Reload or stop"), disabled: controller.selectedTab?.url == nil) { if let id = controller.selectedID { try controller.reload(id) } }
        }.background(WorkspaceStyle.surface, in: Capsule())
    }
    private var addressField: some View {
        TextField(text("Поиск Google или адрес", "Search Google or enter a URL"), text: $address)
            .textFieldStyle(.plain).focused($addressFocused).onSubmit(openAddress)
            .padding(.horizontal, 14).frame(minWidth: 40, minHeight: 36)
            .background(WorkspaceStyle.surface, in: Capsule())
            .overlay(Capsule().strokeBorder(WorkspaceStyle.ink.opacity(addressFocused ? 0.3 : 0.08)))
            .accessibilityIdentifier("workspace.browser.address")
    }
    private var downloadButton: some View {
        button("arrow.down.to.line", text("Загрузки", "Downloads")) { showsDownloads = true }.background(WorkspaceStyle.surface, in: Circle())
    }
    private var browserMenuButton: some View {
        Button { menuVisible.toggle() } label: {
            BlotIcon(symbol: "ellipsis").frame(width: controlSize, height: controlSize).contentShape(Circle()).blotHover(in: Circle())
        }
            .buttonStyle(.plain).background(WorkspaceStyle.surface, in: Circle()).accessibilityLabel(text("Меню панели", "Panel menu"))
            .popover(isPresented: $menuVisible, arrowEdge: .bottom) { panelMenu }
    }
    private var controlSize: CGFloat {
        #if os(iOS)
        44
        #else
        34
        #endif
    }
    private var panelMenu: some View {
        MacActionMenuPanel {
            menuRow("plus", text("Новая вкладка", "New tab")) { work { try controller.newTab() } }
            ForEach(controller.profiles) { profile in
                menuRow(controller.selectedProfileID == profile.id ? "checkmark.circle" : "circle", profile.name) { work { try controller.selectProfile(profile.id) } }
            }
            menuRow("person.crop.circle.badge.plus", text("Новый профиль Ori", "New Ori profile")) { work { try controller.createProfile(name: text("Профиль", "Profile") + " \(controller.profiles.count + 1)") } }
            WorkspaceMenuGap()
            menuRow("square.grid.2x2", text("Все инструменты", "All tools")) { store.showTools() }
            menuRow("globe.badge.shield.half.filled", text("Доступ браузера", "Browser access")) { openTool(.page(.browserSettings)) }
            WorkspaceMenuGap()
            menuRow("desktopcomputer", text("Закрыть компьютер", "Close computer")) { controller.presented = false; if store.route == .browser { store.back() } }
        }
        .onExitCommand { menuVisible = false }
    }
    private func menuRow(_ symbol: String, _ title: String, action: @escaping () -> Void) -> some View {
        Button { menuVisible = false; action() } label: {
            BlotLabel(title, symbol: symbol)
        }.buttonStyle(MacMenuRowStyle())
    }
    private var tabs: some View {
        HStack(spacing: 6) {
            ScrollView(.horizontal) {
                LazyHStack(spacing: 6) {
                    ForEach(controller.sessionTabs) { tab in
                        HStack(spacing: 7) {
                            Button { work { try controller.select(tab.id) } } label: {
                                HStack(spacing: 7) {
                                    BlotIcon(tab.localPage.flatMap { WorkspaceToolDestination(identifier: $0) }?.glyph ?? .globe).foregroundStyle(WorkspaceStyle.secondary)
                                    Text(tabTitle(tab)).lineLimit(1)
                                }.frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                            }.buttonStyle(.plain).accessibilityAddTraits(controller.selectedID == tab.id ? .isSelected : [])
                            Button { do { try controller.close(tab.id) } catch WorkspaceBrowserError.unsavedChanges { closing = tab.id } catch { controller.error = error.localizedDescription } } label: {
                                BlotIcon(symbol: "xmark", size: 10).frame(width: 22, height: 26)
                                    .contentShape(Rectangle()).blotHover(in: Circle())
                            }
                                .buttonStyle(.plain).foregroundStyle(WorkspaceStyle.secondary).accessibilityLabel(text("Закрыть вкладку", "Close tab") + " " + tabTitle(tab))
                        }.font(.system(size: 12)).padding(.leading, 12).padding(.trailing, 4).frame(width: 166, height: 36)
                            .background(controller.selectedID == tab.id ? WorkspaceStyle.surface : .clear, in: RoundedRectangle(cornerRadius: 12))
                            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(WorkspaceStyle.ink.opacity(controller.selectedID == tab.id ? 0.08 : 0)))
                            .blotHover(in: RoundedRectangle(cornerRadius: 12))
                    }
                }.scrollTargetLayout()
            }
            .scrollPosition(id: Binding(get: { controller.selectedID }, set: { _ in }), anchor: .trailing)
            .scrollIndicators(.hidden)
            button("plus", text("Новая вкладка", "New tab")) { try controller.newTab() }
        }.frame(height: 44).padding(.horizontal, 12).padding(.trailing, trailingTabInset).padding(.top, 10).padding(.bottom, 2)
    }
    private func tabTitle(_ tab: BrowserTab) -> String {
        if tab.localPage == nil && tab.url == nil { return text("Новая вкладка", "New tab") }
        if let page = tab.localPage, WorkspaceChangesSource(identifier: page) != nil { return text("Изменения", "Changes") }
        return (tab.unsaved ? "• " : "") + tab.title
    }
    private var empty: some View { WorkspaceBrowserStartPage(controller: controller, select: openTool) }
    private func openTool(_ destination: WorkspaceToolDestination) {
        work {
            let blank = controller.selectedTab.flatMap { $0.url == nil && ($0.localPage == nil || $0.localPage == "start") ? $0.id : nil }
            let id = try controller.openLocalPage(destination.identifier, title: destination.title(russian: ru), replacing: blank)
            store.panelNavigations.reset(controller.tabs.first { $0.id == id }, to: destination)
        }
    }
    private var downloads: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack { Text(text("Загрузки", "Downloads")).font(.headline); Spacer(); Button(text("Закрыть", "Close")) { showsDownloads = false } }
            if controller.sessionDownloads.isEmpty { Text(text("Загрузок пока нет", "No downloads yet")).foregroundStyle(.secondary) }
            ScrollView {
                ForEach(controller.sessionDownloads) { item in
                    HStack {
                        VStack(alignment: .leading) { Text(item.name); Text(item.error ?? item.state).font(.caption).foregroundStyle(.secondary) }
                        Spacer()
                        if item.state == "running" { Button(text("Остановить", "Stop")) { controller.cancelDownload(item.id) } }
                        if item.state == "completed", let url = item.url {
                            Button(text("Просмотр", "Preview")) { preview = url }
                            ShareLink(item: url) { BlotIcon(symbol: "square.and.arrow.up") }
                        }
                    }.padding(.vertical, 6)
                }
            }
        }
    }
    private func openAddress() {
        work {
            let url = try WorkspaceBrowserURL.userNavigation(address)
            if let id = controller.selectedID { try controller.navigate(url.absoluteString, tabID: id) }
            else { _ = try controller.open(url.absoluteString) }
            toolNavigation.path.removeAll()
        }
    }
    private func work(_ action: @escaping () throws -> Void) {
        do { controller.error = nil; try action() }
        catch WorkspaceBrowserError.unsavedChanges { navigationTab = controller.selectedID; pendingNavigation = action }
        catch { controller.error = error.localizedDescription }
    }
    private func button(_ image: String, _ title: String, disabled: Bool = false, action: @escaping () throws -> Void) -> some View {
        Button { work(action) } label: {
            BlotIcon(symbol: image, size: 12).frame(width: 30, height: 34)
                .contentShape(Rectangle()).blotHover(in: Capsule())
        }.buttonStyle(.plain).disabled(disabled).accessibilityLabel(title)
    }
    private func openSystemAuthentication() {
        guard let url = controller.selectedTab?.authenticationURL, WorkspaceBrowserURL.isRestrictedAuthentication(url) else { return }
        #if os(macOS)
        NSWorkspace.shared.open(url)
        #else
        UIApplication.shared.open(url)
        #endif
    }
}

#if os(macOS)
private struct WorkspaceWebSurface: NSViewRepresentable {
    let view: WKWebView
    func makeNSView(context: Context) -> WKWebView { view }
    func updateNSView(_ nsView: WKWebView, context: Context) {}
}
#endif
#endif

#if os(iOS)
private struct PhoneWorkspaceBrowser: View {
    let controller: WorkspaceBrowserController
    @Environment(WorkspaceStore.self) private var store
    @State private var address = ""
    @State private var confirmDiscard = false
    @State private var discardAction: (() throws -> Void)?
    @FocusState private var editingAddress: Bool

    private func text(_ russian: String, _ english: String) -> String { store.language == "ru" ? russian : english }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Button { controller.presented = false; store.back() } label: { BlotIcon(symbol: "chevron.left").frame(minWidth: 44, minHeight: 44) }
                    .accessibilityLabel(text("Назад в чат", "Back to chat"))
                TextField(text("Адрес или поиск", "Address or search"), text: $address)
                    .textFieldStyle(.roundedBorder).textInputAutocapitalization(.never).autocorrectionDisabled()
                    .keyboardType(.URL).submitLabel(.go).focused($editingAddress).onSubmit(openAddress)
                    .accessibilityIdentifier("workspace.browser.address")
                browserMenu
            }.padding(.horizontal, 10)
            WorkspaceBrowserManualControl(controller: controller)
            if let tab = controller.selectedTab {
                if tab.loading { ProgressView(value: tab.progress).progressViewStyle(.linear) }
                if let error = controller.error ?? tab.error {
                    Text(error).font(.footnote).foregroundStyle(.secondary).padding(8)
                }
                if let url = tab.authenticationURL {
                    Button(text("Открыть системный браузер для входа", "Open system browser to sign in")) { UIApplication.shared.open(url) }
                        .font(.footnote).padding(8)
                }
                if tab.isLive, let view = controller.webView(for: tab.id) {
                    PhoneWorkspaceWebSurface(view: view).id(tab.id).frame(maxWidth: .infinity, maxHeight: .infinity)
                } else { emptyPage }
            } else { emptyPage }
        }
        .background(WorkspaceStyle.canvas)
        .task(id: controller.activeSession) {
            perform {
                if controller.selectedTab == nil { try controller.newTab() }
                else if let tab = controller.selectedTab, tab.url != nil, !tab.isLive { try controller.select(tab.id) }
            }
        }
        .onChange(of: controller.selectedID, initial: true) { _, _ in syncAddress() }
        .onChange(of: controller.selectedTab?.url) { _, _ in syncAddress() }
        .confirmationDialog(text("Покинуть несохранённую форму?", "Leave the unsaved form?"), isPresented: $confirmDiscard) {
            Button(text("Покинуть без сохранения", "Leave without saving"), role: .destructive) {
                if let action = discardAction { perform(action) }
                discardAction = nil
            }
            Button(text("Отмена", "Cancel"), role: .cancel) { discardAction = nil }
        }
        .alert(controller.dialog?.origin ?? "", isPresented: Binding(get: { controller.dialog != nil }, set: {
            if !$0 { controller.dialog?.finish(accepted: false) }
        })) {
            if let dialog = controller.dialog {
                if dialog.kind == .prompt { TextField(text("Ответ", "Response"), text: Binding(get: { dialog.input }, set: { dialog.input = $0 })) }
                if dialog.kind != .alert { Button(text("Отмена", "Cancel"), role: .cancel) { dialog.finish(accepted: false) } }
                Button("OK") { dialog.finish(accepted: true) }
            }
        } message: { Text(controller.dialog?.message ?? "") }
        .accessibilityIdentifier("workspace.browser")
    }

    private var emptyPage: some View {
        ContentUnavailableView(text("Откройте сайт", "Open a website"), systemImage: "globe",
            description: Text(text("Введите адрес в строку браузера.", "Enter a website address in the browser bar.")))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var browserMenu: some View {
        Menu {
            if controller.agentHasControl || controller.agentPaused {
                if controller.agentPaused {
                    Button(text("Продолжить работу агента", "Resume agent")) { controller.resumeAgent() }
                } else {
                    Button(text("Взять управление", "Take control")) { controller.pauseAgent() }
                }
            }
            if let tab = controller.selectedTab, tab.url != nil {
                Button(text("Назад по странице", "Go back a page")) { perform { try controller.back(tab.id) } }.disabled(!tab.canGoBack)
                Button(text("Обновить", "Reload")) { perform { try controller.reload(tab.id) } }
            }
            Section(text("Вкладки", "Tabs")) {
                ForEach(controller.sessionTabs) { tab in
                    Button { perform { try controller.select(tab.id) } } label: {
                        Label(tab.title, systemImage: controller.selectedID == tab.id ? "checkmark" : "globe")
                    }
                }
                Button(text("Новая вкладка", "New tab")) { perform { try controller.newTab() } }
                if let tab = controller.selectedTab {
                    Button(text("Закрыть вкладку", "Close tab"), role: .destructive) { close(tab) }
                }
            }
        } label: { BlotIcon(symbol: "ellipsis.circle").frame(minWidth: 44, minHeight: 44) }
            .accessibilityLabel(text("Меню браузера", "Browser menu"))
    }

    private func syncAddress() { address = controller.selectedTab?.url?.absoluteString ?? "" }

    private func openAddress() {
        editingAddress = false
        perform {
            let url = try WorkspaceBrowserURL.userNavigation(address)
            if let tab = controller.selectedTab {
                let navigate = { try controller.navigate(url.absoluteString, tabID: tab.id) }
                if tab.unsaved {
                    discardAction = { controller.discardForm(tab.id); try navigate() }
                    confirmDiscard = true
                } else { try navigate() }
            } else { _ = try controller.open(url.absoluteString) }
        }
    }

    private func close(_ tab: BrowserTab) {
        if tab.unsaved {
            discardAction = { try controller.close(tab.id, discard: true) }
            confirmDiscard = true
        } else { perform { try controller.close(tab.id) } }
    }

    private func perform(_ action: () throws -> Void) {
        do { controller.error = nil; try action() }
        catch { controller.error = error.localizedDescription }
    }
}

private struct PhoneWorkspaceWebSurface: UIViewRepresentable {
    let view: WKWebView
    func makeUIView(context: Context) -> WKWebView { view }
    func updateUIView(_ uiView: WKWebView, context: Context) {}
}
#endif

struct WorkspaceBrowserDestination: View {
    @Environment(WorkspaceStore.self) private var store
    var body: some View {
        #if os(iOS)
        if let browser = store.browser { PhoneWorkspaceBrowser(controller: browser) }
        else { ProgressView().task { store.ensureBrowser() } }
        #else
        if let browser = store.browser { WorkspaceBrowserView(controller: browser) }
        else { ProgressView().task { store.ensureBrowser() } }
        #endif
    }
}
