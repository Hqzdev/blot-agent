import CryptoKit
import Foundation

/// The QR carries only discovery credentials and a fingerprint pinning the signed invitation.
nonisolated struct WorkspacePairingLink: Equatable, Sendable {
    private static let prefix = "blot-connect:2:"
    private static let byteCount = 88
    let id: UUID
    let secret: Data
    private let invitationDigest: Data
    let expiresAt: Date

    init(invitation: String, now: Date = Date()) {
        id = UUID()
        secret = SymmetricKey(size: .bits256).withUnsafeBytes { Data($0) }
        invitationDigest = Data(SHA256.hash(data: Data(invitation.utf8)))
        expiresAt = Date(timeIntervalSince1970: floor(now.timeIntervalSince1970) + 600)
    }

    private init(id: UUID, secret: Data, invitationDigest: Data, expiresAt: Date) {
        self.id = id; self.secret = secret
        self.invitationDigest = invitationDigest; self.expiresAt = expiresAt
    }

    var encoded: String {
        var uuid = id.uuid
        var expiry = UInt64(expiresAt.timeIntervalSince1970).bigEndian
        var bytes = withUnsafeBytes(of: &uuid) { Data($0) }
        bytes.append(secret)
        bytes.append(invitationDigest)
        withUnsafeBytes(of: &expiry) { bytes.append(contentsOf: $0) }
        return Self.prefix + bytes.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    func verifies(_ invitation: String) -> Bool {
        invitation.hasPrefix("blot-pair:") && invitation.utf8.count <= 3000
            && Data(SHA256.hash(data: Data(invitation.utf8))) == invitationDigest
    }

    static func decode(_ value: String, now: Date = Date()) throws -> Self {
        guard value.hasPrefix(prefix), value.utf8.count == prefix.utf8.count + 118 else {
            throw WorkspacePairingFailure.invalidQR
        }
        let base64 = String(value.dropFirst(prefix.count))
            .replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/") + "=="
        guard let bytes = Data(base64Encoded: base64), bytes.count == byteCount else {
            throw WorkspacePairingFailure.invalidQR
        }
        var uuid: uuid_t = (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)
        withUnsafeMutableBytes(of: &uuid) { $0.copyBytes(from: bytes.prefix(16)) }
        let expiry = bytes.suffix(8).reduce(UInt64(0)) { ($0 << 8) | UInt64($1) }
        let date = Date(timeIntervalSince1970: TimeInterval(expiry))
        guard date > now, date <= now.addingTimeInterval(601) else { throw WorkspacePairingFailure.expired }
        let link = Self(id: UUID(uuid: uuid), secret: Data(bytes[16..<48]),
            invitationDigest: Data(bytes[48..<80]), expiresAt: date)
        guard link.encoded == value else { throw WorkspacePairingFailure.invalidQR }
        return link
    }
}

nonisolated enum WorkspacePairingFailure: Error, Equatable {
    case invalidQR, expired, unavailable, disconnected, wrongCode, tooManyAttempts, invalidMessage
}

nonisolated enum WorkspacePairingMessage: Codable, Sendable {
    case invitation(String)
    case claim(String)
    case ready
    case confirm(String)
    case approval(String)
    case received
}
