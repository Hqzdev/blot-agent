import BlotDesign
import SwiftUI

struct PhoneComposerMenuAnchor: PreferenceKey {
    struct Presentation {
        let bounds: Anchor<CGRect>
        let menu: PhoneComposerMenuState
    }

    static var defaultValue: Presentation? { nil }
    static func reduce(value: inout Presentation?, nextValue: () -> Presentation?) {
        value = nextValue() ?? value
    }
}

/// Hosts the expanding surface above the page, without resizing the conversation.
struct PhoneComposerMenuOverlay: ViewModifier {
    @Environment(WorkspaceStore.self) private var store
    @Environment(\.blotReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content.overlayPreferenceValue(PhoneComposerMenuAnchor.self) { value in
            if let value {
                GeometryReader { geometry in
                    let composer = geometry[value.bounds]
                    let anchor = CGRect(x: composer.minX + 6, y: composer.maxY - 50, width: 44, height: 48)
                    ZStack(alignment: .topLeading) {
                        if let page = value.menu.page {
                            let gallery = page == .photos
                            let leading = gallery ? geometry.safeAreaInsets.leading + 12 : max(12, composer.minX - 18)
                            let width = gallery
                                ? max(180, geometry.size.width - leading - geometry.safeAreaInsets.trailing - 12)
                                : min(288, max(220, composer.width * 0.78))
                            let screenBottom = geometry.size.height + geometry.safeAreaInsets.bottom - 8
                            let bottom = gallery ? screenBottom : min(screenBottom, anchor.maxY + 96)
                            let screenHeight = geometry.size.height + geometry.safeAreaInsets.top + geometry.safeAreaInsets.bottom
                            let height = min(gallery ? screenHeight * 0.58 : 284,
                                             max(120, bottom - geometry.safeAreaInsets.top - 12))
                            let input = CGRect(x: composer.maxX - 60, y: composer.maxY - 52, width: 60, height: 52)
                            let backdrop = PhoneComposerBackdrop(input: input)
                            Button {
                                withKAnimation(reduceMotion, KMotion.panel) { value.menu.dismiss() }
                            } label: {
                                backdrop.fill(.clear, style: FillStyle(eoFill: true))
                                    .contentShape(backdrop, eoFill: true)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(store.t("Close"))

                            PhoneComposerMenuSurface(menu: value.menu, size: CGSize(width: width, height: height),
                                                     origin: CGSize(width: anchor.minX - leading, height: anchor.maxY - bottom))
                                .frame(width: width, height: height, alignment: .bottomLeading)
                                .transition(reduceMotion ? .opacity : .asymmetric(
                                    insertion: .opacity,
                                    removal: .scale(scale: 0.14, anchor: .bottomLeading).combined(with: .opacity)))
                                .offset(x: leading, y: bottom - height)
                        }
                    }
                    .kAnimation(KMotion.panel, value: value.menu.page)
                    .allowsHitTesting(value.menu.isOpen)
                }
                .ignoresSafeArea(.keyboard, edges: .bottom)
            }
        }
    }
}

/// The compact composer remains tappable while the rest of the page dismisses the menu.
private struct PhoneComposerBackdrop: Shape {
    let input: CGRect

    func path(in rect: CGRect) -> Path {
        var path = Path(rect)
        path.addRoundedRect(in: input, cornerSize: CGSize(width: 24, height: 24))
        return path
    }
}

private struct PhoneComposerMenuSurface: View {
    let menu: PhoneComposerMenuState
    let size: CGSize
    let origin: CGSize
    @Environment(\.blotReduceMotion) private var reduceMotion
    @State private var expanded = false

    var body: some View {
        Group {
            if menu.page == .photos {
                PhoneInlinePhotoGallery(menu: menu)
            } else {
                ScrollView {
                    PhoneAttachmentMenu { source in
                        withKAnimation(reduceMotion, KMotion.panel) { menu.select(source) }
                    }
                }.scrollIndicators(.hidden)
            }
        }
        .frame(width: size.width, height: size.height)
        .opacity(expanded ? 1 : 0)
        .frame(width: expanded ? size.width : 44, height: expanded ? size.height : 44, alignment: .bottomLeading)
        .clipShape(RoundedRectangle(cornerRadius: expanded ? 44 : 22, style: .continuous))
        .glassEffect(.regular.interactive(), in: .rect(cornerRadius: expanded ? 44 : 22))
        .offset(x: expanded ? 0 : origin.width, y: expanded ? 0 : origin.height)
        .accessibilityElement(children: .contain)
        .accessibilityAction(.escape) {
            withKAnimation(reduceMotion, KMotion.panel) { menu.dismiss() }
        }
        .task {
            await Task.yield()
            withKAnimation(reduceMotion, KMotion.panel) { expanded = true }
        }
    }
}
