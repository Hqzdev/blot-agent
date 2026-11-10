import BlotDesign
import SwiftUI

enum PhonePageLayout {
    static let inset: CGFloat = 20
    static let sectionSpacing: CGFloat = 24
    static let rowInset: CGFloat = 16
    static let radius: CGFloat = 16
}

extension EnvironmentValues {
    @Entry var phonePageTitle: String? = nil
}

struct PhonePageHeader<Actions: View>: View {
    let title: String
    var back: (() -> Void)? = nil
    @ViewBuilder var actions: Actions
    @Environment(WorkspaceStore.self) private var store

    var body: some View {
        HStack(spacing: 12) {
            if let back {
                PhoneGlassCircleButton(symbol: "chevron.left", title: store.t("Back"), action: back)
            }
            Text(title).font(.title2.weight(.semibold)).lineLimit(1).truncationMode(.tail)
                .accessibilityAddTraits(.isHeader)
                .frame(maxWidth: .infinity, alignment: .leading)
            actions
        }
        .frame(minHeight: 44)
        .padding(.horizontal, PhonePageLayout.inset).padding(.vertical, 8)
        .background(WorkspaceStyle.canvas)
    }
}

extension PhonePageHeader where Actions == EmptyView {
    init(title: String, back: (() -> Void)? = nil) {
        self.title = title
        self.back = back
        self.actions = EmptyView()
    }
}

struct PhonePage<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: PhonePageLayout.sectionSpacing) { content }
                .frame(maxWidth: 640, alignment: .leading)
                .padding(PhonePageLayout.inset).frame(maxWidth: .infinity)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(WorkspaceStyle.canvas.ignoresSafeArea())
    }
}
