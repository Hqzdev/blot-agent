import BlotDomain
import BlotWorkspace
import Foundation
import Darwin

@main
struct DirectModelVerification {
    static func main() async {
        do { try await verify() }
        catch {
            if let modelError = error as? ChatModelError {
                print("GigaChat verification failed: \(modelError)")
                exit(1)
            }
            let failure = error as NSError
            print("GigaChat verification failed: domain=\(failure.domain), code=\(failure.code)")
            exit(1)
        }
    }
    static func verify() async throws {
        guard (2...3).contains(CommandLine.arguments.count) else { fatalError("Pass the generated personal-dev plist path") }
        let configuration = try AppleInstallationConfiguration.decode(Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1])))
        let model = try configuration.makeModel()
        if CommandLine.arguments.contains("--tool-loop") { try await verifyToolLoop(model: model); return }
        var text = ""
        var usage: ChatModelUsage?
        var finished = false
        for try await event in model.stream(request: .init(messages: [.init(role: "user", content: "Ответь одним словом: работает")], maximumOutputTokens: 32)) {
            switch event {
            case .text(let delta): text += delta
            case .usage(let value): usage = value
            case .finished(.stop): finished = true
            case .failure(let error): throw error
            default: throw ChatModelError.unsupportedResponse
            }
        }
        guard finished, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw ChatModelError.interrupted }
        // Only counts leave this harness. Neither secrets nor model response bodies enter the log.
        print("GigaChat direct stream: completed; characters=\(text.count); usage=\(usage?.totalTokens.description ?? "unknown")")
    }
    static func verifyToolLoop(model: GigaChatModel) async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let repository = try WorkspaceRepository(url: directory.appendingPathComponent("verification.sqlite"))
        do {
            let identity = try await repository.localIdentity()
            let agentID = try await WorkspaceAgentService(repository: repository, identity: identity).save(commandID: UUID(),
                draft: .init(name: "Verifier", instructions: "Use document_create for requested documents. Answer briefly after creating the result.",
                    modelID: "gigachat", toolIDs: ["document_create"]))
            let configuration = try await repository.projection(identity: identity).configurations.first!
            let chat = WorkspaceChatService(repository: repository, identity: identity)
            let conversationID = try await chat.createConversation(commandID: UUID(), title: "Integration verification", agentID: agentID)
            let prompt = "Создай Markdown документ с именем Проверка и содержимым Тест. Обязательно вызови document_create с format markdown. Затем кратко подтверди результат."
            let messageID = try await chat.sendMessage(commandID: UUID(), conversationID: conversationID, content: prompt)
            let source = try await repository.record(BlotV3.Message.self, id: messageID, workspaceID: identity.workspaceID)!
            let responseID = UUID()
            _ = try await WorkspaceResponseRecorder(repository: repository, identity: identity).begin(id: responseID, replyingTo: source, agentID: agentID)
            let files = WorkspaceFileService(repository: repository, identity: identity, directory: directory.appendingPathComponent("Attachments"))
            let registry = try WorkspaceToolRegistry(providers: [WorkspaceLocalTools(repository: repository, identity: identity, files: files)])
            let runtime = WorkspaceModelRuntime(repository: repository, identity: identity, pool: .init(), tools: registry)
            try await runtime.generate(source: source, responseID: responseID,
                request: .init(messages: [.init(role: "system", content: configuration.instructions), .init(role: "user", content: prompt)], maximumOutputTokens: 256),
                model: model, modelID: "gigachat", configuration: configuration, budgetTokenLimit: 10000, emit: { _ in })
            let projection = try await repository.projection(identity: identity)
            guard projection.artifacts.count == 1, projection.modelSteps.count >= 2,
                  projection.modelSteps.allSatisfy({ $0.state == .completed }),
                  let artifact = projection.artifacts.first, try await files.text(for: artifact.metadata.id).contains("Тест") else {
                throw ChatModelError.unsupportedResponse
            }
            let tokens = projection.modelSteps.compactMap { step -> Int? in
                guard let input = step.inputTokens, let output = step.outputTokens else { return nil }
                return input + output
            }.reduce(0, +)
            print("GigaChat direct tool loop: completed; steps=\(projection.modelSteps.count); documents=\(projection.artifacts.count); usage=\(tokens)")
            try await repository.close()
            try FileManager.default.removeItem(at: directory)
        } catch {
            try? await repository.close()
            try? FileManager.default.removeItem(at: directory)
            throw error
        }
    }

}
