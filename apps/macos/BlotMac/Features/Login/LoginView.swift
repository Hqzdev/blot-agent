//
//  LoginView.swift
//  BlotMac
//
//  Auth flow from agent.pen: «09 · Sign up», «10 · Log in», «11 · Verify email».
//  360 pt column centred in the window, footer links at the bottom.
//

import BlotDesign
import SwiftUI
import BlotAPI

@MainActor
struct LoginView: View {
    @Environment(AppState.self) private var state
    @State private var model: LoginViewModel
    @State private var showSMTP = false
    @State private var emailManaged: Bool?
    @State private var setupError: String?
    @State private var checkingSetup = false

    init(model: LoginViewModel? = nil) {
        _model = State(initialValue: model ?? LoginViewModel(lastEmail: SessionStore.lastEmail))
    }

    var body: some View {
        VStack(spacing: 0) {
            // Title bar: the system draws the traffic lights here.
            Color.clear.frame(height: K.shellToolbarHeight)

            GeometryReader { proxy in
                ScrollView {
                    Group {
                        switch model.screen {
                        case .signUp: SignUpForm(model: model)
                        case .logIn: LogInForm(model: model)
                        case .verify: VerifyEmailForm(model: model)
                        case .reset: ResetPasswordForm(model: model)
                        }
                    }
                    .frame(width: 360)
                    .padding(.bottom, 40)
                    .frame(maxWidth: .infinity, minHeight: proxy.size.height)
                    .transition(.kAppear)
                    .id(model.screen)
                }
                .scrollIndicators(.never)
            }

            VStack(spacing: KSpace.md) {
                if let setupError {
                    HStack(alignment: .top, spacing: KSpace.md) {
                        InlineFeedback(text: "Blot could not reach its server on this Mac. \(setupError)", tone: .error)
                            .textSelection(.enabled)
                        KButton(title: "Try again", icon: "rotate-ccw", height: 28, loading: checkingSetup) {
                            Task { await checkSetup() }
                        }
                    }
                    .frame(maxWidth: 520)
                    .transition(.kAppear)
                }
                if emailManaged == false {
                    HStack(spacing: KSpace.sm) {
                        KIcon("mail", size: 14, color: K.text3)
                        Text("Verification emails need an SMTP account.").font(KFont.ui(13)).foregroundStyle(K.text3)
                        TextLink(title: "Set up email delivery…", color: K.text, weight: .medium) { showSMTP = true }
                    }
                }
            }
            .padding(.horizontal, KSpace.xl).padding(.bottom, KSpace.xl)
            .animation(.default, value: setupError)
        }
        .background(K.bg)
        .ignoresSafeArea()
        .sheet(isPresented: $showSMTP) { SMTPSetupView() }
        .task { await checkSetup() }
        .onChange(of: model.signedInUser) { _, user in
            guard let user else { return }
            state.signIn(user, remember: model.staySignedIn)
        }
    }

    private func checkSetup() async {
        checkingSetup = true
        defer { checkingSetup = false }
        do {
            try await BackendRuntime.shared.start()
            let setup = try await BackendRuntime.shared.client.get("v2/setup/status", as: InstallationSetup.self)
            emailManaged = setup.emailManaged
            setupError = nil
        } catch { setupError = error.localizedDescription }
    }
}

// MARK: - Screens

private struct SignUpForm: View {
    @Bindable var model: LoginViewModel

    var body: some View {
        VStack(spacing: 24) {
            AuthHeading(
                title: "Create your Blot account",
                subtitle: "An agent that plans, edits and tests code right on your Mac."
            )

            VStack(spacing: 12) {
                AuthField(label: "Email", icon: "envelope", placeholder: "you@example.com", text: $model.email,
                          autofocus: true, onSubmit: { model.sendCode() },
                          error: model.error == AuthError.invalidEmail.errorDescription ? model.error : nil)
                AuthField(label: "Password", icon: "lock", placeholder: "Create a password", text: $model.password,
                          secure: true, onSubmit: { model.sendCode() }, hint: "Use at least 12 characters.")
                AuthErrorText(message: model.error)
                PrimaryAuthButton(title: "Continue with email", loading: model.isLoading,
                                  action: { model.sendCode() })
            }

            Text("By continuing you agree to the Terms of Service and Privacy Policy. We'll send a 6-digit code to confirm your email.")
                .font(KFont.body())
                .foregroundStyle(K.text3)
                .multilineTextAlignment(.center)
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)

            SwitchPrompt(question: "Already have an account?", link: "Log in") { model.show(.logIn) }
        }
    }
}

