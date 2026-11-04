import BlotDesign
import SwiftUI

struct MacWelcomeView: View {
    @Environment(WorkspaceStore.self) private var store

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .bottom) {
                VStack(spacing: 44) {
                    HStack(spacing: 20) {
                        mark
                        Text("Blot Agent").font(.system(size: 64, weight: .regular))
                            .lineLimit(1).minimumScaleFactor(0.7).accessibilityAddTraits(.isHeader)
                    }
                    Text(store.t("Your team of always-on agents\nyou can give real work to"))
                        .font(.system(size: 21)).multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                    Button {
                        store.navigate(.signIn)
                    } label: {
                        HStack(spacing: 9) {
                            if store.busy { ProgressView().controlSize(.small).tint(.white) }
                            Text(store.busy ? "Завершаем вход…" : store.t("Sign in"))
                            if !store.busy { BlotIcon(.arrowUp, size: 14).rotationEffect(.degrees(90)) }
                        }.font(.system(size: 18)).padding(.horizontal, 16).padding(.vertical, 10)
                            .contentShape(Rectangle())
                    }.buttonStyle(.plain).disabled(store.busy).padding(.top, 4)
                    if let error = store.error {
                        Text(error).font(.callout).foregroundStyle(.red)
                            .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("workspace.error")
                    }
                }.foregroundStyle(.white)
                    .padding(.horizontal, 32).frame(maxWidth: 680)
                    .position(x: geometry.size.width / 2, y: geometry.size.height * 0.47)
                Text(store.t("By continuing, you accept the Terms and Privacy Policy."))
                    .font(.system(size: 12)).foregroundStyle(.white.opacity(0.45))
                    .multilineTextAlignment(.center).frame(maxWidth: 680)
                    .padding(.horizontal, 32).padding(.bottom, 28)
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Color(red: 0.065, green: 0.065, blue: 0.065).ignoresSafeArea())
    }

    private var mark: some View {
        Circle().fill(.white).frame(width: 60, height: 60)
            .overlay {
                HStack(spacing: 11) {
                    Capsule().frame(width: 7, height: 18)
                    Capsule().frame(width: 7, height: 18)
                }.foregroundStyle(.black)
            }.accessibilityHidden(true)
    }
}
