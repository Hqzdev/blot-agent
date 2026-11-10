import BlotDesign
import SwiftUI

struct PhoneFirstAgentView: View {
    @Environment(WorkspaceStore.self) private var store
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @AppStorage("blot.v3.reduceMotion") private var reduceMotion = false
    @State private var setup: PhoneFirstAgentSetup
    @FocusState private var nameFocused: Bool
    private let resourceBundle: Bundle

    init(setup: PhoneFirstAgentSetup? = nil, resourceBundle: Bundle = .main) {
        _setup = State(initialValue: setup ?? PhoneFirstAgentSetup())
        self.resourceBundle = resourceBundle
    }

    var body: some View {
        Group {
            if setup.step == .preparing { preparation }
            else {
                ScrollView {
                    VStack(spacing: 28) {
                        hero(size: setup.step == .introduction ? 112 : 132)
                            .padding(.top, 24)
                        heading
                        stepContent
                    }
                    .frame(maxWidth: 520).frame(maxWidth: .infinity)
                    .padding(.horizontal, 24).padding(.bottom, 24)
                }
                .scrollDismissesKeyboard(.interactively)
                .scrollBounceBehavior(.basedOnSize)
                .safeAreaInset(edge: .bottom, spacing: 0) { footer }
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) { backButton }
        .background(WorkspaceStyle.canvas.ignoresSafeArea())
        .environment(\.blotReduceMotion, reduceMotion)
        .interactiveDismissDisabled()
        .accessibilityIdentifier("onboarding.first-blot.\(setup.step)")
        .sensoryFeedback(.selection, trigger: setup.step)
        .sensoryFeedback(.selection, trigger: setup.draft.shape)
        .sensoryFeedback(.selection, trigger: setup.draft.color)
        .task(id: setup.step) {
            if setup.step == .name { nameFocused = true }
            if setup.step == .preparing { await setup.finish(using: store) }
        }
    }

    @ViewBuilder private var backButton: some View {
        if setup.step != .introduction {
            HStack {
                PhoneGlassCircleButton(symbol: "chevron.left", title: text("Back")) {
                    nameFocused = false
                    store.error = nil
                    withAnimation(transition) { setup.back() }
                }.disabled(setup.isSaving)
                Spacer()
            }
            .frame(height: 44).padding(.horizontal, 20).padding(.vertical, 8)
        }
    }

    private var heading: some View {
        VStack(spacing: 14) {
            Text(text(title)).font(.largeTitle.weight(.bold))
                .accessibilityAddTraits(.isHeader)
            Text(text(subtitle)).font(.body).foregroundStyle(WorkspaceStyle.secondary)
        }
        .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
    }

    private var title: String {
        switch setup.step {
        case .introduction: "Meet your blot"
        case .name: "What’s your blot’s name?"
        case .appearance: "Make your blot yours"
        case .role: "Choose a role"
        case .preparing: "Setting up your blot"
        }
    }

    private var subtitle: String {
        switch setup.step {
        case .introduction: "Your AI companion for work and everyday life. Let’s create your first blot together."
        case .name: "Give it a name you like. You can change it later."
        case .appearance: "Choose its shape and color."
        case .role: "Start with a template or describe your own role. Your blot’s name and look stay the same."
        case .preparing: "This may take a moment."
        }
    }

    private func hero(size: CGFloat) -> some View {
        WorkspaceAnimatedAvatar(shape: .init(rawValue: setup.draft.shape) ?? .cloud,
            color: WorkspaceAvatarView.color(setup.draft.color), size: size)
            .frame(height: size + 20)
            .animation(transition, value: setup.draft.shape)
            .animation(transition, value: setup.draft.color)
    }

    @ViewBuilder private var stepContent: some View {
        switch setup.step {
        case .introduction: introduction
        case .name:
            TextField(text("Blot name"), text: $setup.draft.name)
                .font(.title2.weight(.medium)).multilineTextAlignment(.center)
                .textInputAutocapitalization(.words).submitLabel(.continue)
                .focused($nameFocused).onSubmit { next() }
                .padding(18).frame(minHeight: 56)
                .background(WorkspaceStyle.secondary.opacity(0.08), in: .rect(cornerRadius: 18))
                .accessibilityLabel(text("Blot name"))
                .accessibilityIdentifier("onboarding.first-blot.name")
        case .appearance: PhoneFirstAgentAppearancePicker(draft: $setup.draft, localize: text)
        case .role: roles
        case .preparing: EmptyView()
        }
    }

    private var introduction: some View {
        VStack(alignment: .leading, spacing: 26) {
            benefit("sparkle", "A little help with big ideas", "Think things through, plan your day, and work on projects together.")
            benefit("paintbrush", "A character of its own", "You choose the name, look, and role. Your blot grows with you.")
            benefit("checkmark.shield", "You’re in control", "Your blot asks before significant actions. Connect apps when you’re ready.")
        }.padding(.top, 12)
    }

    private func benefit(_ symbol: String, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 16) {
            BlotIcon(symbol: symbol, size: 23).foregroundStyle(.blue)
                .frame(width: 44, height: 44)
                .overlay { RoundedRectangle(cornerRadius: 14).strokeBorder(WorkspaceStyle.secondary.opacity(0.16)) }
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 5) {
                Text(text(title)).font(.headline)
                Text(text(detail)).font(.subheadline).foregroundStyle(WorkspaceStyle.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var roles: some View {
        VStack(spacing: 10) {
            ForEach(PhoneFirstAgentSetup.Role.allCases) { role in
                Button { setup.select(role, instructions: text(role.instructions)) } label: {
                    HStack(spacing: 14) {
                        VStack(alignment: .leading, spacing: 5) {
                            Text(text(role.title)).font(.headline)
                            if !role.summary.isEmpty {
                                Text(text(role.summary)).font(.subheadline)
                                    .foregroundStyle(WorkspaceStyle.secondary)
                            }
                        }.frame(maxWidth: .infinity, alignment: .leading)
                        BlotIcon(symbol: setup.selectedRole == role ? "checkmark.circle.fill" : "circle", size: 22)
                            .foregroundStyle(setup.selectedRole == role ? WorkspaceStyle.ink : WorkspaceStyle.secondary)
                    }
                    .padding(16).contentShape(.rect)
                    .background(WorkspaceStyle.secondary.opacity(setup.selectedRole == role ? 0.1 : 0.04),
                        in: .rect(cornerRadius: 18))
                }
                .buttonStyle(.plain).accessibilityAddTraits(setup.selectedRole == role ? .isSelected : [])
                .accessibilityIdentifier("onboarding.first-blot.role.\(role.rawValue)")
            }
            if setup.selectedRole == .custom {
                TextField(text("What should your blot help with?"), text: $setup.draft.instructions, axis: .vertical)
                    .lineLimit(3...8).padding(16)
                    .background(WorkspaceStyle.secondary.opacity(0.08), in: .rect(cornerRadius: 18))
                    .accessibilityLabel(text("Your own role"))
            }
        }
    }

    private var footer: some View {
        VStack(spacing: 4) {
            Button(action: next) {
                Text(text(setup.step == .role ? "Create blot" : "Continue"))
                    .font(.headline).frame(maxWidth: .infinity, minHeight: 24)
            }
            .buttonStyle(WorkspaceButtonStyle()).disabled(!setup.canContinue)
            .accessibilityIdentifier("onboarding.first-blot.continue")
            if setup.step == .role {
                Button(text("Skip")) {
                    nameFocused = false
                    withAnimation(transition) {
                        setup.skipRole(instructions: text(PhoneFirstAgentSetup.Role.assistant.instructions))
                    }
                }
                .font(.body).foregroundStyle(WorkspaceStyle.secondary)
                .frame(maxWidth: .infinity, minHeight: 44).buttonStyle(.plain)
                .accessibilityIdentifier("onboarding.first-blot.skip-role")
            }
        }
        .padding(.horizontal, 24).padding(.top, 12).padding(.bottom, 16)
        .background(WorkspaceStyle.canvas)
    }

    private var preparation: some View {
        VStack(spacing: 24) {
            Spacer(minLength: 24)
            hero(size: 128)
            Spacer(minLength: 24)
            VStack(spacing: 10) {
                Text(text(title)).font(.headline)
                Text(text(subtitle)).font(.subheadline).foregroundStyle(WorkspaceStyle.secondary)
                if setup.isSaving { ProgressView().padding(.top, 8) }
                if store.error != nil {
                    WorkspaceFeedback().padding(.top, 12)
                    Button(text("Try again")) {
                        _Concurrency.Task { await setup.finish(using: store) }
                    }.buttonStyle(WorkspaceButtonStyle()).disabled(setup.isSaving)
                }
            }.multilineTextAlignment(.center).padding(.horizontal, 24).padding(.bottom, 28)
        }.frame(maxWidth: .infinity)
    }

    private func text(_ source: String) -> String {
        guard let path = resourceBundle.path(forResource: store.language, ofType: "lproj"),
              let bundle = Bundle(path: path) else { return store.t(source) }
        return bundle.localizedString(forKey: source, value: store.t(source), table: "FirstAgent")
    }

    private var transition: Animation? {
        systemReduceMotion || reduceMotion ? nil : .easeInOut(duration: 0.25)
    }

    private func next() {
        guard setup.canContinue else { return }
        nameFocused = false
        withAnimation(transition) { setup.advance() }
    }
}
