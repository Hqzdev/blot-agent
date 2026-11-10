import BlotDomain
import BlotWorkspace
import CoreGraphics
import CoreText
import Foundation
import ImageIO
import PDFKit

private actor FileServiceModel: ChatModel {
    private(set) var requests: [ChatModelRequest] = []
    func events(_ request: ChatModelRequest) -> [ChatModelEvent] {
        requests.append(request)
        if request.messages.last(where: { $0.role == "user" })?.content == "Create CSV", !request.messages.contains(where: { $0.role == "tool" }) {
            return [.toolCall(.init(id: "output", name: "document_create", arguments: .object(["name": .string("Report"), "format": .string("csv"),
                "headers": .array([.string("Item"), .string("Total")]), "rows": .array([.array([.string("Invoice"), .string("1250")])])]))), .finished(.toolCalls)]
        }
        return [.text("Read the available text and completed the request."), .finished(.stop)]
    }
    nonisolated func stream(request: ChatModelRequest) -> AsyncThrowingStream<ChatModelEvent, Error> {
        AsyncThrowingStream { continuation in
            _Concurrency.Task { for event in await self.events(request) { continuation.yield(event) }; continuation.finish() }
        }
    }
}

@main struct VerifyFileExecution {
    static func require(_ value: Bool, _ message: String) { precondition(value, message) }
    static func image(blank: Bool = false) throws -> CGImage {
        let context = CGContext(data: nil, width: 1400, height: 700, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
        context.setFillColor(CGColor(gray: 1, alpha: 1)); context.fill(CGRect(x: 0, y: 0, width: 1400, height: 700))
        if !blank {
            let attrs: [NSAttributedString.Key: Any] = [NSAttributedString.Key(kCTFontAttributeName as String): CTFontCreateWithName("Helvetica" as CFString, 62, nil),
                NSAttributedString.Key(kCTForegroundColorAttributeName as String): CGColor(gray: 0, alpha: 1)]
            context.textPosition = CGPoint(x: 90, y: 450)
            CTLineDraw(CTLineCreateWithAttributedString(NSAttributedString(string: "INVOICE 2026 Total 1250", attributes: attrs)), context)
        }
        return context.makeImage()!
    }
    static func png(_ image: CGImage) -> Data {
        let data = NSMutableData()
        let destination = CGImageDestinationCreateWithData(data, "public.png" as CFString, 1, nil)!
        CGImageDestinationAddImage(destination, image, nil); precondition(CGImageDestinationFinalize(destination))
        return data as Data
    }
    static func scan(_ image: CGImage) -> Data {
        let data = NSMutableData(); var rect = CGRect(x: 0, y: 0, width: 1400, height: 700)
        let context = CGContext(consumer: CGDataConsumer(data: data)!, mediaBox: &rect, nil)!
        for _ in 0..<2 { context.beginPDFPage(nil); context.draw(image, in: rect); context.endPDFPage() }
        context.closePDF(); return data as Data
    }
    @MainActor static func wait(_ condition: () async throws -> Bool) async throws {
        let end = ContinuousClock.now.advanced(by: .seconds(8))
        while try await !condition(), ContinuousClock.now < end { try await _Concurrency.Task.sleep(for: .milliseconds(10)) }
        require(try await condition(), "Timed out")
    }
    @MainActor static func main() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("files.sqlite")
        let repository = try WorkspaceRepository(url: url), identity = try await repository.localIdentity()
        let agent = try await WorkspaceAgentService(repository: repository, identity: identity).save(commandID: UUID(),
            draft: .init(name: "Reader", instructions: "Use attached source material", modelID: "gigachat", toolIDs: ["file_read", "document_create"]))
        let chat = try await WorkspaceChatService(repository: repository, identity: identity).createConversation(commandID: UUID(), title: "Files", agentID: agent)
        let model = FileServiceModel()
        let service = try LocalWorkspaceService(databaseURL: url, repository: repository, identity: identity, maximumOutputTokens: 64, makeModel: { _ in model })
        _ = try await service.load()
        let source = directory.appendingPathComponent("invoice.png")
        let bytes = png(try image()); try bytes.write(to: source)
        let library = try await service.importWorkspaceFile(source)
        let read = try await service.readWorkspaceFile(library, startPage: 1, pageCount: 1)
        require(read.usedOCR && read.content.contains("1250"), "Library OCR failed")
        require(try Data(contentsOf: await service.fileURL(library)) == bytes, "Image binary changed")
        print("PASS: library import, original binary and real local OCR through service")

        var form = WorkspaceForm(); form.composer.draft = "Summarize the attachment"; form.composer.attachments = [source]
        let send = WorkspaceRequest(action: .send, form: form, selectedAgentID: agent, selectedConversationID: chat, selectedRecordID: nil)
        let sent = try await service.execute(send, snapshot: service.currentSnapshot())
        let message = sent.messages.first(where: { $0.metadata.id == send.commandID })!
        try FileManager.default.removeItem(at: source)
        for try await _ in try await service.responses(to: message) {}
        let request = await model.requests.last!
        require(request.messages.contains(where: { $0.content.contains("untrusted source material") && $0.content.contains("1250") }), "OCR context or source boundary missing")
        require(request.messages.last?.content == "Summarize the attachment", "Attachment replaced the user request")
        require(try await service.currentSnapshot().messages.last?.delivery == .completed, "Attachment response failed")
        print("PASS: attachment send survives source deletion and supplies quoted OCR context")

        let pdfSource = directory.appendingPathComponent("scan.pdf"); try scan(try image()).write(to: pdfSource)
        let pdf = try await service.importWorkspaceFile(pdfSource)
        let page = try await service.readWorkspaceFile(pdf, startPage: 2, pageCount: 1)
        require(page.totalPages == 2 && page.startPage == 2 && page.nextPage == nil && page.content.contains("1250"), "Scanned PDF pagination failed")
        let blank = directory.appendingPathComponent("blank.png"); try png(try image(blank: true)).write(to: blank)
        form.composer.draft = "Say hello"; form.composer.attachments = [blank]
        let blankSend = WorkspaceRequest(action: .send, form: form, selectedAgentID: agent, selectedConversationID: chat, selectedRecordID: nil)
        let blankState = try await service.execute(blankSend, snapshot: service.currentSnapshot())
        for try await _ in try await service.responses(to: blankState.messages.first(where: { $0.metadata.id == blankSend.commandID })!) {}
        require(await model.requests.last!.messages.contains(where: { $0.content.contains("No text was found") }), "Blank scan error not included in context")
        print("PASS: scanned PDF page navigation and unreadable text do not break chat")

        form.composer.attachments = []; form.composer.draft = "Create CSV"
        let create = WorkspaceRequest(action: .send, form: form, selectedAgentID: agent, selectedConversationID: chat, selectedRecordID: nil)
        let createState = try await service.execute(create, snapshot: service.currentSnapshot())
        for try await _ in try await service.responses(to: createState.messages.first(where: { $0.metadata.id == create.commandID })!) {}
        let outputState = try await service.currentSnapshot()
        let response = outputState.messages.last(where: { $0.role == .assistant && $0.delivery == .completed })!
        require(response.artifactIds.count == 1, "Generated file was not attached to response")
        let csvID = response.artifactIds[0]
        require(try await service.fileText(csvID).contains("\"Item\",\"Total\""), "CSV lost columns")
        print("PASS: structured CSV output is attached to the assistant response")

        let start = WorkspaceRequest(action: .start, form: form, selectedAgentID: agent, selectedConversationID: chat, selectedRecordID: nil)
        _ = try await service.execute(start, snapshot: service.currentSnapshot())
        try await wait { try await service.currentSnapshot().tasks?.contains(where: { $0.state == .completed }) == true }
        let tasks = try await service.currentSnapshot()
        let taskID = tasks.tasks!.first!.metadata.id
        require(tasks.artifacts.contains(where: { $0.execution?.taskId == taskID }), "Generated task artifact lost ownership")
        await service.stopAll()
        let reopened = try LocalWorkspaceService(databaseURL: url, identity: identity, makeModel: { _ in model })
        _ = try await reopened.load()
        require(try await reopened.readWorkspaceFile(library, startPage: 1, pageCount: 1).content.contains("1250"), "OCR did not survive reopen")
        require(try await reopened.fileText(csvID).contains("1250"), "Export did not survive reopen")
        await reopened.stopAll()
        print("PASS: task output provenance and durable files/OCR after reopening")
    }
}
