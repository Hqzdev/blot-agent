import BlotDesign
import SwiftUI

struct PhoneBrowserSignInButton: View {
    @Environment(WorkspaceStore.self) private var store
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.blotReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    private var waiting: Bool { store.browserSignIn.isActive }

    var body: some View {
        GeometryReader { geometry in
            let width = max(0, geometry.size.width - (waiting ? 8 : 0))
            HStack(spacing: 8) {
                if waiting {
                    cancelButton.frame(width: width * 0.3)
                        .transition(.opacity.combined(with: .scale(scale: 0.9, anchor: .leading)))
                }
                Button { store.navigate(.signIn) } label: {
                    HStack(spacing: 8) {
                        if waiting { ProgressView().controlSize(.small).tint(WorkspaceStyle.secondary) }
                        Text(store.t(waiting ? "Waiting for browser" : "Log In or Sign Up"))
                            .font(waiting ? .subheadline.weight(.medium) : .body.weight(.medium))
                            .lineLimit(1).minimumScaleFactor(0.75)
                    }
                    .padding(.horizontal, 10)
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .foregroundStyle(waiting ? WorkspaceStyle.secondary : BlotColor.onInverse)
                    .background(waiting ? WorkspaceStyle.ink.opacity(0.12) : BlotColor.inverse, in: Capsule())
                    .overlay(Capsule().strokeBorder(WorkspaceStyle.secondary.opacity(waiting ? 0.08 : 0.15)))
                    .shadow(color: .black.opacity(waiting ? 0 : 0.12), radius: 18, y: 6)
                }
                .buttonStyle(.plain).disabled(waiting || store.busy)
                .frame(width: waiting ? width * 0.7 : width)
                .accessibilityIdentifier("welcome.browser-sign-in")
            }
        }
        .frame(height: 48)
        .animation(reduceMotion || systemReduceMotion ? nil : BlotInterfaceMotion.standard, value: waiting)
    }

    private var cancelButton: some View {
        Button { store.browserSignIn.cancel() } label: {
            Text(store.t("Cancel")).font(.subheadline.weight(.medium))
                .lineLimit(1).minimumScaleFactor(0.75)
                .frame(maxWidth: .infinity, minHeight: 48)
                .foregroundStyle(.black)
        }
        .buttonStyle(.plain)
        .background(reduceTransparency ? Color.white : .clear, in: Capsule())
        .glassEffect(.regular.tint(.white.opacity(0.75)).interactive(), in: .capsule)
        .accessibilityIdentifier("welcome.cancel-browser-sign-in")
    }
}
