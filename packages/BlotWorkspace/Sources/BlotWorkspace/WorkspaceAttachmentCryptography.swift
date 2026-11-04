import CryptoKit
import Foundation

public struct WorkspaceAttachmentDescriptor: Encodable, Equatable, Sendable {
    public static let chunkBytes = 192 * 1024
    public let workspaceID: UUID
    public let artifactID: UUID
    public let hash: String
    public let byteCount: Int
    public let keyEpoch: Int64
    public var chunkCount: Int { max(1, (byteCount + Self.chunkBytes - 1) / Self.chunkBytes) }
    public var blobID: UUID {
        WorkspaceLogicalID.make(kind: "EncryptedAttachment", workspaceID: workspaceID,
            parts: [artifactID.uuidString, hash, String(keyEpoch)])
    }
    public init(workspaceID: UUID, artifactID: UUID, hash: String, byteCount: Int, keyEpoch: Int64) throws {
        guard hash.range(of: #"^[0-9a-f]{64}$"#, options: .regularExpression) != nil,
              (0...32 * 1024 * 1024).contains(byteCount), keyEpoch > 0 else { throw WorkspaceSyncError.invalidChange }
        self.workspaceID = workspaceID; self.artifactID = artifactID; self.hash = hash; self.byteCount = byteCount; self.keyEpoch = keyEpoch
    }
    func validate(index: Int, plaintextBytes: Int) throws {
        guard index >= 0, index < chunkCount, plaintextBytes == min(Self.chunkBytes, max(0, byteCount - index * Self.chunkBytes)) else {
            throw WorkspaceSyncError.invalidChange
        }
    }
}

extension WorkspaceSyncCryptography {
    public func encryptAttachmentChunk(_ data: Data, descriptor: WorkspaceAttachmentDescriptor, index: Int) throws -> Data {
        try descriptor.validate(index: index, plaintextBytes: data.count)
        let key = try attachmentKey(descriptor)
        let nonce = try attachmentNonce(index)
        let sealed = try AES.GCM.seal(data, using: key, nonce: nonce, authenticating: attachmentHeader(descriptor, index: index))
        guard let ciphertext = sealed.combined else { throw WorkspaceSyncError.invalidChange }
        return ciphertext
    }
    public func decryptAttachmentChunk(_ ciphertext: Data, descriptor: WorkspaceAttachmentDescriptor, index: Int) throws -> Data {
        guard ciphertext.count <= WorkspaceAttachmentDescriptor.chunkBytes + 28 else { throw WorkspaceSyncError.invalidChange }
        let sealed = try AES.GCM.SealedBox(combined: ciphertext)
        guard Data(sealed.nonce) == Data(try attachmentNonce(index)) else { throw WorkspaceSyncError.invalidChange }
        let result = try AES.GCM.open(sealed, using: attachmentKey(descriptor), authenticating: attachmentHeader(descriptor, index: index))
        try descriptor.validate(index: index, plaintextBytes: result.count)
        return result
    }
    private func attachmentNonce(_ index: Int) throws -> AES.GCM.Nonce {
        guard index >= 0, index < 512 else { throw WorkspaceSyncError.invalidChange }
        return try AES.GCM.Nonce(data: Data(repeating: 0, count: 4) + WorkspaceDeviceKeys.integer(Int64(index)))
    }
    private func attachmentHeader(_ descriptor: WorkspaceAttachmentDescriptor, index: Int) throws -> Data {
        struct Binding: Encodable { let descriptor: WorkspaceAttachmentDescriptor; let index: Int }
        return try WorkspaceCoding.encode(Binding(descriptor: descriptor, index: index))
    }
}
