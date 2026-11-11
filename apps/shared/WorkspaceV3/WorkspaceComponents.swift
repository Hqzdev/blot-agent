import BlotDesign
import BlotDomain
import SwiftUI

struct WorkspaceCard<Content: View>: View {
    #if os(iOS)
    @Environment(\.phonePageTitle) private var pageTitle
    #endif
    var padding: CGFloat = 20
    var isButtonLabel = false
    @ViewBuilder let content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 16) { content }.frame(maxWidth: .infinity, alignment: .leading).padding(padding)
            .background(background, in: RoundedRectangle(cornerRadius: radius))
            .overlay {
                #if os(iOS)
                if pageTitle != nil {
                    RoundedRectangle(cornerRadius: radius).strokeBorder(PhoneSettingsStyle.edge)
                }
                #endif
            }
    }
    private var radius: CGFloat {
        #if os(iOS)
        pageTitle != nil ? PhonePageLayout.radius : WorkspaceStyle.radius
        #else
        WorkspaceStyle.radius
        #endif
    }
    private var background: Color {
        #if os(iOS)
        pageTitle != nil ? PhoneSettingsStyle.row : isButtonLabel ? .clear : WorkspaceStyle.surface
        #else
        WorkspaceStyle.surface
        #endif
    }
}

struct WorkspaceHeading: View {
    let title: String
    var subtitle: String = ""
    @Environment(WorkspaceStore.self) private var store
    #if os(iOS)
    @Environment(\.phonePageTitle) private var pageTitle
    #endif
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            #if os(macOS)
            Text(store.t(title)).font(.system(size: 24, weight: .medium)).accessibilityAddTraits(.isHeader)
            #else
            if pageTitle != store.t(title) {
                Text(store.t(title)).font(pageTitle == nil ? .largeTitle : .title3.weight(.semibold))
                    .accessibilityAddTraits(.isHeader)
            }
            #endif
            if !subtitle.isEmpty { Text(store.t(subtitle)).foregroundStyle(WorkspaceStyle.secondary).fixedSize(horizontal: false, vertical: true) }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct WorkspaceV3ActionButton: View {
    let title: String
    let action: WorkspaceAction
    var next: WorkspaceRoute?
    var kind: WorkspaceButtonStyle.Kind = .primary
    @Environment(WorkspaceStore.self) private var store
    @Environment(\.workspacePanelNavigation) private var panelNavigation
    var body: some View {
        Button {
            _Concurrency.Task {
                await store.perform(action, next: panelNavigation == nil ? next : nil)
                if store.error == nil, let next, let panelNavigation { panelNavigation.open(next) }
            }
        } label: {
            HStack {
                if store.busy { ProgressView().controlSize(.small).tint(kind == .primary ? BlotColor.onInverse : WorkspaceStyle.ink) }
                Text(store.t(title)).frame(maxWidth: .infinity)
            }
        }.buttonStyle(WorkspaceButtonStyle(kind)).disabled(store.busy)
    }
}

struct WorkspaceLink: View {
    let title: String
    let route: WorkspaceRoute
    var symbol: String = "chevron.right"
    @Environment(WorkspaceStore.self) private var store
    @Environment(\.workspacePanelNavigation) private var panelNavigation
    var body: some View {
        Button { if let panelNavigation { panelNavigation.open(route) } else { store.navigate(route) } } label: {
            HStack(spacing: 14) {
                Text(store.t(title)).multilineTextAlignment(.leading)
                Spacer(minLength: 4)
                BlotIcon(symbol: symbol).foregroundStyle(WorkspaceStyle.secondary)
            }
            #if os(macOS)
            .frame(minHeight: 32)
            #else
            .frame(minHeight: 44)
            #endif
            .contentShape(Rectangle())
        }.buttonStyle(WorkspaceRowButtonStyle())
    }
}

struct WorkspaceField: View {
    @FocusState private var focused: Bool
    let title: String
    @Binding var text: String
    var secure = false
    var multiline = false
    @Environment(WorkspaceStore.self) private var store
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(store.t(title)).font(.subheadline).foregroundStyle(WorkspaceStyle.secondary)
            Group {
                if secure { SecureField(store.t(title), text: $text).textContentType(.password) }
                else if multiline { TextField(store.t(title), text: $text, axis: .vertical).lineLimit(4...8) }
                else { TextField(store.t(title), text: $text) }
            }.textFieldStyle(.plain).padding(14).frame(minHeight: 44)
                .workspaceInputSurface(cornerRadius: 12)
                .accessibilityLabel(store.t(title)).disabled(store.busy).focused($focused)
                .onChange(of: store.invalidField) { _, field in if field == title { focused = true } }
        }
    }
}

