import BlotDomain
import Foundation

public struct AppleUncertainAction: Identifiable, Sendable {
    public let invocation: BlotV3.ToolInvocation
    public let preparation: BlotV3.PreparedAction
    public var id: UUID { invocation.metadata.id }
}

public enum AppleInvocationRecovery {
    public static func pending(plugin: ApplePluginID, deviceID: UUID, actions: [BlotV3.PreparedAction], invocations: [BlotV3.ToolInvocation]) -> [AppleUncertainAction] {
        let prefix = "apple_" + plugin.rawValue.dropFirst(6) + "_"
        return invocations.compactMap { invocation in
            guard invocation.state == .unknown, invocation.execution.executorDeviceId == deviceID,
                  let action = actions.first(where: { $0.metadata.id == invocation.preparedActionId && $0.toolId.hasPrefix(prefix) }) else { return nil }
            return .init(invocation: invocation, preparation: action)
        }
    }
}
