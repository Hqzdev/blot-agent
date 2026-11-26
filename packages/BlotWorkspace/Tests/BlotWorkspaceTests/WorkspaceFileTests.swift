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

@Test func localPresentationPreservesEverySlideAndItsText() throws {
    let slides = (1...4).map { WorkspacePresentationDocumentWriter.Slide(title: "Слайд \($0)", body: "Только локальные данные.\nЦель: проверка Blot.\nРезультат \($0).") }
    let data = try WorkspacePresentationDocumentWriter().pdf(slides: slides)
    let pdf = try #require(PDFDocument(data: data))
    #expect(pdf.pageCount == 4)
    for index in 0..<4 {
        let page = try #require(pdf.page(at: index))
        #expect(page.bounds(for: .mediaBox).width == 960)
        #expect(page.string?.contains("Слайд \(index + 1)") == true)
        #expect(page.string?.contains("Результат \(index + 1).") == true)
    }
    #expect(throws: WorkspaceStorageError.invalidParameters) { _ = try WorkspacePresentationDocumentWriter().pdf(slides: []) }
    #expect(throws: WorkspaceStorageError.invalidParameters) {
        _ = try WorkspacePresentationDocumentWriter().pdf(slides: [.init(title: "Too long", body: String(repeating: "W", count: 11_000))])
    }
}

@Test func localCSVPreviewRoundTripsQuotedUnicodeAndMultilineCells() throws {
    let headers = ["Имя", "Описание", "Сумма"]
    let rows = [["А, Б", "Первая\nВторая \"строка\"", "12"], ["Тест", "", "=literal"]]
    let data = try WorkspaceDocumentWriter().csv(headers: headers, rows: rows)
    let parsed = try WorkspaceCSV().rows(String(decoding: data, as: UTF8.self))
    #expect(parsed == [headers, rows[0], ["Тест", "", "'=literal"]])
    #expect(throws: WorkspaceFileError.invalidText) { _ = try WorkspaceCSV().rows("\"unclosed") }
    #expect(throws: WorkspaceFileError.invalidText) { _ = try WorkspaceCSV().rows("\"closed\"trailing") }
}

@Test func localPresentationToolPersistsAndReplaysWithoutCloudConnection() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { cleanupWorkspaceTestStorage(directory) }
    let repository = try await workspaceTestRepository(url: directory.appendingPathComponent("workspace.sqlite"))
    let identity = try await repository.localIdentity()
    let files = WorkspaceFileService(repository: repository, identity: identity, directory: directory.appendingPathComponent("Files"))
    let chats = WorkspaceChatService(repository: repository, identity: identity)
    let chat = try await chats.createConversation(commandID: UUID(), title: "Local documents")
    let source = try await chats.sendMessage(commandID: UUID(), conversationID: chat, content: "Create a local presentation without Google")
    let tools = try WorkspaceToolRegistry(providers: [WorkspaceLocalTools(repository: repository, identity: identity, files: files)])
    let call = ChatToolCall(id: "local-slides", name: "document_create", arguments: .object([
        "name": .string("Local deck"), "format": .string("presentation"),
        "slides": .array([.object(["title": .string("Local content"), "body": .string("No Google account or external document service required.")])])
    ]))
    let context = WorkspaceToolContext(sourceMessageID: source, taskID: nil, allowedToolIDs: ["document_create"])
    let result = try await tools.execute(call, context: context)
    #expect(try await tools.execute(call, context: context) == result)
    var changed = call.arguments.mcpFields
    changed["name"] = .string("Changed input")
    await #expect(throws: WorkspaceStorageError.commandConflict) {
        _ = try await tools.execute(.init(id: call.id, name: call.name, arguments: .object(changed)), context: context)
    }
    let raw = try #require(result.mcpFields["artifact_id"]?.mcpString)
    let id = try #require(UUID(uuidString: raw))
    let pdf = try #require(PDFDocument(data: try await files.data(for: id)))
    #expect(pdf.pageCount == 1 && pdf.string?.contains("No Google account") == true)
    #expect(try await repository.records(BlotV3.Artifact.self, workspaceID: identity.workspaceID).filter { !WorkspaceEditableDocument.isInternalArtifact(name: $0.name) }.count == 1)
    #expect(try await repository.records(BlotV3.Connection.self, workspaceID: identity.workspaceID).isEmpty)
}
