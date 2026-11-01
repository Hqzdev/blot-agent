import BlotDesign
import SwiftUI

struct BlotMotionPreview: View {
    @Environment(AppState.self) private var app
    @State private var selection: BlotState = .idle
    @State private var replay = 0
    var body: some View {
        PageContent {
            VStack(alignment: .leading, spacing: 24) {
                Text("Blot").font(KFont.pageTitle()).foregroundStyle(K.text)
                HStack {
                    BlotView(state: selection, size: 160, replay: replay, followsPointer: true,
                             behavior: .lively, tappable: selection == .idle)
                        .frame(maxWidth: .infinity)
                    VStack(alignment: .leading, spacing: 14) {
                        Text(selection.title).font(KFont.ui(20, .medium)).foregroundStyle(K.text)
                        Text(selection == .idle ? "Idle = Blot lives on his own: beats by mood, reacts to the pointer, click him" : "Motion from agent.pen · 18 · Blot").font(KFont.body()).foregroundStyle(K.text3)
                        KButton(title: "Replay", icon: "play") { replay += 1 }
                        if app.settings.reduceMotion {
                            Text("Reduce motion is enabled in Appearance.").font(KFont.body()).foregroundStyle(K.text3)
                        }
                    }
                }.padding(24).kCard()
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 160))], spacing: 12) {
                    ForEach(BlotState.allCases) { state in
                        Button { selection = state; replay += 1 } label: {
                            VStack(spacing: 12) {
                                BlotView(state: state, size: 72, behavior: state == .idle ? .lively : BlotBehavior.none)
                                Text(state.title).font(KFont.body()).foregroundStyle(K.text)
                            }.frame(maxWidth: .infinity).padding(16)
                                .kCard(fill: selection == state ? K.selected : K.surface)
                        }.buttonStyle(KIconButtonStyle()).kFocusRing(radius: K.rSm)
                    }
                }
            }
        }.background(K.bg)
    }
}
