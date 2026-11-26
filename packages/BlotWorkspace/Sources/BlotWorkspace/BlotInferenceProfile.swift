import Foundation

public enum BlotModelTier: String, CaseIterable, Codable, Sendable {
    case mini, pro, max

    public var title: String { "Ori " + rawValue.capitalized }
    public var providerID: String {
        switch self {
        case .mini: "GigaChat-2"
        case .pro: "GigaChat-2-Pro"
        case .max: "GigaChat-2-Max"
        }
    }
}

public enum BlotModelEffort: String, CaseIterable, Codable, Sendable {
    case light, medium, high, extra

    func reviewTokens(within allowance: Int) -> Int {
        switch self {
        case .light: 0
        case .medium: min(128, allowance / 12)
        case .high: min(384, allowance / 6)
        case .extra: min(768, allowance / 3)
        }
    }

    var reviewInstruction: String {
        switch self {
        case .light: ""
        case .medium: "Identify the main requirements and one decisive check."
        case .high: "Check the requirements, assumptions and relevant edge cases."
        case .extra: "Check constraints, inconsistencies and edge cases. Identify an independent way to verify the result."
        }
    }
}

public struct BlotInferenceProfile: Codable, Equatable, Sendable {
    public let tier: BlotModelTier
    public let effort: BlotModelEffort
    public init(tier: BlotModelTier, effort: BlotModelEffort = .medium) {
        self.tier = tier
        self.effort = tier == .mini ? .light : effort
    }
}

public protocol BlotSelectableModel: ChatModel {
    func selecting(_ tier: BlotModelTier) -> any ChatModel
}

/// Review uses the same model and quota as the answer. It has no tools or side effects.
public struct BlotInferenceModel: ChatModel {
    private let base: any ChatModel
    private let effort: BlotModelEffort

    public init(provider: any BlotSelectableModel, profile: BlotInferenceProfile) {
        base = provider.selecting(profile.tier)
        effort = profile.tier == .mini ? .light : profile.effort
    }

    public func stream(request: ChatModelRequest) -> AsyncThrowingStream<ChatModelEvent, Error> {
        let budget = effort.reviewTokens(within: request.maximumOutputTokens)
        guard budget > 0, let user = request.messages.last, user.role == "user",
              !user.content.isEmpty, request.maximumOutputTokens >= 256 else { return base.stream(request: request) }
        return AsyncThrowingStream { continuation in
            let worker = Task {
                do {
                    try Task.checkCancellation()
                    let review = ChatModelRequest(messages: [
                        .init(role: "system", content: "Write a brief checklist of concrete acceptance criteria for the task below. Return only checks, in the user's language. Never perform the task or claim a result. " + effort.reviewInstruction),
                        .init(role: "user", content: String(user.content.prefix(4096)))
                    ], maximumOutputTokens: budget)
                    var notes = ""
                    var reviewUsage: ChatModelUsage?
                    for try await event in base.stream(request: review) {
                        try Task.checkCancellation()
                        switch event {
                        case .text(let text): notes += text
                        case .usage(let value): reviewUsage = value
                        case .failure(let error): throw error
                        case .toolCall: throw ChatModelError.invalidStream
                        case .finished: break
                        }
                    }
                    try Task.checkCancellation()
                    var messages = request.messages
                    if !notes.isEmpty {
                        messages.insert(.init(role: "assistant", content: "Draft checklist:\n" + String(notes.prefix(4096))), at: messages.count - 1)
                    }
                    let final = ChatModelRequest(messages: messages, tools: request.tools,
                        maximumOutputTokens: request.maximumOutputTokens - budget, requiredTool: request.requiredTool)
                    for try await event in base.stream(request: final) {
                        try Task.checkCancellation()
                        if case .usage(let finalUsage) = event, let reviewUsage {
                            let input = finalUsage.inputTokens.addingReportingOverflow(reviewUsage.inputTokens)
                            let output = finalUsage.outputTokens.addingReportingOverflow(reviewUsage.outputTokens)
                            guard !input.overflow, !output.overflow else { throw ChatModelError.invalidStream }
                            continuation.yield(.usage(try ChatModelUsage(inputTokens: input.partialValue, outputTokens: output.partialValue)))
                        } else { continuation.yield(event) }
                    }
                    continuation.finish()
                } catch { continuation.finish(throwing: error) }
            }
            continuation.onTermination = { _ in worker.cancel() }
        }
    }
}
