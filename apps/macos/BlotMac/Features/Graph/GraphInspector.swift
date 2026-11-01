import BlotAPI
import BlotDesign
import SwiftUI

/// Right panel for the graph: the record behind the selected node or link.
struct GraphInspector: View {
    @Environment(AppState.self) private var app
    private var evidence: WorkspaceEvidence? {
        let source: String
        switch app.graphSelection {
        case .node(let id), .edge(let id): source = id
        case nil: return nil
        }
        let parts = source.split(separator: "|")
        guard parts.count == 2, let id = UUID(uuidString: String(parts[1])) else { return nil }
        return WorkspaceEvidence(kind: String(parts[0]), id: id)
    }
    private var isEdge: Bool { if case .edge = app.graphSelection { return true }; return false }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: KSpace.sm) {
                Text(isEdge ? "Connection" : "Selection").font(KFont.body(.medium)).foregroundStyle(K.text)
                if let evidence { Badge(text: evidence.kind.lowercased()) }
                Spacer()
                IconButton(icon: "x", help: "Close inspector") { app.inspectorVisible = false }
            }
            .padding(.leading, KSpace.lg).padding(.trailing, 10).frame(height: K.headerHeight).kBorder(.bottom)
            ScrollView {
                VStack(alignment: .leading, spacing: KSpace.lg) {
                    if let evidence, let row = app.workspace.find(evidence.kind, evidence.id) {
                        VStack(alignment: .leading, spacing: 6) {
                            KeyValueRow(label: "Record", value: String(row.id.uuidString.prefix(8)), mono: true, labelWidth: 72)
                            KeyValueRow(label: "Version", value: String(row.version), labelWidth: 72)
                            if !row.data.text("status").isEmpty {
                                HStack(spacing: KSpace.md) {
                                    Text("Status").font(KFont.ui(13)).foregroundStyle(K.text3).frame(width: 72, alignment: .leading)
                                    StatusBadge(status: row.data.text("status"))
                                }
                            }
                        }
                        if !row.data.text("content").isEmpty {
                            Text(row.data.text("content")).font(KFont.ui(13)).foregroundStyle(K.text).lineSpacing(3)
                                .textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                                .padding(12).frame(maxWidth: .infinity, alignment: .leading)
                                .kCard(radius: K.rLg, fill: K.surface)
                        }
                        CodeBlock(title: "data", text: row.data.formatted, maxHeight: 320)
                        if let id = row.data.uuid("artifactId") { ArtifactLink(id: id) }
                    } else {
                        EmptyState(icon: "network", title: "Nothing selected",
                                   detail: "Select a node or a link on the graph to see where it comes from.")
                    }
                }
                .padding(KSpace.lg)
            }
        }
        .kAnimation(value: app.graphSelection)
    }
}

/// «Team · live» panel next to a Motes conversation: run status and every specialist's state.
struct TeamLivePanel: View {
    @Environment(AppState.self) private var app
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: KSpace.sm) {
                Text("Team · live").font(KFont.body(.medium)).foregroundStyle(K.text)
                let working = app.workspace.rows("AGENT_SESSION", parentID: UUID(uuidString: app.selectedRunID))
                    .filter { BackendStatus($0.data.text("status")).tone == .active }.count
                if working > 0 { Badge(text: "\(working) working") }
                Spacer()
                IconButton(icon: "network", help: "Open the team graph") { app.openGraph() }
            }
            .padding(.leading, KSpace.lg).padding(.trailing, 10).frame(height: K.headerHeight).kBorder(.bottom)
            if let run = app.workspace.find("RUN", app.selectedRunID) {
                let sessions = app.workspace.rows("AGENT_SESSION", parentID: run.id)
                ScrollView {
                    VStack(alignment: .leading, spacing: 2) {
                        if sessions.isEmpty {
                            EmptyState(icon: "users", title: "No specialists yet",
                                       detail: "They join after you approve the plan.")
                        }
                        ForEach(sessions, id: \.id) { session in
                            let status = BackendStatus(session.data.text("status"))
                            HStack(alignment: .top, spacing: KSpace.md) {
                                FaceAvatar(role: .backendRole(session.data.text("role")), size: 32)
                                    .opacity(status.tone == .neutral ? 0.6 : 1)
                                VStack(alignment: .leading, spacing: 3) {
                                    HStack(spacing: 6) {
                                        Text(AgentRole.displayName(session.data.text("role")))
                                            .font(KFont.label()).foregroundStyle(K.text)
                                        Image(systemName: status.tone.icon).font(.system(size: 10, weight: .semibold))
                                            .foregroundStyle(status.tone.color).accessibilityHidden(true)
                                        Text(status.label.lowercased()).font(KFont.mono(11)).foregroundStyle(K.text2)
                                    }
                                    if !session.data.text("waitingReason").isEmpty {
                                        Text(session.data.text("waitingReason")).font(KFont.mono(11)).foregroundStyle(K.text3)
                                            .lineLimit(2)
                                    }
                                }
                                Spacer(minLength: 0)
                            }
                            .padding(10)
                            .accessibilityElement(children: .combine)
                        }
                    }
                    .padding(6)
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text("RUN · " + String(run.data.text("goal").prefix(40)).uppercased())
                        .font(KFont.mono(10)).foregroundStyle(K.text3).lineLimit(1)
                    HStack(spacing: KSpace.sm) {
                        StatusBadge(status: run.data.text("status"))
                        if !run.data.text("waitingReason").isEmpty {
                            Text(run.data.text("waitingReason")).font(KFont.caption()).foregroundStyle(K.text2).lineLimit(2)
                        }
                    }
                }
                .padding(KSpace.lg).frame(maxWidth: .infinity, alignment: .leading).kBorder(.top)
            } else {
                EmptyState(icon: "users", title: "No run selected", detail: "Open a run to follow the team.")
                Spacer()
            }
        }
    }
}
