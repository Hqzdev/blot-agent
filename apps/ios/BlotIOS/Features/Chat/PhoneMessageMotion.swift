import BlotDomain
import SwiftUI

enum PhoneMessageMotion {
    static let spring = Animation.spring(response: 0.44, dampingFraction: 0.76)

    static func arrival(for role: BlotV3.MessageRole, reduced: Bool) -> AnyTransition {
        guard !reduced else { return .opacity }
        let outgoing = role == .user
        return .asymmetric(
            insertion: .scale(scale: outgoing ? 0.88 : 0.82, anchor: outgoing ? .bottomTrailing : .bottomLeading)
                .combined(with: .offset(x: outgoing ? 10 : -6, y: outgoing ? 34 : 18))
                .combined(with: .opacity),
            removal: .opacity)
    }
}
