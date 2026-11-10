import BlotAppleIntegrations
import BlotDesign
import BlotWorkspace
import SwiftUI
import WebKit
import QuickLook
#if os(macOS)
import AppKit
#endif

struct WorkspaceBrowserView: View {
    let controller: WorkspaceBrowserController
    var compact = false
    @Environment(WorkspaceStore.self) private var store
    @State private var address = ""
    @State private var closing: UUID?
    @State private var showsDownloads = false
    @State private var systemAuthentication = false
    @State private var preview: URL?
    @State private var pendingNavigation: (() throws -> Void)?
    @State private var navigationTab: UUID?
    private var ru: Bool { store.language == "ru" }
    private func text(_ ru: String, _ en: String) -> String { self.ru ? ru : en }
    var body: some View {
        VStack(spacing: 0) {
            toolbar
            if !controller.tabs.isEmpty { tabs }
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
            if let tab = controller.selectedTab {
                if tab.loading { ProgressView(value: tab.progress).progressViewStyle(.linear) }
                if let error = tab.error { Text(error).font(.caption).foregroundStyle(.secondary).padding(8).frame(maxWidth: .infinity, alignment: .leading) }
                if tab.authenticationURL != nil {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(text("Этот провайдер запрещает встроенный вход. Системный браузер использует отдельную сессию; вход не переносится в Blot автоматически.", "This provider blocks embedded sign-in. The system browser uses a separate session; sign-in does not automatically transfer to Blot.")).font(.caption)
                        Button(text("Выбрать системный браузер…", "Use system browser…")) { systemAuthentication = true }
                    }.padding(10)
                }
                if tab.isLive, let view = controller.webView(for: tab.id) { WorkspaceWebSurface(view: view).id(tab.id).frame(maxWidth: .infinity, maxHeight: .infinity) }
                else { empty }
            } else { empty }
            if let error = controller.error { Text(error).font(.caption).foregroundStyle(.red).padding(8) }
        }
        .background(WorkspaceStyle.canvas)
        .task { if let tab = controller.selectedTab, !tab.isLive, tab.url != nil { work { try controller.select(tab.id) } } }
        .onChange(of: controller.selectedID, initial: true) { _, _ in address = controller.selectedTab?.url?.absoluteString ?? "" }
        .onChange(of: controller.selectedTab?.url) { _, url in address = url?.absoluteString ?? "" }
        .sheet(isPresented: $showsDownloads) { downloads.frame(minWidth: 300, minHeight: 260).padding(20).quickLookPreview($preview) }
        .confirmationDialog(text("Покинуть несохранённую форму?", "Leave the unsaved form?"), isPresented: Binding(get: { pendingNavigation != nil }, set: { if !$0 { pendingNavigation = nil } }), titleVisibility: .visible) {
            Button(text("Покинуть без сохранения", "Leave without saving"), role: .destructive) {
                if let action = pendingNavigation, let id = navigationTab, controller.selectedID == id {
                    controller.discardForm(id); pendingNavigation = nil; work(action)
                } else { pendingNavigation = nil }
            }
        }
        .confirmationDialog(text("На странице есть несохранённая форма. Закрыть вкладку?", "This page has an unsaved form. Close the tab?"), isPresented: Binding(get: { closing != nil }, set: { if !$0 { closing = nil } }), titleVisibility: .visible) {
            Button(text("Закрыть без сохранения", "Close without saving"), role: .destructive) { if let id = closing { work { try controller.close(id, discard: true) } }; closing = nil }
        }
        .alert(text("Системный вход", "System sign-in"), isPresented: $systemAuthentication) {
            Button(text("Открыть внешний браузер", "Open external browser")) { openSystemAuthentication() }
            Button(text("Отмена", "Cancel"), role: .cancel) {}
        } message: { Text(text("Будет открыт браузер macOS/iOS только для этого входа. Его cookies не копируются в Blot.", "The system browser will open for this sign-in. Its cookies are not copied into Blot.")) }
        .alert(controller.dialog?.origin ?? "", isPresented: Binding(get: { controller.dialog != nil }, set: { if !$0 { controller.dialog?.finish(accepted: false) } })) {
            if let dialog = controller.dialog {
                if dialog.kind == .prompt { TextField(text("Ответ", "Response"), text: Binding(get: { dialog.input }, set: { dialog.input = $0 })) }
                if dialog.kind != .alert { Button(text("Отмена", "Cancel"), role: .cancel) { dialog.finish(accepted: false) } }
                Button("OK") { dialog.finish(accepted: true) }
            }
        } message: { Text(controller.dialog?.message ?? "") }
        .accessibilityIdentifier("workspace.browser")
    }
    private var toolbar: some View {
        HStack(spacing: 8) {
            button("chevron.left", text("Назад", "Back"), disabled: controller.selectedTab?.canGoBack != true) { if let id = controller.selectedID { try controller.back(id) } }
            button("chevron.right", text("Вперёд", "Forward"), disabled: controller.selectedTab?.canGoForward != true) { if let id = controller.selectedID { try controller.back(id, forward: true) } }
            TextField(text("Адрес сайта", "Website address"), text: $address).textFieldStyle(.roundedBorder).onSubmit(openAddress)
                .accessibilityIdentifier("workspace.browser.address")
            button(controller.selectedTab?.loading == true ? "xmark" : "arrow.clockwise", text("Обновить или остановить", "Reload or stop")) { if let id = controller.selectedID { try controller.reload(id) } }
            Menu {
                Button(text("Новая вкладка", "New tab")) { work { try controller.newTab() }; address = "" }
                Button(text("Загрузки", "Downloads")) { showsDownloads = true }
                Button(text("Доступ агентов", "Agent access")) { controller.presented = false; store.navigate(.browserSettings) }
                if compact { Button(text("Развернуть", "Expand")) { controller.presented = false; store.navigate(.browser) } }
            } label: { Image(systemName: "ellipsis") }.menuStyle(.borderlessButton)
            button("xmark", text("Вернуться к чату", "Return to chat")) {
                controller.presented = false
                if store.route == .browser { store.back() }
            }
        }.padding(10)
    }
    private var tabs: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 6) {
                ForEach(controller.tabs) { tab in
                    HStack(spacing: 6) {
                        Button { work { try controller.select(tab.id) } } label: {
                            Text((tab.unsaved ? "• " : "") + tab.title).lineLimit(1).frame(maxWidth: 160)
                        }.buttonStyle(.plain)
                        Button { do { try controller.close(tab.id) } catch WorkspaceBrowserError.unsavedChanges { closing = tab.id } catch { controller.error = error.localizedDescription } } label: { Image(systemName: "xmark").font(.caption2) }.buttonStyle(.plain).accessibilityLabel(text("Закрыть вкладку", "Close tab"))
                    }.padding(.horizontal, 10).padding(.vertical, 7).background(controller.selectedID == tab.id ? WorkspaceStyle.surface : .clear, in: RoundedRectangle(cornerRadius: 8))
                }
            }.padding(.horizontal, 10)
        }.scrollIndicators(.hidden)
    }
    private var empty: some View {
        ContentUnavailableView(text("Браузер Blot", "Blot browser"), systemImage: "globe", description: Text(text("Введите адрес сайта. Страница откроется внутри приложения.", "Enter a website address to open it inside the app.")))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    private var downloads: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack { Text(text("Загрузки", "Downloads")).font(.headline); Spacer(); Button(text("Закрыть", "Close")) { showsDownloads = false } }
            if controller.downloads.isEmpty { Text(text("Загрузок пока нет", "No downloads yet")).foregroundStyle(.secondary) }
            ScrollView {
                ForEach(controller.downloads) { item in
                    HStack {
                        VStack(alignment: .leading) { Text(item.name); Text(item.error ?? item.state).font(.caption).foregroundStyle(.secondary) }
                        Spacer()
                        if item.state == "running" { Button(text("Остановить", "Stop")) { controller.cancelDownload(item.id) } }
                        if item.state == "completed", let url = item.url {
                            Button(text("Просмотр", "Preview")) { preview = url }
                            ShareLink(item: url) { Image(systemName: "square.and.arrow.up") }
                        }
                    }.padding(.vertical, 6)
                }
            }
        }
    }
    private func openAddress() {
        work {
            if let id = controller.selectedID { try controller.navigate(address, tabID: id) }
            else { _ = try controller.open(address) }
        }
    }
    private func work(_ action: @escaping () throws -> Void) {
        do { controller.error = nil; try action() }
        catch WorkspaceBrowserError.unsavedChanges { navigationTab = controller.selectedID; pendingNavigation = action }
        catch { controller.error = error.localizedDescription }
    }
    private func button(_ image: String, _ title: String, disabled: Bool = false, action: @escaping () throws -> Void) -> some View {
        Button { work(action) } label: { Image(systemName: image).frame(width: 22, height: 24) }.buttonStyle(.plain).disabled(disabled).accessibilityLabel(title)
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
#else
private struct WorkspaceWebSurface: UIViewRepresentable {
    let view: WKWebView
    func makeUIView(context: Context) -> WKWebView { view }
    func updateUIView(_ uiView: WKWebView, context: Context) {}
}
#endif

struct WorkspaceBrowserDestination: View {
    @Environment(WorkspaceStore.self) private var store
    var body: some View {
        if let browser = store.browser { WorkspaceBrowserView(controller: browser) }
        else { ProgressView().task { store.ensureBrowser() } }
    }
}
