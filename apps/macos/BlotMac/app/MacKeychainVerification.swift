#if DEBUG
import AppKit
import BlotWorkspace
import Foundation

/// Exercises the shipping bundle's signature, not an unsigned command-line host.
enum MacKeychainVerification {
    static var requested: Bool { ProcessInfo.processInfo.arguments.contains("--verify-keychain") }

    static func run() async {
        let keychain = WorkspaceKeychain(service: "dev.blot.verification." + UUID().uuidString)
        let name = "synthetic-test-key"
        let value = Data(UUID().uuidString.utf8)
        var result: [String: Any] = ["passed": false]
        do {
            try await keychain.remove(name)
            try await keychain.write(value, name: name)
            guard try await keychain.read(name) == value else { throw WorkspaceCredentialError.invalidValue }
            try await keychain.remove(name)
            guard try await keychain.read(name) == nil else { throw WorkspaceCredentialError.invalidValue }
            result = ["passed": true]
        } catch {
            try? await keychain.remove(name)
            if case let WorkspaceCredentialError.unavailable(status) = error { result["OSStatus"] = status }
            else { result["errorType"] = String(reflecting: type(of: error)) }
        }
        if var data = try? JSONSerialization.data(withJSONObject: result, options: [.sortedKeys]) {
            data.append(0x0a)
            FileHandle.standardOutput.write(data)
        }
        NSApp.terminate(nil)
    }
}
#endif