private struct LogInForm: View {
    @Bindable var model: LoginViewModel

    var body: some View {
        VStack(spacing: 24) {
            AuthHeading(
                title: "Welcome back",
                subtitle: "Log in to pick up your tasks where Blot left off."
            )

            VStack(spacing: 12) {
                AuthField(label: "Email", icon: "envelope", placeholder: "you@example.com", text: $model.email,
                          autofocus: model.email.isEmpty, onSubmit: { model.logIn() },
                          error: model.error == AuthError.invalidEmail.errorDescription ? model.error : nil)
                AuthField(label: "Password", icon: "lock", placeholder: "Password", text: $model.password,
                          secure: true, autofocus: !model.email.isEmpty, onSubmit: { model.logIn() },
                          trailingLink: ("Forgot password?", { model.requestPasswordReset() }),
                          error: model.error == AuthError.emptyPassword.errorDescription || model.error == AuthError.wrongCredentials.errorDescription ? model.error : nil)

                HStack(spacing: 10) {
                    KToggle(isOn: $model.staySignedIn)
                        .accessibilityLabel("Stay signed in on this Mac")
                    Button { model.staySignedIn.toggle() } label: {
                        Text("Stay signed in on this Mac")
                            .font(KFont.body())
                            .foregroundStyle(K.text2)
                    }
                    .buttonStyle(KIconButtonStyle())
                    .focusable(false)
                    .accessibilityHidden(true)
                    Spacer()
                }
                .padding(.vertical, 2)
                .kAnimation(KMotion.quick, value: model.staySignedIn)

                AuthErrorText(message: model.error)
                PrimaryAuthButton(title: "Log in", loading: model.isLoading,
                                  action: { model.logIn() })
            }


            SwitchPrompt(question: "New to Blot?", link: "Create an account") { model.show(.signUp) }
        }
    }
}

private struct VerifyEmailForm: View {
    @Bindable var model: LoginViewModel

    var body: some View {
        VStack(spacing: 24) {
            AuthHeading(
                title: "Check your email",
                subtitle: "We sent a 6-digit code to \(model.email.isEmpty ? "your email" : model.email). It expires in 10 minutes."
            )

            VStack(spacing: 12) {
                CodeInput(code: $model.code, disabled: model.isLoading, invalid: model.error != nil)
                AuthErrorText(message: model.error)
            }

            PrimaryAuthButton(title: "Verify and continue", loading: model.isLoading,
                              enabled: model.canSubmitCode, action: { model.verify() })

            VStack(spacing: 8) {
                TextLink(
                    title: model.resendLabel,
                    color: model.resendSeconds > 0 ? K.text3 : K.text2,
                    action: { model.resendCode() }
                )
                .disabled(model.resendSeconds > 0)
                TextLink(title: "Use a different email", color: K.text, weight: .medium, action: { model.useDifferentEmail() })
            }
        }
    }
}

// MARK: - Pieces

/// The Blot arch: 56 × 64, top radius 28, 7 pt inner stroke, ember slot as the mouth.
struct BlotMark: View {
    var height: CGFloat = 64
    var body: some View {
        BlotDrawing(role: .blot)
            .frame(width: height, height: height)
            .accessibilityLabel("Blot")
    }
}

private struct AuthHeading: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(spacing: 24) {
            BlotMark()
            VStack(spacing: 8) {
                Text(title)
                    .font(KFont.pageTitle())
                    .foregroundStyle(K.text)
                Text(subtitle)
                    .font(KFont.body())
                    .foregroundStyle(K.text2)
                    .lineSpacing(6)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity)
        }
    }
}

private struct ResetPasswordForm: View {
    @Bindable var model: LoginViewModel
    var body: some View {
        VStack(spacing: 20) {
            AuthHeading(title: "Reset password", subtitle: "Enter the code from your email and a new password.")
            CodeInput(code: $model.code, disabled: model.isLoading, invalid: model.error != nil)
            AuthField(label: "New password", icon: "lock", placeholder: "New password", text: $model.password,
                      secure: true, onSubmit: { model.resetPassword() }, hint: "Use at least 12 characters.")
            AuthErrorText(message: model.error)
            PrimaryAuthButton(title: "Change password", loading: model.isLoading,
                              enabled: model.code.count == 6, action: { model.resetPassword() })
            TextLink(title: "Back to login", action: { model.show(.logIn) })
        }
    }
}

