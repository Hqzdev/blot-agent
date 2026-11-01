import BlotDesign
import SwiftUI

struct ProfileMenuButton: View {
    @Environment(AppState.self) private var app
    @State private var anchor = KMenuAnchor()
    @State private var isOpen = false
    @State private var sheet: ProfileSheet?

    var body: some View {
        Button(action: toggle) {
            InitialsAvatar(initials: app.profileDetails.initials, size: 24,
                           fill: K.profileAvatar, foreground: K.onInverse, bordered: false)
                .frame(width: 36, height: 36).kHover(radius: K.rMd, active: isOpen || app.profileVisible)
        }
        .buttonStyle(KIconButtonStyle()).kFocusRing(radius: K.rSm).help("Profile").accessibilityLabel("Open profile menu")
        .background(KMenuAnchorView(anchor: anchor))
        .onDisappear { if isOpen { KMenuController.shared.close() } }
        .onChange(of: app.shellDestination) { _, _ in
            if isOpen { KMenuController.shared.close() }
        }
        .sheet(item: $sheet) { ProfileSheetView(sheet: $0).environment(app) }
    }

    private func toggle() {
        guard !isOpen, let view = anchor.view, let window = view.window else {
            KMenuController.shared.close(); return
        }
        let rect = window.convertToScreen(view.convert(view.bounds, to: nil))
        isOpen = true
        let menu = ProfileMenuCard(action: perform).environment(app)
            .blotTheme(app.theme).tint(K.inverse)
        KMenuController.shared.showProfile(menu, beside: rect, in: window) { isOpen = false }
    }

    private func perform(_ action: ProfileMenuAction) {
        KMenuController.shared.close()
        switch action {
        case .profile: app.openProfile()
        case .usage: app.openProfileSettings(.billing)
        case .pet: app.openPet()
        case .settings: app.openProfileSettings(.general)
        case .shortcuts: app.openProfileSettings(.shortcuts)
        case .invitation: sheet = .invitation
        case .guide: sheet = .guide
        case .about: sheet = .about
        case .logOut: app.signOut()
        }
    }
}

struct ProfileMenuCard: View {
    @Environment(AppState.self) private var app
    let action: (ProfileMenuAction) -> Void
    @State private var showingHelp = false

    init(showingHelp: Bool = false, action: @escaping (ProfileMenuAction) -> Void) {
        self.action = action
        _showingHelp = State(initialValue: showingHelp)
    }

    var body: some View {
        VStack(spacing: 0) {
            if showingHelp { helpMenu } else { profileMenu }
        }
        .padding(6).frame(width: 232, height: 250)
        .kPopover()
    }

    private var profileMenu: some View {
        Group {
            Button { action(.profile) } label: {
                HStack(spacing: 6) {
                    InitialsAvatar(initials: app.profileDetails.initials, size: 18,
                                   fill: K.profileAvatar, foreground: K.onInverse, bordered: false)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(app.profileDetails.name).font(KFont.body()).foregroundStyle(K.text).lineLimit(1)
                        Text(app.currentUser?.email ?? "View profile").font(KFont.caption()).foregroundStyle(K.text3)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                }.padding(.horizontal, 4).frame(height: 40).contentShape(Rectangle())
            }.buttonStyle(KIconButtonStyle()).kFocusRing(radius: K.rSm).help("View profile")
            separator
            row("Usage", icon: "gauge") { action(.usage) }
            row("Show Pet", icon: "blot", detail: "⌥Space") { action(.pet) }
            row("Invite a friend", icon: "paperplane") { action(.invitation) }
            row("Settings", icon: "gearshape", detail: "⌘,") { action(.settings) }
            separator
            row("Help", icon: "lifepreserver", submenu: true) { showingHelp = true }
            row("Log out", icon: "log-out") { action(.logOut) }
        }
    }

    private var helpMenu: some View {
        Group {
            HStack(spacing: 8) {
                KIcon("lifepreserver", size: 18, color: K.text2)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Help").font(KFont.body()).foregroundStyle(K.text)
                    Text("Using Blot").font(KFont.caption()).foregroundStyle(K.text3)
                }
                Spacer()
            }.padding(.horizontal, 6).frame(height: 40)
            separator
            row("Getting started", icon: "book") { action(.guide) }
            row("Keyboard shortcuts", icon: "keyboard") { action(.shortcuts) }
            row("About Blot", icon: "info.circle") { action(.about) }
            Spacer(minLength: 0)
            separator
            row("Back to profile", icon: "chevron-left") { showingHelp = false }
        }
    }

    private var separator: some View { HDivider().padding(.horizontal, 4).padding(.vertical, 4) }

    private func row(_ title: String, icon: String, detail: String? = nil, submenu: Bool = false,
                     perform: @escaping () -> Void) -> some View {
        Button(action: perform) {
            HStack(spacing: 8) {
                if icon == "blot" {
                    BlotDrawing(role: .blot, framing: .avatar).frame(width: 14, height: 14)
                } else {
                    KIcon(icon, size: 14, color: K.text2)
                }
                Text(title).font(KFont.ui(13)).foregroundStyle(K.text).lineLimit(1)
                Spacer(minLength: 0)
                if let detail { Text(detail).font(KFont.caption()).foregroundStyle(K.text3).fixedSize() }
                if submenu { KIcon("chevron-right", size: 12, color: K.text3) }
            }.padding(.horizontal, 8).frame(height: 30).contentShape(Rectangle()).kHover(radius: K.rMd)
        }.buttonStyle(KIconButtonStyle()).kFocusRing(radius: K.rMd)
    }
}
