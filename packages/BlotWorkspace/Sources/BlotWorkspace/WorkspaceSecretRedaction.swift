import Foundation

extension ChatJSON {
    func redactingSecrets(_ secrets: [String]) -> ChatJSON {
        let secrets = secrets.filter { !$0.isEmpty }
        func text(_ value: String) -> String { secrets.reduce(value) { $0.replacingOccurrences(of: $1, with: "[redacted]") } }
        switch self {
        case .string(let value): return .string(text(value))
        case .array(let values): return .array(values.map { $0.redactingSecrets(secrets) })
        case .object(let values):
            var result: [String: ChatJSON] = [:]
            for (key, value) in values { result[text(key)] = value.redactingSecrets(secrets) }
            return .object(result)
        default: return self
        }
    }
}
