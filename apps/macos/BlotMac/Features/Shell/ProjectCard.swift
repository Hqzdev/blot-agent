import BlotDesign
import SwiftUI
import UniformTypeIdentifiers

struct ProjectCard: View {
    @Environment(AppState.self) private var app
    @State private var importing = false
    @State private var importProjectID = ""
    @State private var importError: String?
    private var added: Int { app.shellChangedFiles.reduce(0) { $0 + $1.added } }
    private var removed: Int { app.shellChangedFiles.reduce(0) { $0 + $1.removed } }
    var body: some View {
        VStack(alignment: .leading, spacing: KSpace.lg) {
            HStack(spacing: 4) {
                Text(app.shellProjectName.isEmpty ? "No project selected" : app.shellProjectName)
                    .font(KFont.body()).foregroundStyle(K.text3).lineLimit(1)
                Spacer()
                MoreMenu(help: "Project panel actions") {[
                    .button(app.shell.expandedSources ? "Show fewer sources" : "View all sources", icon: "list") {
                        app.shell.expandedSources.toggle()
                    },
                    .divider,
                    .button("Hide project panel", icon: "sidebar.right") { app.shell.rightVisible = false },
                ]}
            }
            if app.shellHasConversation {
                Button { app.showShellReview() } label: {
                    HStack(spacing: KSpace.sm) {
                        KIcon(app.isMotes ? "users" : "file-text", size: 16, color: K.text3)
                        Text(app.isMotes ? "Run details" : (app.currentTask?.title ?? "Changes"))
                            .font(KFont.body()).foregroundStyle(K.text2).lineLimit(1)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        if app.isMotes {
                            Text("\(app.team.count) Motes").font(KFont.caption()).foregroundStyle(K.text3)
                        } else if added + removed > 0 {
                            Text("+" + added.formatted(.number)).foregroundStyle(K.success)
                                .accessibilityLabel("\(added) lines added")
                            Text("−" + removed.formatted(.number)).foregroundStyle(K.danger)
                                .accessibilityLabel("\(removed) lines removed")
                        }
                        KIcon("chevron-right", size: 12, color: K.text3)
                    }
                    .font(KFont.mono(12)).frame(height: 32).padding(.horizontal, 6).contentShape(Rectangle())
                    .kHover(radius: K.rMd)
                }
                .buttonStyle(KIconButtonStyle()).kFocusRing(radius: K.rMd)
                .padding(.horizontal, -6)
                .help(app.isMotes ? "Open run details" : "Open results and Git")
            }
            HDivider()
            HStack {
                Text("Sources").font(KFont.body()).foregroundStyle(K.text2)
                Spacer()
                IconButton(icon: "plus", iconSize: 15, help: "Add a local file") {
                    importProjectID = app.shellProjectID; importing = true
                }
                .disabled(app.shellProjectID.isEmpty)
            }
            VStack(alignment: .leading, spacing: 2) {
                if app.shellSources.isEmpty {
                    Text("Add a file for this project").font(KFont.body()).foregroundStyle(K.text3)
                }
                ForEach(app.shell.expandedSources ? app.shellSources : Array(app.shellSources.prefix(3))) { source in
                    ProjectSourceRow(source: source).transition(.kAppear)
                }
            }
            .kAnimation(value: app.shell.expandedSources)
            if let importError { InlineFeedback(text: importError, tone: .error) }
            if app.shellSources.count > 3 {
                TextLink(title: app.shell.expandedSources ? "Show less" : "View all \(app.shellSources.count)", color: K.text3, size: 14) {
                    app.shell.expandedSources.toggle()
                }
            }
        }.padding(KSpace.lg).kCard(radius: K.rPopover, fill: K.surface2)
        .fileImporter(isPresented: $importing, allowedContentTypes: [.item], allowsMultipleSelection: true) { result in
            switch result {
            case .success(let urls): app.shell.addSources(urls, projectID: importProjectID); importError = nil
            case .failure(let error): importError = error.localizedDescription
            }
        }
    }
}
