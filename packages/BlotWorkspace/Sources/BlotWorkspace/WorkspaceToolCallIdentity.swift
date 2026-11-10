import CryptoKit
import Foundation

/// Stable across restarts and shared with action reconciliation; changing a model call ID creates a new action.
public enum WorkspaceToolCallIdentity {
    public static func actionID(workspaceID: UUID, sourceID: UUID, callID: String) -> UUID {
        var bytes = Array(SHA256.hash(data: Data((workspaceID.uuidString + ":" + sourceID.uuidString + ":" + callID).utf8)).prefix(16))
        bytes[6] = (bytes[6] & 15) | 0x80; bytes[8] = (bytes[8] & 63) | 0x80
        return UUID(uuid: (bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7], bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]))
    }
}
