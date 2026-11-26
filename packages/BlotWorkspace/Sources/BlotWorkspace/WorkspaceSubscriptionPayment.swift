import BlotDomain
import Foundation

public struct WorkspaceSubscriptionPayment: Codable, Equatable, Sendable {
    public let paymentId: UUID
    public let plan: String
    public let status: String
    public let test: Bool
}

extension WorkspaceConversationCardService {
    /// Called only with the authenticated billing server's response, never a browser redirect.
    public func applyVerifiedPayment(cardID: UUID, payment: WorkspaceSubscriptionPayment) async throws {
        guard payment.test, ["premium", "super", "ultra"].contains(payment.plan),
              ["pending", "waiting_for_capture", "succeeded", "canceled"].contains(payment.status) else { throw WorkspaceStorageError.invalidParameters }
        let command = try WorkspaceCoding.encode(payment)
        _ = try await repository.execute(commandID: UUID(), command: command, identity: identity) { tx in
            let old = try tx.require(BlotV3.ConversationCard.self, id: cardID)
            guard old.kind == "subscription" else { throw WorkspaceStorageError.invalidRecord }
            let response = WorkspaceCardResponse(action: "payment_status", value: String(decoding: command, as: UTF8.self))
            let json = String(decoding: try JSONEncoder().encode(response), as: UTF8.self)
            if old.responseJSON == json { return cardID }
            let card = try BlotV3.ConversationCard(metadata: tx.metadata(id: cardID, now: Date(), replacing: old.metadata),
                messageId: old.messageId, operationId: old.operationId, executorDeviceId: old.executorDeviceId, kind: old.kind,
                state: payment.status == "succeeded" || payment.status == "canceled" ? "answered" : "pending",
                expiresAt: old.expiresAt, payloadJSON: old.payloadJSON, responseJSON: json, updatedByDeviceId: tx.identity.deviceID)
            try tx.put(card, expectedVersion: old.metadata.version)
            return cardID
        }
    }
}
