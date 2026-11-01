import BlotAPI
import BlotDesign
import SwiftUI

/// «14 · Motes — Team graph»: who works with whom, by organisation, communication or dependencies.
/// Selecting a node or an edge opens its source record in the inspector.
struct TeamGraphView: View {
    @Environment(AppState.self) private var app
    private var graph: WorkspaceGraph? {
        guard let records = app.workspace.records, let id = UUID(uuidString: app.selectedRunID),
            records.find("RUN", id: id) != nil
        else { return nil }
        let mode: WorkspaceGraphMode =
            app.graphMode == .dependencies
            ? .dependencies : app.graphMode == .organization ? .organization : .communication
        return WorkspaceGraph(records: records, runID: id, mode: mode)
    }
    var body: some View {
        @Bindable var app = app
        VStack(spacing: 0) {
            HStack(spacing: KSpace.sm) {
                KSegmented(options: GraphMode.allCases, selection: $app.graphMode, label: \.rawValue, title: "Graph view")
                Spacer()
                KButton(title: "Conversation", icon: "messages-square", kind: .ghost) { app.openWorkRun(app.selectedRunID) }
                    .disabled(UUID(uuidString: app.selectedRunID) == nil)
            }
            .padding(.horizontal, KSpace.lg).padding(.vertical, KSpace.md)
            .kBorder(.bottom)
            if app.workspace.loading && graph == nil {
                ContentSkeleton()
            } else if let graph, !graph.nodes.isEmpty {
                RunGraphCanvas(graph: graph)
                    .background(GraphGrid())
                    .id(app.graphMode)
                    .transition(.opacity)
                HStack(spacing: KSpace.lg) {
                    Text("Built from assignments, messages, reviews and dependencies. Select a node or an edge to see its source record.")
                        .font(KFont.caption()).foregroundStyle(K.text3)
                    Spacer()
                    Text("\(graph.nodes.count) nodes · \(graph.edges.count) links").font(KFont.mono(11)).foregroundStyle(K.text3)
                }
                .padding(.horizontal, KSpace.lg).padding(.vertical, 10).kBorder(.top)
            } else {
                EmptyState(icon: "network", title: "The graph is empty",
                           detail: UUID(uuidString: app.selectedRunID) == nil
                               ? "Choose a run in the sidebar."
                               : "Tasks and specialists appear after you approve the plan.")
                    .frame(maxHeight: .infinity)
            }
        }
        .kAnimation(value: app.graphMode)
    }
}

private struct GraphGrid: View {
    var body: some View {
        Canvas { context, size in
            let step: CGFloat = 24
            var path = Path()
            for x in stride(from: 0, through: size.width, by: step) {
                for y in stride(from: 0, through: size.height, by: step) {
                    path.addEllipse(in: CGRect(x: x - 0.75, y: y - 0.75, width: 1.5, height: 1.5))
                }
            }
            context.fill(path, with: .color(K.text.opacity(0.06)))
        }
        .accessibilityHidden(true)
    }
}

private struct RunGraphCanvas: View {
    @Environment(AppState.self) private var app
    let graph: WorkspaceGraph
    private func point(_ id: String) -> CGPoint {
        let index = graph.nodes.firstIndex { $0.id == id } ?? 0
        return CGPoint(x: 140 + (index % 3) * 280, y: 75 + (index / 3) * 160)
    }
    private func selected(_ selection: GraphSelection) -> Bool {
        app.inspectorVisible && app.graphSelection == selection
    }
    var body: some View {
        ScrollView([.horizontal, .vertical]) {
            ZStack(alignment: .topLeading) {
                ForEach(graph.edges) { edge in
                    let from = point(edge.from)
                    let to = point(edge.to)
                    let active = selected(.edge(edge.source))
                    GraphConnection(from: from, to: to).stroke(
                        active ? K.text : K.text3.opacity(0.65),
                        style: StrokeStyle(lineWidth: active ? 2 : 1.5, lineCap: .round, dash: active ? [] : [5, 4]))
                }
                ForEach(graph.edges) { edge in
                    let from = point(edge.from)
                    let to = point(edge.to)
                    Button { select(.edge(edge.source)) } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "arrow.right").font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(K.text2).accessibilityHidden(true)
                            Text(edge.label).font(KFont.ui(11)).foregroundStyle(K.text2).lineLimit(1)
                        }
                        .padding(.horizontal, 8).frame(height: 24)
                        .background(Rectangle().fill(K.bg))
                        .overlay(Rectangle().strokeBorder(selected(.edge(edge.source)) ? K.text : K.borderStrong,
                                                          lineWidth: selected(.edge(edge.source)) ? 2 : 1))
                    }
                    .buttonStyle(KIconButtonStyle()).kFocusRing(radius: 0)
                    .position(x: (from.x + to.x) / 2, y: (from.y + to.y) / 2)
                    .help(edge.source)
                    .accessibilityLabel("Link: \(edge.label)")
                }
                ForEach(graph.nodes) { node in
                    let active = selected(.node(node.id))
                    let status = BackendStatus(node.status)
                    Button { select(.node(node.id)) } label: {
                        HStack(spacing: 10) {
                            FaceAvatar(role: .backendRole(node.role), size: 34)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(node.title).font(KFont.label()).foregroundStyle(K.text).lineLimit(2)
                                HStack(spacing: 6) {
                                    Image(systemName: status.tone.icon).font(.system(size: 10, weight: .semibold))
                                        .foregroundStyle(status.tone.color).accessibilityHidden(true)
                                    Text(status.label + " · " + (node.kind == "TASK" ? "task" : "specialist"))
                                        .font(KFont.mono(11)).foregroundStyle(K.text2).lineLimit(1)
                                }
                            }.frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .padding(EdgeInsets(top: 10, leading: 10, bottom: 10, trailing: 12))
                        .frame(width: 236, height: 72)
                        .background(RoundedRectangle(cornerRadius: K.rPopover, style: .continuous).fill(K.surface))
                        .overlay(RoundedRectangle(cornerRadius: K.rPopover, style: .continuous)
                            .strokeBorder(active ? K.text : K.borderStrong, lineWidth: active ? 2 : 1))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(KIconButtonStyle()).kFocusRing(radius: K.rPopover)
                    .position(point(node.id))
                    .accessibilityLabel("\(node.title), \(status.label)")
                    .accessibilityAddTraits(active ? .isSelected : [])
                }
            }.frame(width: 850, height: CGFloat(max(1, (graph.nodes.count + 2) / 3) * 160))
                .padding(KSpace.lg)
        }
    }
    private func select(_ selection: GraphSelection) {
        app.graphSelection = selection
        app.inspectorVisible = true
        app.shell.rightVisible = true
    }
}

private struct GraphConnection: Shape {
    let from: CGPoint
    let to: CGPoint
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: from)
        let middle = (from.y + to.y) / 2
        path.addCurve(to: to, control1: CGPoint(x: from.x, y: middle), control2: CGPoint(x: to.x, y: middle))
        let direction = atan2(to.y - from.y, to.x - from.x)
        path.move(to: CGPoint(x: to.x - cos(direction - 0.5) * 10, y: to.y - sin(direction - 0.5) * 10))
        path.addLine(to: to)
        path.addLine(to: CGPoint(x: to.x - cos(direction + 0.5) * 10, y: to.y - sin(direction + 0.5) * 10))
        return path
    }
}
