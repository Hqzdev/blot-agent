import BlotDomain
import Foundation
import Testing
@testable import BlotWorkspace

private struct TextEditorFixture {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let repository: WorkspaceRepository
    let files: WorkspaceFileService
    let documents: WorkspaceDocumentService
    init() async throws {
        repository = try await workspaceTestRepository(url: directory.appendingPathComponent("workspace.sqlite"))
        let identity = try await repository.localIdentity()
        files = .init(repository: repository, identity: identity, directory: directory.appendingPathComponent("Files"))
        documents = .init(repository: repository, identity: identity, files: files)
    }
}

private struct TextEditorCase: Sendable {
    let name: String
    let type: String
    let body: String
}

@Test(arguments: [
    TextEditorCase(name: "settings.json", type: "application/json", body: "{\"project\":\"Orion\"}"),
    TextEditorCase(name: "report.md", type: "text/markdown", body: "# Orion\n\nOriginal report\n"),
    TextEditorCase(name: "script.js", type: "application/javascript", body: "const project = 'Orion';\n"),
    TextEditorCase(name: "settings.yaml", type: "application/yaml", body: "project: Orion\n"),
    TextEditorCase(name: "README", type: "text/plain", body: "Orion\n")
])
private func textEditorPreservesFormatOriginalAndExactEditedSource(_ item: TextEditorCase) async throws {
    let f = try await TextEditorFixture(); defer { cleanupWorkspaceTestStorage(f.directory) }
    let id = UUID()
    _ = try await f.files.store(commandID: id, name: item.name, mediaType: item.type, data: Data(item.body.utf8))
    var document = try #require(try await f.documents.load(id))
    #expect(document.fileExtension == (item.name as NSString).pathExtension)
    #expect(document.mediaType == item.type)
    document.body += "Updated\n"
    let saved = try await f.documents.save(document, commandID: UUID())
    #expect(String(data: try await f.files.data(for: id), encoding: .utf8) == item.body)
    #expect(String(data: try await f.files.data(for: saved.exportArtifactID), encoding: .utf8) == document.body)
    #expect(try await f.documents.load(id) == saved)
    #expect(WorkspaceEditableDocument.isInternalArtifact(name: "blot-render-" + id.uuidString + "-" + saved.revisionID!.uuidString + (saved.fileExtension.isEmpty ? "" : "." + saved.fileExtension)))
}

@Test private func arbitraryUTF8TextCanBeImportedButBinaryDataCannotBecomeEditableText() async throws {
    let f = try await TextEditorFixture(); defer { cleanupWorkspaceTestStorage(f.directory) }
    let source = f.directory.appendingPathComponent("config.customtext")
    try Data("name = Orion\n".utf8).write(to: source)
    let id = try await f.files.importFile(commandID: UUID(), source: source)
    #expect(try await f.documents.load(id)?.fileExtension == "customtext")
    let binary = f.directory.appendingPathComponent("archive.unknown")
    try Data([0, 1, 2, 255]).write(to: binary)
    await #expect(throws: WorkspaceFileError.unsupportedType) { _ = try await f.files.importFile(commandID: UUID(), source: binary) }
}

@Test private func oldDocumentSourcesStillDecodeWithoutNewFileMetadata() throws {
    let original = WorkspaceEditableDocument(id: UUID(), title: "Legacy report", kind: .markdown, body: "Report body")
    let data = try JSONEncoder().encode(original)
    let decoded = try JSONDecoder().decode(WorkspaceEditableDocument.self, from: data)
    #expect(decoded.sourceFileExtension == nil && decoded.sourceMediaType == nil)
    #expect(String(data: try decoded.rendered(), encoding: .utf8) == "# Legacy report\n\nReport body\n")
}
