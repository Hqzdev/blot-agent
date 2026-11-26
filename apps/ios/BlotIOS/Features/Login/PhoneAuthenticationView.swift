import BlotDesign
import SwiftUI

struct PhoneAuthenticationView: View {
    let initialRoute: WorkspaceRoute
    @Environment(WorkspaceStore.self) private var store
    @State private var submitting = false
    @State private var submission: _Concurrency.Task<Void, Never>?

    private var route: WorkspaceRoute { store.authenticationRoute ?? initialRoute }
    private var registering: Bool { route == .createAccount }

    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                Group {
                    if submitting { loading }
                    else { form }
                }
                .padding(.horizontal, 16)
                .padding(.top, registering ? 68 : 148)
                .padding(.bottom, 96)
                .frame(minHeight: geometry.size.height, alignment: .top)
            }
            .scrollDismissesKeyboard(.interactively)
            .overlay(alignment: .top) { header.padding(.horizontal, 16).padding(.top, 16) }
            .overlay(alignment: .bottom) { browserControls.padding(.horizontal, 24).padding(.bottom, 16) }
            .background(PhoneReferenceStyle.authentication.ignoresSafeArea())
        }
        .foregroundStyle(WorkspaceStyle.ink)
        .workspaceGlassContainer()
        .onDisappear { submission?.cancel() }
    }

    private var header: some View {
        HStack(spacing: 12) {
            PhoneGlassCircleButton(symbol: "xmark", title: store.t("Close")) { close() }
            Spacer(minLength: 0)
            Text("Ori").font(.headline).lineLimit(1)
            Spacer(minLength: 0)
            Menu {
                Button("Русский") { store.language = "ru" }
                Button("English") { store.language = "en" }
            } label: {
                BlotIcon(symbol: "rectangle.bottomthird.inset.filled").font(.title3)
                    .frame(width: 44, height: 44).blotChromeSurface(cornerRadius: 24)
            }.accessibilityLabel(store.t("Language"))
        }
    }

    private var form: some View {
        @Bindable var store = store
        return VStack(spacing: 26) {
            WorkspaceAvatar(size: 68)
            Text(store.t("Sign in to Ori")).font(.system(size: 25))
                .multilineTextAlignment(.center).padding(.bottom, 14)
                .accessibilityAddTraits(.isHeader)
            VStack(spacing: 20) {
                if registering {
                    PhoneAuthenticationField(title: "First name", placeholder: "Your first name", text: $store.form.account.name)
                    PhoneAuthenticationField(title: "Last name", placeholder: "Your last name", text: $store.form.account.lastName)
                }
                PhoneAuthenticationField(title: "Email", placeholder: "Your email address", text: $store.form.account.email)
                SecureField(store.t("Password"), text: $store.form.account.password)
                    .textContentType(registering ? .newPassword : .password)
                    .font(.subheadline).textFieldStyle(.plain)
                    .padding(.horizontal, 16).frame(minHeight: 38)
                    .background(PhoneReferenceStyle.field, in: RoundedRectangle(cornerRadius: 6))
                    .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(BlotColor.edge))
                    .accessibilityLabel(store.t("Password"))
                if !registering {
                    Button(store.t("Forgot password?")) {
                        store.authenticationRoute = nil
                        store.navigate(.recovery)
                    }.buttonStyle(.plain)
                }
                WorkspaceFeedback()
                Button { submit(registering ? .register : .signIn) } label: {
                    Text(store.t(registering ? "Continue" : "Continue with email"))
                        .font(.subheadline).foregroundStyle(BlotColor.onInverse)
                        .frame(maxWidth: .infinity).frame(minHeight: 36)
                        .background(BlotColor.inverse, in: RoundedRectangle(cornerRadius: 6))
                }.buttonStyle(.plain)
            }
            Button {
                store.navigate(registering ? .signIn : .createAccount)
            } label: {
                (Text(store.t(registering ? "Already have an account? " : "Don’t have an account? "))
                    .foregroundStyle(WorkspaceStyle.secondary)
                 + Text(store.t(registering ? "Sign in" : "Sign up")))
                .font(.subheadline)
            }.buttonStyle(.plain).padding(.top, 4)
            if !registering { Spacer(minLength: 52) }
            VStack(spacing: 4) {
                if registering {
                    Text(store.t("By creating an account, you agree to the"))
                }
                Text(store.t("Terms of Service and Privacy Policy")).underline()
            }.font(.subheadline).foregroundStyle(WorkspaceStyle.secondary)
                .multilineTextAlignment(.center).padding(.top, 12)
        }
    }

    private var loading: some View {
        VStack(alignment: .leading, spacing: 22) {
            WorkspaceAvatar(size: 34)
            HStack(spacing: 10) { Text(store.t("Loading…")).font(.title3); ProgressView() }
            Divider()
            Text(store.t("Your input stays on this device.")).font(.subheadline).foregroundStyle(WorkspaceStyle.secondary)
        }.frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 8)
            .accessibilityElement(children: .combine)
    }

    private var browserControls: some View {
        HStack {
            PhoneGlassCircleButton(symbol: "chevron.left", title: store.t("Back")) {
                if registering { store.navigate(.signIn) } else { close() }
            }
            Spacer()
            PhoneGlassCapsule {
                HStack(spacing: 24) {
                    ShareLink(item: "Ori") {
                        BlotIcon(symbol: "square.and.arrow.up").font(.title2).frame(width: 28, height: 44)
                    }.buttonStyle(.plain).accessibilityLabel(store.t("Share"))
                    Button {
                        if submitting { submission?.cancel(); submitting = false }
                        else { store.form.account = WorkspaceAccountForm(); store.error = nil }
                    } label: {
                        BlotIcon(symbol: submitting ? "xmark" : "arrow.clockwise").font(.title2).frame(width: 28, height: 44)
                    }.buttonStyle(.plain).accessibilityLabel(store.t(submitting ? "Cancel" : "Reset form"))
                }
            }
        }
    }

    private func submit(_ action: WorkspaceAction) {
        guard !submitting else { return }
        let destination: WorkspaceRoute = registering ? .verifyEmail : .chats
        submitting = true
        submission = _Concurrency.Task {
            await _Concurrency.Task.yield()
            guard !_Concurrency.Task.isCancelled else { return }
            await store.perform(action, next: destination)
            submitting = false
        }
    }

    private func close() {
        submission?.cancel()
        submitting = false
        store.dismissAuthentication()
    }
}

