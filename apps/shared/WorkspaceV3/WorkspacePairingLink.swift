import Foundation

nonisolated struct WorkspacePairingLink: Codable, Equatable, Sendable {
    let version: Int
    let id: UUID
    let secret: String
    let invitation: String
    let expiresAt: Date

    init(invitation: String, now: Date = Date()) {
        version = 1
        id = UUID()
        secret = UUID().uuidString + UUID().uuidString
        self.invitation = invitation
        expiresAt = now.addingTimeInterval(600)
    }

    var encoded: String {
        get throws { "blot-connect:" + (try JSONEncoder().encode(self)).base64EncodedString() }
    }

    static func decode(_ value: String, now: Date = Date()) throws -> Self {
        guard value.utf8.count <= 4096, value.hasPrefix("blot-connect:"),
              let bytes = Data(base64Encoded: String(value.dropFirst(13))) else { throw WorkspacePairingFailure.invalidQR }
        let link = try JSONDecoder().decode(Self.self, from: bytes)
        guard link.version == 1, link.secret.utf8.count == 72,
              link.invitation.hasPrefix("blot-pair:"), link.invitation.utf8.count <= 3000 else {
            throw WorkspacePairingFailure.invalidQR
        }
        guard link.expiresAt > now, link.expiresAt <= now.addingTimeInterval(601) else { throw WorkspacePairingFailure.expired }
        return link
    }
}

nonisolated enum WorkspacePairingFailure: Error, Equatable {
    case invalidQR, expired, unavailable, disconnected, wrongCode, tooManyAttempts, invalidMessage
}

nonisolated enum WorkspacePairingMessage: Codable, Sendable {
    case claim(String)
    case ready
    case confirm(String)
    case approval(String)
    case received
}