/// Auth form field: the shared «Text Field» at the large size.
private struct AuthField: View {
    let label: String
    let icon: String
    let placeholder: String
    @Binding var text: String
    var secure = false
    var autofocus = false
    var onSubmit: () -> Void = {}
    var trailingLink: (title: String, action: () -> Void)?
    var error: String?
    /// Requirement that must stay visible while typing (the placeholder disappears).
    var hint: String?

    var body: some View {
        // The error text is shown once under the form, so the field only turns red.
        KTextField(label, text: $text, placeholder: placeholder, icon: icon, secure: secure, large: true,
                   invalid: error != nil, hint: hint, autofocus: autofocus,
                   contentType: secure ? .password : .username,
                   trailingLink: trailingLink.map { FieldLink(title: $0.title, action: $0.action) },
                   onSubmit: onSubmit)
    }
}

/// Six digit boxes with a dash after the third, backed by one hidden text field.
private struct CodeInput: View {
    @Binding var code: String
    var disabled = false
    var invalid = false
    @FocusState private var focused: Bool

    var body: some View {
        ZStack {
            TextField("", text: $code)
                .textFieldStyle(.plain)
                .focused($focused)
                .frame(width: 1, height: 1)
                .opacity(0.01)
                .disabled(disabled)
                .accessibilityLabel("Verification code")

            HStack(spacing: 8) {
                ForEach(0..<LoginViewModel.codeLength, id: \.self) { index in
                    if index == 3 {
                        Text("–")
                            .font(KFont.ui(16))
                            .foregroundStyle(K.text3)
                    }
                    digitBox(index)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture { focused = true }
        }
        .onAppear { focused = true }
    }

    private func digitBox(_ index: Int) -> some View {
        let digits = Array(code)
        let active = focused && !disabled && index == min(digits.count, LoginViewModel.codeLength - 1)
        return ZStack {
            if index < digits.count {
                Text(String(digits[index]))
                    .font(KFont.ui(22, .medium))
                    .foregroundStyle(K.text)
                    .transition(.scale(scale: 0.8).combined(with: .opacity))
            } else if active {
                BlinkingCaret()
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 56)
        .background(RoundedRectangle(cornerRadius: K.rMd, style: .continuous).fill(K.bg))
        .overlay(
            RoundedRectangle(cornerRadius: K.rMd, style: .continuous)
                .strokeBorder(invalid ? K.danger : active ? K.focus : K.borderStrong, lineWidth: active ? 2 : 1)
        )
        .animation(KMotion.quick, value: code)
    }
}

private struct BlinkingCaret: View {
    @Environment(\.blotReduceMotion) private var reducedMotion
    var body: some View {
        TimelineView(.animation(minimumInterval: 0.53, paused: reducedMotion)) { context in
            let visible = reducedMotion || Int(context.date.timeIntervalSinceReferenceDate / 0.53) % 2 == 0
            Rectangle()
                .fill(K.text2)
                .frame(width: 1.5, height: 22)
                .opacity(visible ? 1 : 0)
        }
    }
}

private struct PrimaryAuthButton: View {
    let title: String
    var loading = false
    var enabled = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Text(title).opacity(loading ? 0 : 1)
                if loading {
                    ProgressView()
                        .controlSize(.small)
                }
            }
            .frame(maxWidth: .infinity)
        }
        // Sign-in is the one pill-shaped control in the system.
        .buttonStyle(BlotButtonStyle(.pill, size: .large, fullWidth: true))
        .kFocusRing(radius: K.controlHeightLarge / 2)
        .accessibilityLabel(loading ? "\(title), waiting" : title)
        .disabled(!enabled || loading)
    }
}

private struct AuthErrorText: View {
    let message: String?

    var body: some View {
        if let message {
            InlineFeedback(text: message, tone: .error)
                .frame(maxWidth: .infinity, alignment: .leading)
                .transition(.kAppear)
        }
    }
}

private struct SwitchPrompt: View {
    let question: String
    let link: String
    let action: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            Text(question)
                .font(KFont.body())
                .foregroundStyle(K.text2)
            TextLink(title: link, color: K.text, weight: .medium, action: action)
        }
    }
}
