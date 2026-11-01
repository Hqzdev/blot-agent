import BlotDesign
import SwiftUI

struct PrimaryBlot: View {
    @Environment(AppState.self) private var app
    @Environment(\.blotNamespace) private var namespace
    let context: BlotContext
    var body: some View {
        Group {
            if let namespace { pet.matchedGeometryEffect(id: "primary-blot", in: namespace) }
            else { pet }
        }
    }
    private var pet: some View {
        BlotView(state: app.activeBlotContext == context ? app.activeBlotState : .idle,
                 size: K.primaryBlotSize, followsPointer: true, behavior: .lively, tappable: true, intro: true, context: context)
    }
}
