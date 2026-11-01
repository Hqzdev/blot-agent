import BlotAPI
import BlotDesign
import SwiftUI

struct PhoneApprovalsView: View {
    let client: BackendClient
    @State private var actions: [BackendEntity<BackendJSON>] = []
    @State private var questions: [BackendEntity<BackendJSON>] = []
    @State private var customAnswers: [UUID: String] = [:]
    @State private var error: String?
    @State private var loading = true
    @State private var submitting: Set<UUID> = []
    @State private var commandError: String?
    nonisolated private struct Grant: Encodable, Sendable { let id: UUID; let seconds = 300; let uses = 1 }
    nonisolated private struct Answer: Encodable, Sendable { let id: UUID; let answer: String }
    var body: some View {
        List {
            if loading {
                BlotLoadingState("Loading decisions…").phoneRow()
            }
            if let error {
                BlotErrorState(error) { Task { await refresh() } }.phoneRow()
            }
            if let commandError { PhoneErrorText(commandError).phoneRow() }
            ForEach(actions.filter { $0.data.text("status") == "PREPARED" }, id: \.id) { row in
                VStack(alignment: .leading, spacing: BlotSpace.s8) {
                    Label(row.data.text("capability"), systemImage: "exclamationmark.triangle")
                        .blotFont(.body, weight: .semibold).foregroundStyle(BlotColor.text)
                    if case .object(let value) = row.data, case .object(let arguments) = value["arguments"] {
                        if case .string(let path) = arguments["path"] { Text(path).font(.body.monospaced()).textSelection(.enabled) }
                        if case .string(let content) = arguments["content"] { Text(content).font(.caption.monospaced()).lineLimit(12).textSelection(.enabled) }
                        if case .string(let program) = arguments["program"] {
                            let args: [String] = { if case .array(let list) = arguments["arguments"] { return list.compactMap { if case .string(let arg) = $0 { return arg }; return nil } }; return [] }()
                            Text(([program] + args).joined(separator: " ")).font(.body.monospaced()).textSelection(.enabled)
                        }
                        if case .string(let remote) = arguments["remote"] { Text("Remote: " + remote) }
                        if case .array(let urls) = arguments["pushUrls"] {
                            ForEach(Array(urls.enumerated()), id: \.offset) { entry in if case .string(let url) = entry.element { Text(url).font(.caption.monospaced()).textSelection(.enabled) } }
                        }
                        if case .string(let sha) = arguments["expectedCommit"] { Text("Commit: " + sha).font(.caption.monospaced()).textSelection(.enabled) }
                        if case .string(let hash) = arguments["snapshotHash"] { Text("Changes SHA-256: " + hash).font(.caption.monospaced()).textSelection(.enabled) }
                        if case .string(let value) = arguments["artifactId"], let id = UUID(uuidString: value) {
                            NavigationLink("Inspect accepted changes") { PhoneArtifactView(client: client, id: id) }
                        }
                        if case .string(let refspec) = arguments["refspec"] { Text(refspec).font(.caption.monospaced()) }
                        if case .string(let message) = arguments["message"] { Text(message) }
                    }
                    HStack(spacing: BlotSpace.s8) {
                        Button { grant(row) } label: { Label("Allow once", systemImage: "checkmark") }
                            .buttonStyle(PhoneButtonStyle(kind: .primary, fullWidth: true))
                        Button(role: .destructive) { deny(row) } label: { Label("Deny", systemImage: "xmark") }
                            .buttonStyle(PhoneButtonStyle(kind: .destructive, fullWidth: true))
                    }
                    .padding(.top, BlotSpace.element)
                }
                .padding(.vertical, BlotSpace.element)
                .phoneRow()
                // Several buttons share one row: without this, a tap on the row triggers all of them.
                .buttonStyle(.borderless)
                .disabled(submitting.contains(row.id))
                .overlay(alignment: .trailing) {
                    if submitting.contains(row.id) { ProgressView().accessibilityLabel("Saving decision") }
                }
            }
            ForEach(questions.filter { $0.data.flag("open") }, id: \.id) { row in
                VStack(alignment: .leading, spacing: BlotSpace.s8) {
                    Label(row.data.text("question"), systemImage: "questionmark.circle")
                        .blotFont(.body, weight: .semibold).foregroundStyle(BlotColor.text)
                    ForEach(row.data.strings("options"), id: \.self) { option in
                        Button(option) { answer(row, option) }.buttonStyle(PhoneButtonStyle(fullWidth: true))
                    }
                    TextField("Your answer", text: Binding(get: { customAnswers[row.id] ?? "" }, set: { customAnswers[row.id] = $0 }))
                        .blotFont(.body)
                        .padding(.horizontal, BlotSpace.s12)
                        .frame(minHeight: BlotLayout.minimumTapTarget)
                        .blotPanel(fill: BlotColor.canvas, border: BlotColor.hairlineStrong)
                    Button("Send answer") { answer(row, customAnswers[row.id] ?? "") }
                        .buttonStyle(PhoneButtonStyle(kind: .primary, fullWidth: true))
                        .disabled((customAnswers[row.id] ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                .padding(.vertical, BlotSpace.element)
                .phoneRow()
                .buttonStyle(.borderless)
                .disabled(submitting.contains(row.id))
                .overlay(alignment: .trailing) {
                    if submitting.contains(row.id) { ProgressView().accessibilityLabel("Sending answer") }
                }
            }
            if !loading && error == nil && actions.allSatisfy({ $0.data.text("status") != "PREPARED" }) && questions.allSatisfy({ !$0.data.flag("open") }) {
                BlotEmptyState(symbol: "checkmark.shield", title: "Nothing to decide",
                               message: "Approvals and questions from your Mac appear here.")
                    .listRowBackground(Color.clear)
            }
        }
        .phoneList()
        .navigationTitle("Your decisions")
        .refreshable { await refresh() }
        .task(id: client.baseURL) { while !Task.isCancelled { await refresh(); try? await Task.sleep(for: .seconds(1)) } }
    }
    private func refresh() async {
        defer { loading = false }
        do {
            let actions = try await client.records("PREPARED_ACTION", as: BackendJSON.self)
            let questions = try await client.records("CHECKPOINT", as: BackendJSON.self)
            guard !Task.isCancelled else { return }
            self.actions = actions; self.questions = questions; error = nil
        } catch is CancellationError { }
        catch { self.error = error.localizedDescription }
    }
    private func deny(_ action: BackendEntity<BackendJSON>) {
        perform(id: action.id) { _ = try await client.command("permission.deny", payload: ["id": action.id.uuidString], expectedVersion: action.version) }
    }
    private func grant(_ action: BackendEntity<BackendJSON>) {
        perform(id: action.id) { _ = try await client.command("permission.grant", payload: Grant(id: action.id), expectedVersion: action.version) }
    }
    private func answer(_ question: BackendEntity<BackendJSON>, _ value: String) {
        perform(id: question.id) { _ = try await client.command("user.answer", payload: Answer(id: question.id, answer: value), expectedVersion: question.version) }
    }
    private func perform(id: UUID, operation: @escaping () async throws -> Void) {
        guard submitting.insert(id).inserted else { return }
        commandError = nil
        Task {
            defer { submitting.remove(id) }
            do { try await operation(); await refresh() }
            catch { commandError = error.localizedDescription }
        }
    }
}
