import BlotDesign
import SwiftUI
struct ShellRightPane: View {
    @Environment(AppState.self) private var app
    var body: some View {
        Group {
            if let source = app.shell.previewSource { SourcePreview(source: source) }
            else if app.product == .code && app.shellHasConversation {
                if app.teamRoute == .graph && app.inspectorVisible { GraphInspector() }
                else { TeamLivePanel() }
            } else { VStack { ProjectCard().padding(8); Spacer() } }
        }.frame(maxWidth: .infinity, maxHeight: .infinity).background(K.bg)
    }
}
