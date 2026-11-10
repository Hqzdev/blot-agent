import BlotDomain
import BlotWorkspace
import Foundation
#if os(macOS)
import AppKit
#endif

@MainActor
final class WorkspaceSessionDirectoryPicker {
    #if os(macOS)
    private var pending: NSOpenPanel?
    func choose(purpose: String, name: String?) async throws -> WorkspaceDirectoryChoice? {
        guard pending == nil else { throw NativeExecutionError.busy }
        let panel = NSOpenPanel(); panel.canChooseFiles = false; panel.canChooseDirectories = true
        panel.canCreateDirectories = true; panel.allowsMultipleSelection = false
        panel.title = name.map { "Создать папку «\($0)»" } ?? "Доступ агента к папке"
        panel.message = purpose + "\n\n" + (name.map { "Выберите родительскую папку. Blot создаст в ней «\($0)» и разрешит агенту читать и изменять файлы только в этой папке." } ?? "Выбранная папка будет доступна этому агенту для чтения и изменения файлов в текущем чате.")
        panel.prompt = name == nil ? "Разрешить доступ" : "Создать и разрешить"
        pending = panel; defer { pending = nil }
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                panel.begin { result in
                    guard result == .OK, let selected = panel.url else { continuation.resume(returning: nil); return }
                    do {
                        guard selected.startAccessingSecurityScopedResource() else { throw NativeExecutionError.accessDenied }
                        defer { selected.stopAccessingSecurityScopedResource() }
                        let parent = selected.standardizedFileURL.resolvingSymlinksInPath()
                        let target = name.map { parent.appendingPathComponent($0, isDirectory: true) } ?? parent
                        if let name {
                            guard !name.isEmpty, name != ".", name != "..", !name.contains("/"), !name.contains("\\"), !name.contains("\0") else { throw NativeExecutionError.invalidRequest }
                            if FileManager.default.fileExists(atPath: target.path) {
                                guard try target.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey]).isDirectory == true,
                                      target.resolvingSymlinksInPath().path == target.path else { throw NativeExecutionError.accessDenied }
                            } else { try FileManager.default.createDirectory(at: target, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700]) }
                        }
                        let bookmark = try target.bookmarkData(options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil)
                        continuation.resume(returning: .init(path: target.path, bookmark: bookmark))
                    } catch { continuation.resume(throwing: error) }
                }
            }
        } onCancel: { _Concurrency.Task { @MainActor in panel.cancel(nil) } }
    }
    func stop() { pending?.cancel(nil) }
    #else
    func choose(purpose: String, name: String?) async throws -> WorkspaceDirectoryChoice? { throw NativeExecutionError.unavailable }
    func stop() {}
    #endif
}

@MainActor
extension LocalWorkspaceService {
    func sessionFileService() async throws -> WorkspaceSessionFileService? {
        guard automaticSessionFiles else { return nil }
        if let sessionFiles { return sessionFiles }
        let picker = sessionDirectoryPicker
        let value = WorkspaceSessionFileService(repository: repository, identity: try await context(), credentials: mcpCredentials,
            makeExecutor: makeNativeExecutor, choose: { purpose, name in try await picker.choose(purpose: purpose, name: name) })
        sessionFiles = value; return value
    }
    func sessionFileTools() async throws -> WorkspaceSessionFileTools {
        try await WorkspaceSessionFileTools(service: sessionFileService(), repository: repository, identity: context())
    }
    func restoreBuiltInTools(projection: WorkspaceProjection) async throws {
        var builtIn: Set<String> = []
        if automaticSessionFiles { builtIn.formUnion(WorkspaceSessionFileCatalog.toolIDs); builtIn.formUnion(["file_read", "document_create"]) }
        if automaticBrowserAccess { builtIn.formUnion(WorkspaceBrowserCatalog.toolIDs) }
        guard !builtIn.isEmpty else { return }
        let service = try await WorkspaceAgentService(repository: repository, identity: context())
        for agent in projection.agents {
            let tools = agent.accessMode == .observe ? builtIn.subtracting(["document_create"]) : builtIn
            guard !projection.conflicts.contains(where: { !$0.resolved && $0.recordId == agent.metadata.id }),
                  let revision = try WorkspaceAgentConfigurationResolver().resolve(agentID: agent.metadata.id, projection: projection),
                  !tools.isSubset(of: Set(revision.toolIds)) else { continue }
            _ = try await service.save(commandID: UUID(), agentID: agent.metadata.id, expectedVersion: agent.metadata.version,
                draft: .init(name: agent.name, instructions: revision.instructions, avatarShape: agent.avatarShape, avatarColor: agent.avatarColor,
                    modelID: revision.modelId, toolIDs: Set(revision.toolIds).union(tools).sorted(), accessMode: agent.accessMode))
        }
    }
    func startSessionFiles() async {
        guard automaticSessionFiles else { return }
        do {
            guard let service = try await sessionFileService() else { return }
            await service.resume(); _ = try await service.prepare()
            if sessionMirror == nil {
                sessionMirror = try await WorkspaceSessionMirror(repository: repository, identity: context(), files: service, indexURL: sessionMirrorIndex, artifacts: fileService())
            }
            await sessionMirror?.start(); sessionFilesFailure = nil
        } catch { sessionFilesFailure = (error as? NativeExecutionError)?.localizedDescription ?? "Не удалось подготовить рабочую папку Blot." }
    }
    static func eraseSessionFiles(ownerID: UUID) async throws {
        #if os(macOS)
        let executor = NativeXPCClient(); defer { _Concurrency.Task { await executor.stopAll() } }
        _ = try await executor.request(.init(.workspaceEraseOwner,
            command: NativeCommand(projectID: UUID(), root: "/", executable: "/usr/bin/true"), parameters: ["owner_id": ownerID.uuidString]))
        #endif
    }
    static func prepareDefaultWorkspaceRoot() async throws {
        #if os(macOS)
        let executor = NativeXPCClient()
        do {
            _ = try await executor.request(.init(.workspacePrepare, command: NativeCommand(projectID: UUID(), root: "/", executable: "/usr/bin/true")))
            await executor.stopAll()
        } catch { await executor.stopAll(); throw error }
        #endif
    }
}
