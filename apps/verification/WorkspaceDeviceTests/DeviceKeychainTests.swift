import BlotWorkspace
import Foundation
import Testing

@Test func signedHostCanPersistAndRemoveDeviceOnlyKeychainValue() async throws {
    let keychain = WorkspaceKeychain(service: "dev.blot.verification." + UUID().uuidString)
    let name = "synthetic-test-key"
    let value = Data("Synthetic verification value; not an account credential".utf8)
    do {
        try await keychain.write(value, name: name)
        #expect(try await keychain.read(name) == value)
        try await keychain.remove(name)
        #expect(try await keychain.read(name) == nil)
    } catch {
        try? await keychain.remove(name)
        throw error
    }
}
