import BlotDomain
import CoreGraphics
import CoreText
import Foundation
import ImageIO
import PDFKit
import Testing
@testable import BlotWorkspace

private final class CountingTextRecognizer: WorkspaceTextRecognizing, @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    var calls: Int { lock.withLock { count } }
    let text: String
    init(_ text: String = "Invoice 42") { self.text = text }
    func recognize(_ image: CGImage, orientation: CGImagePropertyOrientation) throws -> String {
        lock.withLock { count += 1; return text }
    }
}
private struct OCRFiles {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let repository: WorkspaceRepository
    let identity: WorkspaceIdentity
    let files: WorkspaceFileService
    let recognizer: CountingTextRecognizer
    var storage: URL { directory.appendingPathComponent("Files") }
    init(text: String = "Invoice 42") async throws {
        repository = try await workspaceTestRepository(url: directory.appendingPathComponent("workspace.sqlite"))
        identity = try await repository.localIdentity()
        recognizer = CountingTextRecognizer(text)
        files = WorkspaceFileService(repository: repository, identity: identity, directory: directory.appendingPathComponent("Files"), recognizer: recognizer)
    }
    func importImage() async throws -> UUID {
        let source = directory.appendingPathComponent("invoice.PNG")
        try png(printedImage()).write(to: source)
        return try await files.importFile(commandID: UUID(), source: source)
    }
}

private func printedImage(_ lines: [String] = ["INVOICE 2026", "Total 1250"]) throws -> CGImage {
    let width = 1400, height = 700
    let context = try #require(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue))
    context.setFillColor(CGColor(gray: 1, alpha: 1)); context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    for (index, text) in lines.enumerated() {
        let attrs: [NSAttributedString.Key: Any] = [NSAttributedString.Key(kCTFontAttributeName as String): CTFontCreateWithName("Helvetica" as CFString, 62, nil),
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): CGColor(gray: 0, alpha: 1)]
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: attrs))
        context.textPosition = CGPoint(x: 90, y: 540 - index * 110); CTLineDraw(line, context)
    }
    return try #require(context.makeImage())
}
private func png(_ image: CGImage) throws -> Data {
    let data = NSMutableData()
    let writer = try #require(CGImageDestinationCreateWithData(data, "public.png" as CFString, 1, nil))
    CGImageDestinationAddImage(writer, image, nil)
    #expect(CGImageDestinationFinalize(writer))
    return data as Data
}
private func scannedPDF(_ image: CGImage, pages: Int = 1) throws -> Data {
    let data = NSMutableData()
    var rect = CGRect(x: 0, y: 0, width: image.width, height: image.height)
    let consumer = try #require(CGDataConsumer(data: data))
    let context = try #require(CGContext(consumer: consumer, mediaBox: &rect, nil))
    for _ in 0..<pages { context.beginPDFPage(nil); context.draw(image, in: rect); context.endPDFPage() }
    context.closePDF()
    return data as Data
}

@Test func imageImportPreservesBinaryAndOCRCacheSurvivesReopenButNeverBypassesIntegrity() async throws {
    let f = try await OCRFiles(); defer { cleanupWorkspaceTestStorage(f.directory) }
    let id = try await f.importImage()
    #expect(f.recognizer.calls == 0)
    let artifact = try #require(try await f.repository.record(BlotV3.Artifact.self, id: id, workspaceID: f.identity.workspaceID))
    #expect(artifact.mediaType == "image/png" && artifact.relativePath.hasSuffix(".png"))
    let original = try await f.files.data(for: id)
    #expect(original.starts(with: [137, 80, 78, 71]))
    let first = try await f.files.read(id)
    #expect(first.usedOCR && first.content.contains("Invoice 42") && !first.truncated)
    #expect(try await f.files.read(id) == first && f.recognizer.calls == 1)
    let freshRecognizer = CountingTextRecognizer("Unexpected second recognition")
    let reopened = WorkspaceFileService(repository: f.repository, identity: f.identity, directory: f.storage, recognizer: freshRecognizer)
    #expect(try await reopened.read(id) == first && freshRecognizer.calls == 0)
    try Data("tampered".utf8).write(to: await f.files.url(for: id))
    await #expect(throws: WorkspaceFileError.integrityMismatch) { _ = try await reopened.read(id) }
}