struct PhoneVerificationActions: View {
    @Environment(WorkspaceStore.self) private var store
    @Environment(\.dynamicTypeSize) private var textSize
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        let layout = textSize.isAccessibilitySize ? AnyLayout(VStackLayout(spacing: 12)) : AnyLayout(HStackLayout(spacing: 12))
        layout {
            Button(role: .cancel) {
                store.form.account.code = ""
                store.form.account.password = ""
                store.dismissAuthentication()
            } label: {
                Text(store.t("Cancel"))
                    .font(.body.weight(.medium)).foregroundStyle(WorkspaceStyle.ink)
                    .padding(.horizontal, 18)
                    .frame(maxWidth: textSize.isAccessibilitySize ? .infinity : nil, minHeight: 48)
                    .background(reduceTransparency ? BlotColor.panel : .clear, in: Capsule())
                    .glassEffect(reduceTransparency ? .identity : .regular.interactive(), in: Capsule())
                    .contentShape(Capsule())
            }.buttonStyle(BlotPlainButtonStyle())

            Button {
                _Concurrency.Task { await store.perform(.verify) }
            } label: {
                HStack(spacing: 8) {
                    if store.busy { ProgressView().controlSize(.small).tint(BlotColor.onInverse) }
                    Text(store.t("Confirm sign-in"))
                }
            }.buttonStyle(PhoneAuthenticationPrimaryButtonStyle())
        }
        .disabled(store.busy)
        .padding(.horizontal, 30).padding(.top, 8).padding(.bottom, 2)
        .background(PhoneReferenceStyle.authentication.ignoresSafeArea(edges: .bottom))
    }
}

struct PhoneAuthenticationPrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var enabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.medium)).multilineTextAlignment(.center)
            .foregroundStyle(BlotColor.onInverse)
            .padding(.horizontal, 12).padding(.vertical, 8)
            .frame(maxWidth: .infinity, minHeight: 48)
            .background(BlotColor.inverse, in: Capsule())
            .overlay(Capsule().strokeBorder(WorkspaceStyle.secondary.opacity(0.15)).allowsHitTesting(false))
            .shadow(color: .black.opacity(0.12), radius: 18, y: 6)
            .contentShape(Capsule())
            .opacity(enabled ? (configuration.isPressed ? 0.78 : 1) : 0.6)
    }
}

private struct PhoneAuthenticationField: View {
    let title: String
    let placeholder: String
    @Binding var text: String
    @Environment(WorkspaceStore.self) private var store

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(store.t(title)).font(.subheadline).foregroundStyle(WorkspaceStyle.secondary)
            TextField(store.t(placeholder), text: $text)
                .font(.subheadline).textFieldStyle(.plain)
                .textInputAutocapitalization(title == "Email" ? .never : .words)
                .keyboardType(title == "Email" ? .emailAddress : .default)
                .textContentType(title == "Email" ? .emailAddress : title == "First name" ? .givenName : .familyName)
                .autocorrectionDisabled().padding(.horizontal, 16).frame(minHeight: 38)
                .background(PhoneReferenceStyle.field, in: RoundedRectangle(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(BlotColor.edge))
                .accessibilityLabel(store.t(title))
        }
    }
}
