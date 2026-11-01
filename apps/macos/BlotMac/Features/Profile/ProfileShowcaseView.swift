import BlotDesign
import SwiftUI

struct ProfileShowcaseView: View {
    @Environment(\.openURL) private var openURL
    let sites: [SavedSite]
    let edit: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Text("Showcase").font(KFont.body(.medium)).foregroundStyle(K.text)
                Spacer()
                if !sites.isEmpty { KButton(title: "Edit", icon: "pencil", kind: .ghost, height: 28, action: edit) }
            }
            if sites.isEmpty {
                VStack(spacing: 24) {
                    ShowcaseIllustration().frame(width: 180, height: 82)
                    Text("Feature sites on your profile").font(KFont.body()).foregroundStyle(K.text2)
                    KButton(title: "Add sites", icon: "plus", action: edit)
                }
                .frame(maxWidth: .infinity).frame(height: 256)
                .kCard(radius: K.rXl, fill: K.surface2)
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 220))], spacing: 14) {
                    ForEach(sites) { site in
                        Button { openURL(site.url) } label: {
                            VStack(alignment: .leading, spacing: 14) {
                                HStack {
                                    KIcon("globe", size: 28, color: K.text2)
                                    Spacer()
                                    KIcon("square-arrow-out-up-right", size: 14, color: K.text3)
                                }
                                Text(site.name).font(KFont.body(.medium)).foregroundStyle(K.text).lineLimit(2)
                                Text(site.url.host ?? site.url.absoluteString).font(KFont.caption()).foregroundStyle(K.text2).lineLimit(1)
                            }.padding(20).frame(maxWidth: .infinity, alignment: .leading)
                                .frame(minHeight: 140).kCard(radius: K.rPopover, fill: K.surface2)
                                .contentShape(Rectangle()).kHover(radius: K.rPopover)
                        }.buttonStyle(KIconButtonStyle()).kFocusRing(radius: K.rSm)
                    }
                }
            }
        }
    }
}

private struct ShowcaseIllustration: View {
    var body: some View {
        ZStack {
            tile(front: false).rotationEffect(.degrees(-10)).offset(x: -38, y: 5)
            tile(front: false).rotationEffect(.degrees(10)).offset(x: 38, y: 5)
            tile(front: true)
        }.accessibilityHidden(true)
    }
    private func tile(front: Bool) -> some View {
        VStack(spacing: 7) {
            Capsule().fill(K.text.opacity(0.09)).frame(width: 42, height: 5)
            if front {
                KIcon("globe", size: 22, color: K.text2)
                Text("www").font(KFont.caption()).foregroundStyle(K.text3)
            } else { Spacer(minLength: 0) }
        }.padding(9).frame(width: 100, height: 72)
            .background(K.composer, in: RoundedRectangle(cornerRadius: K.rMd))
            .overlay(RoundedRectangle(cornerRadius: K.rMd).strokeBorder(K.border, lineWidth: 1))
    }
}
