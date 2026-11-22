import Foundation
import Testing
@testable import BlotWorkspace

private actor InferenceProbe {
    var requests: [ChatModelRequest] = []
    func record(_ request: ChatModelRequest) { requests.append(request) }
}

private struct InferenceProvider: BlotSelectableModel {
    let probe: InferenceProbe
    var tier: BlotModelTier = .mini

    func selecting(_ tier: BlotModelTier) -> any ChatModel { Self(probe: probe, tier: tier) }
    func stream(request: ChatModelRequest) -> AsyncThrowingStream<ChatModelEvent, Error> {
        AsyncThrowingStream { continuation in
            Task {
                await probe.record(request)
                continuation.yield(.text(tier.providerID))
                continuation.yield(.usage(try! ChatModelUsage(inputTokens: 20, outputTokens: 5)))
                continuation.yield(.finished(.stop))
                continuation.finish()
            }
        }
    }
}

@Test func modelProfilesSelectProviderAndReviewBudget() async throws {
    for tier in BlotModelTier.allCases {
        for effort in BlotModelEffort.allCases {
            let probe = InferenceProbe()
            let profile = BlotInferenceProfile(tier: tier, effort: effort)
            let model = BlotInferenceModel(provider: InferenceProvider(probe: probe), profile: profile)
            let tool = ChatToolDefinition(name: "lookup", description: "Search", parameters: .object([:]))
            let request = ChatModelRequest(messages: [.init(role: "user", content: "Compare A and B")],
                                           tools: [tool], maximumOutputTokens: 4096)
            var text = ""
            var usage: ChatModelUsage?
            for try await event in model.stream(request: request) {
                if case .text(let part) = event { text += part }
                if case .usage(let total) = event { usage = total }
            }
            let calls = await probe.requests
            let budget = tier == .mini ? 0 : [BlotModelEffort.light: 0, .medium: 128, .high: 384, .extra: 768][effort]!
            #expect(text == tier.providerID)
            #expect(calls.count == (budget == 0 ? 1 : 2))
            #expect(usage?.totalTokens == calls.count * 25)
            #expect(calls.last?.tools == [tool])
            #expect(calls.last?.maximumOutputTokens == 4096 - budget)
            if budget > 0 {
                #expect(calls.first?.maximumOutputTokens == budget)
                #expect(calls.first?.tools.isEmpty == true)
            }
        }
    }
}