@Test func scannedAndMixedPDFsKeepOrderAndOnlyRecognizeImagePages() async throws {
    let f = try await OCRFiles(text: "Текст скана 42"); defer { cleanupWorkspaceTestStorage(f.directory) }
    let native = try #require(PDFDocument(data: WorkspaceDocumentWriter().pdf(title: "Native report", body: "Original layer")))
    let scan = try #require(PDFDocument(data: scannedPDF(printedImage())))
    let mixed = PDFDocument()
    mixed.insert(try #require(native.page(at: 0)), at: 0)
    mixed.insert(try #require(scan.page(at: 0)), at: 1)
    let source = f.directory.appendingPathComponent("mixed.pdf")
    try #require(mixed.dataRepresentation()).write(to: source)
    let id = try await f.files.importFile(commandID: UUID(), source: source)
    let first = try await f.files.read(id, pageCount: 1)
    #expect(first.content.contains("Original layer") && !first.usedOCR && first.nextPage == 2 && first.truncated)
    #expect(f.recognizer.calls == 0)
    let second = try await f.files.read(id, startPage: 2, pageCount: 1)
    #expect(second.content.contains("[Page 2]") && second.content.contains("Текст скана 42") && second.usedOCR && second.nextPage == nil)
    #expect(f.recognizer.calls == 1)
}

@Test func nativeVisionActuallyRecognizesPNGAndScannedRotatedPDF() throws {
    let extractor = WorkspaceFileTextExtractor()
    let image = try printedImage()
    let result = try extractor.extract(png(image), mediaType: "image/png")
    #expect(result.content.contains("INVOICE 2026") && result.content.contains("1250") && result.usedOCR)
    let document = try #require(PDFDocument(data: scannedPDF(image)))
    document.page(at: 0)?.rotation = 90
    let pdf = try extractor.extract(#require(document.dataRepresentation()), mediaType: "application/pdf")
    #expect(pdf.content.contains("INVOICE 2026") && pdf.content.contains("1250") && pdf.usedOCR)
}

@Test func invalidImagesAndPDFsLeaveNoMetadataAndBlankScansRemainPreviewable() async throws {
    let f = try await OCRFiles(text: ""); defer { cleanupWorkspaceTestStorage(f.directory) }
    for ext in ["png", "pdf"] {
        let source = f.directory.appendingPathComponent("broken." + ext)
        try Data("not a document".utf8).write(to: source)
        await #expect(throws: WorkspaceFileError.self) { _ = try await f.files.importFile(commandID: UUID(), source: source) }
    }
    #expect(try await f.repository.projection(identity: f.identity).artifacts.isEmpty)
    let id = try await f.importImage()
    await #expect(throws: WorkspaceFileError.noRecognizableText) { _ = try await f.files.read(id) }
    #expect(try await f.files.data(for: id).count > 0)
}

@Test func textExtractionBoundsPagesCharactersAndRegeneratesCorruptCache() async throws {
    let f = try await OCRFiles(); defer { cleanupWorkspaceTestStorage(f.directory) }
    let id = try await f.importImage()
    let result = try await f.files.read(id, maximumCharacters: 6)
    #expect(result.content.count == 6 && result.truncated)
    let cache = f.storage.appendingPathComponent("ExtractedText/v1")
    let file = try #require(FileManager.default.contentsOfDirectory(at: cache, includingPropertiesForKeys: nil).first)
    try Data("{".utf8).write(to: file)
    #expect(try await f.files.read(id).content.contains("Invoice 42") && f.recognizer.calls == 2)
    await #expect(throws: WorkspaceStorageError.invalidParameters) { _ = try await f.files.read(id, startPage: 2) }
    await #expect(throws: WorkspaceStorageError.invalidParameters) { _ = try await f.files.read(id, pageCount: 21) }
    await #expect(throws: WorkspaceStorageError.invalidParameters) { _ = try await f.files.read(id, maximumCharacters: 48_001) }
    let source = f.directory.appendingPathComponent("large.txt")
    try Data(String(repeating: "Я", count: 48_010).utf8).write(to: source)
    let textID = try await f.files.importFile(commandID: UUID(), source: source)
    #expect(try await f.files.read(textID).truncated)
    #expect(try await f.files.text(for: textID).hasSuffix("[Truncated]"))
}

@Test func canceledFileReadDoesNotInvokeOCR() async throws {
    let f = try await OCRFiles(); defer { cleanupWorkspaceTestStorage(f.directory) }
    let id = try await f.importImage()
    let operation = _Concurrency.Task { () throws -> WorkspaceExtractedText in
        withUnsafeCurrentTask { $0?.cancel() }
        return try await f.files.read(id)
    }
    await #expect(throws: CancellationError.self) { _ = try await operation.value }
    #expect(f.recognizer.calls == 0)
}

@Test func fileToolRequiresExplicitAttachmentAndReturnsOCRMetadata() async throws {
    let f = try await OCRFiles(); defer { cleanupWorkspaceTestStorage(f.directory) }
    let id = try await f.importImage()
    let chats = WorkspaceChatService(repository: f.repository, identity: f.identity)
    let chat = try await chats.createConversation(commandID: UUID(), title: "OCR")
    let source = try await chats.sendMessage(commandID: UUID(), conversationID: chat, content: "Read only", artifactIDs: [id])
    let tools = try WorkspaceToolRegistry(providers: [WorkspaceLocalTools(repository: f.repository, identity: f.identity, files: f.files)])
    let call = ChatToolCall(id: "read", name: "file_read", arguments: .object(["artifact_id": .string(id.uuidString)]))
    let context = WorkspaceToolContext(sourceMessageID: source, taskID: nil, allowedToolIDs: ["file_read"])
    let result = try await tools.execute(call, context: context)
    guard case .object(let fields) = result else { Issue.record("Expected text result"); return }
    #expect(fields["used_ocr"] == .bool(true) && fields["total_pages"] == .number(1))
    let otherSource = try await chats.sendMessage(commandID: UUID(), conversationID: chat, content: "No attachments")
    await #expect(throws: WorkspaceStorageError.permissionDenied) { _ = try await tools.execute(call, context: .init(sourceMessageID: otherSource, taskID: nil, allowedToolIDs: ["file_read"])) }
}

private actor FileResultModel: ChatModel {
    nonisolated func stream(request: ChatModelRequest) -> AsyncThrowingStream<ChatModelEvent, Error> {
        AsyncThrowingStream { continuation in
            if request.messages.contains(where: { $0.role == "tool" }) {
                continuation.yield(.text("Created the CSV.")); continuation.yield(.finished(.stop))
            } else {
                continuation.yield(.toolCall(.init(id: "csv", name: "document_create", arguments: .object([
                    "name": .string("Report"), "format": .string("csv"), "headers": .array([.string("Name"), .string("Amount")]),
                    "rows": .array([.array([.string("Alice, Inc"), .string("1250")]), .array([.string("Bob"), .string(" =SUM(A1:A2)")])])]))))
                continuation.yield(.finished(.toolCalls))
            }
            continuation.finish()
        }
    }
}

@Test func generatedCSVIsStructuredAttachedToReplyAndOwnedByItsTask() async throws {
    let f = try await OCRFiles(); defer { cleanupWorkspaceTestStorage(f.directory) }
    let agent = try await WorkspaceAgentService(repository: f.repository, identity: f.identity).save(commandID: UUID(), draft: .init(name: "Writer", instructions: "Create documents", toolIDs: ["document_create"]))
    let chat = try await WorkspaceChatService(repository: f.repository, identity: f.identity).createConversation(commandID: UUID(), title: "Files", agentID: agent)
    let task = try await WorkspaceTaskService(repository: f.repository, identity: f.identity).create(commandID: UUID(), conversationID: chat, agentID: agent, goal: "Create a CSV", executorDeviceID: f.identity.deviceID, budgetTokenLimit: 100_000)
    let tools = try WorkspaceToolRegistry(providers: [WorkspaceLocalTools(repository: f.repository, identity: f.identity, files: f.files)])
    try await WorkspaceTaskExecution(repository: f.repository, identity: f.identity, pool: .init(), tools: tools, maximumOutputTokens: 64).run(taskID: task, model: FileResultModel())
    let projection = try await f.repository.projection(identity: f.identity)
    let artifact = try #require(projection.artifacts.first)
    let reply = try #require(projection.messages.first(where: { $0.role == .assistant && $0.delivery == .completed }))
    #expect(reply.artifactIds == [artifact.metadata.id] && artifact.execution?.taskId == task)
    #expect(projection.tasks.first?.state == .completed)
    let csv = try await f.files.text(for: artifact.metadata.id)
    #expect(csv.contains("\"Name\",\"Amount\"") && csv.contains("\"Alice, Inc\",\"1250\""))
    #expect(csv.contains("\"' =SUM(A1:A2)\""))
    // Attaching the same output again is idempotent while the response is running.
    let source = try #require(projection.messages.first(where: { $0.role == .user }))
    let recorder = WorkspaceResponseRecorder(repository: f.repository, identity: f.identity)
    let response = try await recorder.begin(id: UUID(), replyingTo: source, agentID: agent)
    _ = try await recorder.attach(artifact.metadata.id, to: response.metadata.id)
    #expect(try await recorder.attach(artifact.metadata.id, to: response.metadata.id).artifactIds.count == 1)
}

@Test func mismatchedCSVColumnsFailBeforeArtifactPersistenceAndFormulaWhitespaceIsEscaped() throws {
    let writer = WorkspaceDocumentWriter()
    #expect(throws: WorkspaceStorageError.invalidParameters) { _ = try writer.csv(headers: ["A", "B"], rows: [["only one"]]) }
    let csv = String(decoding: try writer.csv(headers: ["Text"], rows: [["\t=1+1"], ["\u{feff} +1"], ["normal"]]), as: UTF8.self)
    #expect(csv.contains("'\t=1+1") && csv.contains("'\u{feff} +1") && csv.contains("\"normal\""))
}

@Test func jpegAndMultipageTIFFPreserveMediaTypesAndUseImageDecoding() async throws {
    let f = try await OCRFiles(); defer { cleanupWorkspaceTestStorage(f.directory) }
    for (ext, uti, media, count) in [("jpg", "public.jpeg", "image/jpeg", 1), ("tiff", "public.tiff", "image/tiff", 2)] {
        let data = NSMutableData()
        let destination = try #require(CGImageDestinationCreateWithData(data, uti as CFString, count, nil))
        for _ in 0..<count { CGImageDestinationAddImage(destination, try printedImage(), nil) }
        #expect(CGImageDestinationFinalize(destination))
        let source = f.directory.appendingPathComponent("image." + ext)
        try (data as Data).write(to: source)
        let id = try await f.files.importFile(commandID: UUID(), source: source)
        let artifact = try #require(try await f.repository.record(BlotV3.Artifact.self, id: id, workspaceID: f.identity.workspaceID))
        #expect(artifact.mediaType == media)
        let result = try await f.files.read(id)
        #expect(result.usedOCR && result.totalPages == count)
        #expect(try await f.files.data(for: id) == data as Data)
    }
}