struct WorkspaceAvatarView: View {
    let agent: BlotV3.AgentProfile
    var size: CGFloat = 48
    var animated = false
    var body: some View {
        if animated {
            WorkspaceAnimatedAvatar(shape: .init(rawValue: agent.avatarShape) ?? .round, color: Self.color(agent.avatarColor), size: size)
        } else {
            WorkspaceAvatar(shape: .init(rawValue: agent.avatarShape) ?? .round, color: Self.color(agent.avatarColor), size: size)
        }
    }
    static func color(_ key: String) -> Color { WorkspaceAvatarPalette.color(key) }
}

struct WorkspaceFeedback: View {
    @Environment(WorkspaceStore.self) private var store
    var body: some View {
        if let error = store.error {
            BlotLabel(store.t(error), symbol: "exclamationmark.triangle")
                .font(.callout).foregroundStyle(.red).padding(12).frame(maxWidth: .infinity, alignment: .leading)
                .background(WorkspaceStyle.surface, in: RoundedRectangle(cornerRadius: WorkspaceStyle.radius, style: .continuous))
                .accessibilityIdentifier("workspace.error")
        }
        if let notice = store.notice { Text(store.t(notice)).font(.callout).foregroundStyle(WorkspaceStyle.secondary) }
    }
}

struct WorkspaceDataState: View {
    let state: WorkspaceStore.ScreenState
    @Environment(WorkspaceStore.self) private var store
    private var symbol: String {
        switch state { case .loading: "arrow.clockwise"; case .error: "exclamationmark.triangle"; case .offline: "laptopcomputer"; case .limit: "gauge"; case .unavailable: "lock"; case .unknown: "questionmark.circle"; default: "bubble.left.and.bubble.right" }
    }
    private var title: String {
        switch state {
        case .loading: "Connecting to your computer…"
        case .error: "Couldn’t reach the model"
        case .offline: "Your computer is offline"
        case .limit: "Daily model limit reached"
        case .unavailable: "This action is unavailable"
        case .unknown: "Outcome unknown"
        default: "Nothing here yet"
        }
    }
    var body: some View {
        WorkspaceCard {
            VStack(alignment: .leading, spacing: 18) {
                if state == .loading { ProgressView() } else { BlotIcon(symbol: symbol, size: 40).font(.largeTitle) }
                Text(store.t(title)).font(.title2)
                Text(store.t(state == .unknown ? "The result has not been confirmed. Check before retrying." :
                    state == .empty ? "Start a conversation or add an item to continue." : "Your input is saved. You can continue when the service is available."))
                    .foregroundStyle(WorkspaceStyle.secondary)
                if state == .error {
                    Button(store.t("Retry")) { store.screenState = .normal }.buttonStyle(WorkspaceButtonStyle(.secondary))
                }
                if state == .offline { WorkspaceLink(title: "Choose computer", route: .devices) }
                if state == .limit { WorkspaceLink(title: "AI models", route: .models) }
            }
        }.accessibilityElement(children: .contain)
    }
}

struct WorkspaceComposer: View {
    var body: some View {
        #if os(iOS)
        PhoneConversationComposer()
        #else
        MacWorkspaceComposer()
        #endif
    }
}
