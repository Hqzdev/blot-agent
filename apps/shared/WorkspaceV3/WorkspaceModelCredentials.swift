import Foundation
import Security

/// Device-only credentials. Never included in WorkspaceSnapshot, fixtures or replication.
struct WorkspaceModelCredentials: Codable {
    let endpoint: URL
    let model: String
    let apiKey: String
}

struct WorkspaceModelCredentialStore {
    enum Failure: Error { case keychain(OSStatus), missing }
    private let accountNamespace: String
    init(accountNamespace: String = "default") { self.accountNamespace = accountNamespace }
    private let service = "dev.blot.apple-v1.compatible-model"

    func load() throws -> WorkspaceModelCredentials {
        var query = identity
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { throw Failure.missing }
        guard status == errSecSuccess, let data = result as? Data else { throw Failure.keychain(status) }
        return try JSONDecoder().decode(WorkspaceModelCredentials.self, from: data)
    }

    func save(_ credentials: WorkspaceModelCredentials) throws {
        let data = try JSONEncoder().encode(credentials)
        let attributes: [String: Any] = [kSecValueData as String: data]
        let updated = SecItemUpdate(identity as CFDictionary, attributes as CFDictionary)
        if updated == errSecItemNotFound {
            var item = identity
            item[kSecValueData as String] = data
            item[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            let status = SecItemAdd(item as CFDictionary, nil)
            guard status == errSecSuccess else { throw Failure.keychain(status) }
        } else if updated != errSecSuccess { throw Failure.keychain(updated) }
    }

    private var identity: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
         kSecAttrAccount as String: accountNamespace, kSecAttrSynchronizable as String: false,
         kSecUseDataProtectionKeychain as String: true]
    }
}
