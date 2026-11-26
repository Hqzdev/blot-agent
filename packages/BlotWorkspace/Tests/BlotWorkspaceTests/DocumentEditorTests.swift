import BlotDomain
import Foundation
import PDFKit
import Testing
@testable import BlotWorkspace

private struct DocumentEditorFixture {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let repository: WorkspaceRepository
    let identity: WorkspaceIdentity
    let files: WorkspaceFileService
    let documents: WorkspaceDocumentService
    init() async throws {
        repository = try await workspaceTestRepository(url: folder.appendingPathComponent("workspace.sqlite"))
        identity = try await repository.localIdentity()
        files = WorkspaceFileService(repository: repository, identity: identity, directory: folder.appendingPathComponent("Files"))
        documents = .init(repository: repository, identity: identity, files: files)
    }
    func create(_ document: WorkspaceEditableDocument) async throws -> WorkspaceEditableDocument {
        _ = try await files.store(commandID: document.id, name: document.title + "." + document.fileExtension, mediaType: document.mediaType, data: document.rendered())
        try await documents.register(document)
        return try #require(try await documents.load(document.id))
    }
    func clean() { cleanupWorkspaceTestStorage(folder) }
}

@Test func editableDocumentSaveKeepsOriginalAndPersistsLatestRevisionAcrossReopen() async throws {
    let f = try await DocumentEditorFixture(); defer { f.clean() }
    var source = try await f.create(.init(id: UUID(), title: "Отчёт", kind: .pdf, body: "Исходный текст"))
    let original = try await f.files.data(for: source.id)
    source.body = "Изменённый текст, сохранённый внутри Blot"
    let commandID = UUID()
    let saved = try await f.documents.save(source, commandID: commandID)
    #expect(saved.id == source.id && saved.exportArtifactID != source.id)
    #expect(try await f.documents.save(source, commandID: commandID) == saved)
    #expect(try await f.files.data(for: source.id) == original)
    let pdf = try #require(PDFDocument(data: try await f.files.data(for: saved.exportArtifactID)))
    #expect(pdf.string?.contains("Изменённый текст") == true)
    await #expect(throws: WorkspaceStorageError.versionConflict) { _ = try await f.documents.save(source, commandID: UUID()) }
    try await f.repository.close()
    let repository = try await workspaceTestRepository(url: f.folder.appendingPathComponent("workspace.sqlite"))
    let files = WorkspaceFileService(repository: repository, identity: f.identity, directory: f.folder.appendingPathComponent("Files"))
    let reopened = WorkspaceDocumentService(repository: repository, identity: f.identity, files: files)
    #expect(try await reopened.load(source.id) == saved)
}

@Test func editedTablePreservesCellsAndSlideChangesRegenerateEveryPage() async throws {
    let f = try await DocumentEditorFixture(); defer { f.clean() }
    var table = try await f.create(.init(id: UUID(), title: "Бюджет", kind: .table, columns: ["Этап", "Сумма"], rows: [["Дизайн", "12000"]]))
    table.rows[0][1] = "15000"; table.rows.append(["Текст, с запятой", "строка\nдве"])
    let updated = try await f.documents.save(table, commandID: UUID())
    let data = try await f.files.data(for: updated.exportArtifactID)
    #expect(try WorkspaceCSV().rows(String(decoding: data, as: UTF8.self)) == [table.columns] + table.rows)
    var slides = try await f.create(.init(id: UUID(), title: "Слайды", kind: .presentation, slides: [.init(title: "Первый", body: "Начальный текст")]))
    slides.slides[0].body = "Новый текст"
    slides.slides.append(.init(title: "Второй", body: "Добавлен в редакторе"))
    let deck = try await f.documents.save(slides, commandID: UUID())
    let pdf = try #require(PDFDocument(data: try await f.files.data(for: deck.exportArtifactID)))
    #expect(pdf.pageCount == 2)
    #expect(pdf.string?.contains("Новый текст") == true && pdf.string?.contains("Добавлен в редакторе") == true)
}

