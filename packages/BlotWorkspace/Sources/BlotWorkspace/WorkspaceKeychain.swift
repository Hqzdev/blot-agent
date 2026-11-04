import Foundation
import Security

public enum WorkspaceCredentialError: Error, Equatable, Sendable { case unavailable(OSStatus), invalidValue }

public protocol WorkspaceCredentialStore: Sendable {
    func read(_ name: String) async throws -> Data?
    func write(_ value: Data, name: String) async throws
    func remove(_ name: String) async throws
}

/// System Keychain storage, scoped by service and account. Never exported in snapshots.
/// macOS uses its login Keychain's application ACL; iOS uses device-only Data Protection.
public actor WorkspaceKeychain: WorkspaceCredentialStore {
    private let service: String
    public init(service: String) { self.service = service }
    public func read(_ name: String) throws -> Data? {
        var query = base(name)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var value: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &value)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = value as? Data else { throw WorkspaceCredentialError.unavailable(status) }
        return data
    }
    public func write(_ value: Data, name: String) throws {
        guard !value.isEmpty, value.count <= 1_048_576 else { throw WorkspaceCredentialError.invalidValue }
        let query = base(name)
        var changes: [String: Any] = [kSecValueData as String: value]
        #if !os(macOS)
        changes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        #endif
        var status = SecItemUpdate(query as CFDictionary, changes as CFDictionary)
        if status == errSecItemNotFound {
            status = SecItemAdd(query.merging(changes, uniquingKeysWith: { _, new in new }) as CFDictionary, nil)
        }
        guard status == errSecSuccess else { throw WorkspaceCredentialError.unavailable(status) }
    }
    public func remove(_ name: String) throws {
        let status = SecItemDelete(base(name) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw WorkspaceCredentialError.unavailable(status) }
    }
    private func base(_ name: String) -> [String: Any] {
        var query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service, kSecAttrAccount as String: name]
        #if !os(macOS)
        query[kSecAttrSynchronizable as String] = false
        query[kSecUseDataProtectionKeychain as String] = true
        #endif
        return query
    }
}
