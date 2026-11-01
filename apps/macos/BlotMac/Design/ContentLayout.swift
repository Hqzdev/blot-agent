import BlotDesign
import SwiftUI

/// The content width excludes the surrounding page gutter on every screen.
struct ContentColumn<Content: View>: View {
    var alignment: Alignment = .leading
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .frame(maxWidth: K.contentWidth, alignment: alignment)
            .padding(.horizontal, K.pageInset)
            .frame(maxWidth: .infinity, alignment: .top)
    }
}

struct PageContent<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        ScrollView {
            ContentColumn {
                content()
                    .padding(.top, K.pageTopInset)
                    .padding(.bottom, K.pageTopInset)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct ComposerPlacement: ViewModifier {
    let hasPet: Bool

    func body(content: Content) -> some View {
        ContentColumn { content }
            .padding(.top, hasPet ? K.composerPetClearance : 0)
            .padding(.bottom, K.composerBottomInset)
    }
}

extension View {
    func composerPlacement(hasPet: Bool = false) -> some View {
        modifier(ComposerPlacement(hasPet: hasPet))
    }
}
