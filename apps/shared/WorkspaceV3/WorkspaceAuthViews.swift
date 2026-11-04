import BlotDesign
import BlotDomain
import SwiftUI

struct WorkspaceAuthView: View {
    let route: WorkspaceRoute
    @Environment(WorkspaceStore.self) private var store
    var body: some View {
        #if os(macOS)
        if route == .welcome { MacWelcomeView() }
        else if route == .firstRun {
            ScrollView { setup.padding(40).frame(maxWidth: 1060) }.frame(maxWidth: .infinity)
        } else {
            ScrollView { form.padding(40).frame(maxWidth: 440) }.frame(maxWidth: .infinity)
        }
        #else
        switch route {
        case .welcome: PhoneWelcomeView()
        case .signIn, .createAccount: PhoneAuthenticationView(initialRoute: route)
        case .firstAgent: PhoneFirstAgentView()
        default: ScrollView { form.padding(24).frame(maxWidth: 520) }.frame(maxWidth: .infinity)
        }
        #endif
    }
    @ViewBuilder private var form: some View {
        switch route {
        case .welcome:
            #if os(macOS)
            MacWelcomeView()
            #else
            PhoneWelcomeView()
            #endif
        case .firstAgent:
            #if os(macOS)
            MacAgentCreationView()
            #else
            PhoneFirstAgentView()
            #endif
        case .firstRun: setup
        case .verifyEmail: verification
        case .recovery: recovery
        default:
            #if os(macOS)
            credentials
            #else
            PhoneAuthenticationView(initialRoute: route)
            #endif
        }
    }
    #if os(macOS)
    private var credentials: some View {
        @Bindable var store = store
        let registering = route == .createAccount
        return VStack(alignment: .leading, spacing: 22) {
            WorkspaceAvatar(size: 60)
            WorkspaceHeading(title: registering ? "Let’s get started" : "Welcome back",
                subtitle: registering ? "One account for phone and computer." : "Sign in to continue with your team.")
            
            if registering { WorkspaceField(title: "Your name", text: $store.form.account.name) }
            WorkspaceField(title: "Email", text: $store.form.account.email)
                #if os(iOS)
                .textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.emailAddress)
                #endif
            WorkspaceField(title: "Password", text: $store.form.account.password, secure: true)
            if !registering {
                HStack { Spacer(); Button(store.t("Forgot password?")) { store.navigate(.recovery) }.buttonStyle(WorkspaceRowButtonStyle()).font(.footnote) }
            }
            WorkspaceFeedback()
            WorkspaceV3ActionButton(title: registering ? "Create account" : "Sign in", action: registering ? .register : .signIn, next: registering ? .verifyEmail : loginDestination)
            Button(store.t(registering ? "Have an account? Sign in" : "No account? Create one")) { store.navigate(registering ? .signIn : .createAccount) }
                .buttonStyle(WorkspaceRowButtonStyle()).frame(maxWidth: .infinity).font(.footnote)
            Text(store.t("By continuing, you accept the Terms and Privacy Policy.")).font(.caption).foregroundStyle(WorkspaceStyle.secondary).multilineTextAlignment(.center).frame(maxWidth: .infinity)
        }
    }
    private var loginDestination: WorkspaceRoute {
        #if os(macOS)
        .home
        #else
        .chats
        #endif
    }
    #endif
    private var verification: some View {
        @Bindable var store = store
        return VStack(alignment: .leading, spacing: 24) {
            BlotIcon(symbol: "envelope", size: 36).font(.largeTitle)
            WorkspaceHeading(title: "Check your email", subtitle: "Enter the 6-digit code from your email.")
            WorkspaceField(title: "Verification code", text: $store.form.account.code)
                .textContentType(.oneTimeCode)
                #if os(iOS)
                .keyboardType(.numberPad)
                #endif
            WorkspaceFeedback()
            WorkspaceV3ActionButton(title: "Verify", action: .verify, next: {
                #if os(macOS)
                .firstRun
                #else
                .firstAgent
                #endif
            }())
            WorkspaceV3ActionButton(title: "Resend code", action: .resendVerification, kind: .quiet)
            Button(store.t("Change email address")) { store.navigate(.createAccount) }.buttonStyle(WorkspaceRowButtonStyle())
        }.padding(.vertical, 70)
    }
    private var recovery: some View {
        @Bindable var store = store
        return VStack(alignment: .leading, spacing: 24) {
            WorkspaceHeading(title: "Reset password", subtitle: "We’ll send a recovery code to your email.")
            WorkspaceField(title: "Email", text: $store.form.account.email)
            WorkspaceFeedback()
            WorkspaceV3ActionButton(title: "Send recovery email", action: .recover)
            WorkspaceField(title: "Verification code", text: $store.form.account.code).textContentType(.oneTimeCode)
            WorkspaceField(title: "New password", text: $store.form.account.password, secure: true)
            WorkspaceV3ActionButton(title: "Reset password", action: .resetPassword)
        }
    }
    private var setup: some View {
        @Bindable var store = store
        return VStack(alignment: .leading, spacing: 30) {
            WorkspaceHeading(title: "Set up your workspace", subtitle: "Blot runs tasks on this computer. You decide what it can access.")
            WorkspaceCard {
                BlotLabel("Blot Workspace", symbol: "folder").font(.title2)
                Text("~/Documents/Blot Workspace").font(.system(.callout, design: .monospaced))
                Text(store.t("Agents only touch files inside the selected folder.")).foregroundStyle(WorkspaceStyle.secondary)
                WorkspaceV3ActionButton(title: "Choose folder", action: .saveSetting, kind: .secondary)
            }
            WorkspaceCard {
                BlotLabel(store.t("Ask first"), symbol: "checkmark.circle").font(.title2)
                Text(store.t("Blot shows changes and asks before anything significant.")).foregroundStyle(WorkspaceStyle.secondary)
            }
            Toggle(store.t("Keep working after the window closes"), isOn: $store.form.preferences.backgroundWork)
            WorkspaceFeedback()
            WorkspaceV3ActionButton(title: "Open Blot", action: .saveSetting, next: .home)
        }
    }
}
