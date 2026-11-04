import SwiftUI

/// Isolated host required by XCTest on physical iOS devices; never opens the product's workspace.
@main
struct WorkspaceVerificationApp: App {
    var body: some Scene {
        WindowGroup { Text("Blot workspace verification").padding() }
    }
}