@Test func invalidEditAndChangedReplayCannotCommitARevision() async throws {
    let f = try await DocumentEditorFixture(); defer { f.clean() }
    var source = try await f.create(.init(id: UUID(), title: "Таблица", kind: .table, columns: ["A", "B"], rows: [["1", "2"]]))
    let before = try await f.repository.records(BlotV3.Artifact.self, workspaceID: f.identity.workspaceID)
    source.rows[0].removeLast()
    await #expect(throws: WorkspaceStorageError.invalidParameters) { _ = try await f.documents.save(source, commandID: UUID()) }
    #expect(try await f.repository.records(BlotV3.Artifact.self, workspaceID: f.identity.workspaceID) == before)
    source.rows = [["3", "4"]]
    let id = UUID()
    _ = try await f.documents.save(source, commandID: id)
    source.title = "Другие параметры"
    await #expect(throws: WorkspaceStorageError.commandConflict) { _ = try await f.documents.save(source, commandID: id) }
}

@Test func previousGeneratedPresentationRecoversStructuredSourceFromItsRecordedCall() async throws {
    let f = try await DocumentEditorFixture(); defer { f.clean() }
    let chat = try await WorkspaceChatService(repository: f.repository, identity: f.identity).createConversation(commandID: UUID(), title: "Legacy")
    let sourceID = try await WorkspaceChatService(repository: f.repository, identity: f.identity).sendMessage(commandID: UUID(), conversationID: chat, content: "Create a presentation")
    let source = try #require(try await f.repository.record(BlotV3.Message.self, id: sourceID, workspaceID: f.identity.workspaceID))
    let responseID = UUID()
    _ = try await WorkspaceResponseRecorder(repository: f.repository, identity: f.identity).begin(id: responseID, replyingTo: source, agentID: nil)
    let step = UUID(), steps = WorkspaceModelStepService(repository: f.repository, identity: f.identity)
    try await steps.begin(id: step, source: source, responseID: responseID, request: .init(messages: [.init(role: "user", content: source.content)]), modelID: "test", configurationID: nil, budgetTokenLimit: 20_000)
    let call = ChatToolCall(id: "legacy-slide", name: "document_create", arguments: .object(["name": .string("Старая презентация"), "format": .string("presentation"), "slides": .array([.object(["title": .string("Слайд 1"), "body": .string("Точное содержимое")])])]))
    try await steps.finish(id: step, state: .completed, calls: [call], usage: nil)
    let artifactID = WorkspaceLogicalID.make(kind: "LocalTool", workspaceID: f.identity.workspaceID, parts: [sourceID.uuidString, call.id])
    let draft = try WorkspaceEditableDocument.generated(id: artifactID, arguments: call.arguments)
    _ = try await f.files.store(commandID: artifactID, name: "Старая презентация.pdf", mediaType: "application/pdf", data: draft.rendered())
    let recovered = try #require(try await f.documents.load(artifactID))
    #expect(recovered.slides == draft.slides && recovered.kind == .presentation)
    var edit = recovered; edit.slides[0].body = "Обновлённый слайд"
    let saved = try await f.documents.save(edit, commandID: UUID())
    #expect(try await f.documents.load(artifactID)?.slides[0].body == "Обновлённый слайд")
    #expect(saved.parents.isEmpty)
}

@Test func documentDraftPreviewDoesNotPublishOrReplaceAnyArtifact() async throws {
    let f = try await DocumentEditorFixture(); defer { f.clean() }
    var source = try await f.create(.init(id: UUID(), title: "Draft preview", kind: .pdf, body: "Saved body"))
    let before = try await f.repository.records(BlotV3.Artifact.self, workspaceID: f.identity.workspaceID)
    source.body = "Unsaved preview body"
    let url = try await f.documents.preview(source)
    #expect(PDFDocument(url: url)?.string?.contains("Unsaved preview body") == true)
    #expect(try await f.repository.records(BlotV3.Artifact.self, workspaceID: f.identity.workspaceID) == before)
    #expect(try await f.documents.load(source.id)?.body == "Saved body")
}
