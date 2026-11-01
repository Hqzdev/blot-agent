import BlotDesign
import SwiftUI

struct ProductModePicker: View {
    @Environment(AppState.self) private var app
    let title: String
    @State private var anchor = KMenuAnchor()
    @State private var presented = false

    var body: some View {
        Button(action: toggle) {
            HStack(spacing: 6) {
                Text(title).font(KFont.sidebarTitle()).foregroundStyle(K.text).lineLimit(1)
                KIcon("chevron-down", size: 12, color: K.text3)
                    .rotationEffect(.degrees(presented ? 180 : 0))
            }.padding(.horizontal, 6).frame(height: 32).kHover(radius: K.rMd, active: presented)
                .padding(.leading, -6)
                .kAnimation(KMotion.quick, value: presented)
        }
        .buttonStyle(KIconButtonStyle()).kFocusRing(radius: K.rSm)
        .accessibilityLabel("Switch mode")
        .accessibilityValue(app.product.rawValue)
        .background(KMenuAnchorView(anchor: anchor))
        .onDisappear { if presented { KMenuController.shared.close() } }
        .onChange(of: app.shellDestination) { _, _ in if presented { KMenuController.shared.close() } }
    }

    private func toggle() {
        guard !presented, let view = anchor.view, let window = view.window else {
            KMenuController.shared.close()
            return
        }
        let rect = window.convertToScreen(view.convert(view.bounds, to: nil))
        presented = true
        KMenuController.shared.showDropdown(ProductModeMenuCard().environment(app), below: rect, in: window,
                                           title: "Switch mode") { presented = false }
    }
}

struct ProductModeMenuCard: View {
    @Environment(AppState.self) private var app
    var body: some View {
        VStack(spacing: 2) {
            ForEach([Product.code, .work], id: \.self) { product in
                Button {
                    KMenuController.shared.close()
                    app.switchProduct(product)
                } label: {
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Blot \(product.rawValue)").font(KFont.ui(15, .medium)).foregroundStyle(K.text)
                            Text(product.subtitle).font(KFont.ui(13)).foregroundStyle(K.text2)
                        }.frame(maxWidth: .infinity, alignment: .leading)
                        if app.product == product { KIcon("check", size: 16, color: K.text) }
                    }
                    .padding(.horizontal, 12).padding(.vertical, 10).contentShape(Rectangle())
                    .kHover(radius: 10, active: app.product == product)
                }.buttonStyle(KIconButtonStyle()).kFocusRing(radius: 10).accessibilityAddTraits(app.product == product ? .isSelected : [])
            }
        }
        .padding(6).frame(width: 300)
        .kPopover(radius: K.rXl)
    }
}
