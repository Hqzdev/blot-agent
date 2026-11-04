import BlotDomain
import Foundation
import PDFKit
import Testing
@testable import BlotWorkspace

@Test func selectedTextIsCopiedAndStillReadableAfterSourceDisappears() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { cleanupWorkspaceTestStorage(directory) }
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let repository = try await workspaceTestRepository(url: directory.appendingPathComponent("workspace.sqlite"))
    let identity = try await repository.localIdentity()
    let files = WorkspaceFileService(repository: repository, identity: identity, directory: directory.appendingPathComponent("Files"))
    let source = directory.appendingPathComponent("source.md")
    try Data("# Источник\nТочный текст".utf8).write(to: source)
    let commandID = UUID()
    let id = try await files.importFile(commandID: commandID, source: source)
    #expect(try await files.importFile(commandID: commandID, source: source) == id)
    try FileManager.default.removeItem(at: source)
    #expect(try await files.text(for: id) == "# Источник\nТочный текст")
    let record = try #require(try await repository.record(BlotV3.Artifact.self, id: id, workspaceID: identity.workspaceID))
    #expect(record.execution == nil && !record.relativePath.contains("source.md"))
    let url = try await files.url(for: id)
    try Data("tampered".utf8).write(to: url)
    await #expect(throws: WorkspaceFileError.integrityMismatch) { _ = try await files.url(for: id) }
}

@Test func generatedPDFContainsAllPagesAndCSVPreservesCells() throws {
    let writer = WorkspaceDocumentWriter()
    let body = (0..<180).map { "Строка \($0): проверяем перенос текста на следующую страницу." }.joined(separator: "\n")
    let pdf = try writer.pdf(title: "Отчёт", body: body)
    let document = try #require(PDFDocument(data: pdf))
    #expect(document.pageCount > 1)
    let text = (0..<document.pageCount).compactMap { document.page(at: $0)?.string }.joined(separator: "\n")
    #expect(text.contains("Строка 0:") && text.contains("Строка 179:"))
    let csv = String(decoding: try writer.csv(headers: ["Name", "Text"], rows: [["A,B", "Two\nlines"], ["Quote", "\"value\""]]), as: UTF8.self)
    #expect(csv.contains("\"A,B\",\"Two\nlines\""))
    #expect(csv.contains("\"Quote\",\"\"\"value\"\"\""))
}

@Test func oversizedOrUnsupportedImportsDoNotCreateMetadata() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { cleanupWorkspaceTestStorage(directory) }
    let repository = try await workspaceTestRepository(url: directory.appendingPathComponent("workspace.sqlite"))
    let identity = try await repository.localIdentity()
    let files = WorkspaceFileService(repository: repository, identity: identity, directory: directory.appendingPathComponent("Files"), maximumBytes: 8)
    let source = directory.appendingPathComponent("large.txt")
    try Data(repeating: 65, count: 9).write(to: source)
    await #expect(throws: WorkspaceFileError.tooLarge) { _ = try await files.importFile(commandID: UUID(), source: source) }
    await #expect(throws: WorkspaceFileError.unsupportedType) { _ = try await files.importFile(commandID: UUID(), source: source.deletingPathExtension().appendingPathExtension("exe")) }
    #expect(try await repository.records(BlotV3.Artifact.self, workspaceID: identity.workspaceID).isEmpty)
}
