import Foundation

struct PhoneTokenUsage: Codable, Identifiable {
    let id: UUID
    let date: Date
    let modelID: String
    let agentName: String
    let inputTokens: Int
    var outputTokens: Int
    var totalTokens: Int { inputTokens + outputTokens }

}
