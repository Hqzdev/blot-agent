import BlotDesign
import SwiftUI

struct PhoneWelcomeView: View {
    @Environment(WorkspaceStore.self) private var store
    @ScaledMetric(relativeTo: .largeTitle) private var titleSize = 36

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                PhoneWelcomeOrbit()
                VStack(spacing: 12) {
                    Text("Blot Agent")
                        .font(.system(size: titleSize, weight: .medium))
                        .accessibilityAddTraits(.isHeader)
                    Text(store.t("Your team of always-on agents\nthat finish the work."))
                        .font(.body).foregroundStyle(WorkspaceStyle.secondary)
                        .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: 310)
                }
                .padding(.horizontal, 32)
                .position(x: geometry.size.width / 2, y: geometry.size.height * 0.44)
                VStack {
                    Spacer(minLength: 0)
                    footer
                }.padding(.horizontal, 30)
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .clipped()
        }
        .background(BlotColor.dynamic(.init(light: 0xFCFCFCFF, dark: 0x111111FF)).ignoresSafeArea())
    }

    private var footer: some View {
        VStack(spacing: 18) {
            Button { store.navigate(.signIn) } label: {
                Text(store.t("Log In or Sign Up")).font(.body.weight(.medium))
                    .foregroundStyle(BlotColor.onInverse)
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .background(BlotColor.inverse, in: Capsule())
                    .overlay(Capsule().strokeBorder(WorkspaceStyle.secondary.opacity(0.15)))
                    .shadow(color: .black.opacity(0.12), radius: 18, y: 6)
            }.buttonStyle(.plain)
            Text(store.t("By continuing, you accept the Terms and Privacy Policy."))
                .font(.system(size: 11)).foregroundStyle(WorkspaceStyle.secondary.opacity(0.6))
                .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 290)
        }.padding(.bottom, 2)
    }
}
