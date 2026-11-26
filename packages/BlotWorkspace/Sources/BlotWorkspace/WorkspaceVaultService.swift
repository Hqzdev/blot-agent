import Foundation

public struct WorkspaceVaultItem: Codable, Equatable, Sendable, Identifiable {
    public enum Kind: String, Codable, CaseIterable, Sendable { case login, card, contact, apiSecret }
    public let id: UUID
    public var version: Int
    public var title: String
    public var kind: Kind
    public var fields: [String: String]
    public var hint: String
    public init(id: UUID = UUID(), version: Int = 0, title: String, kind: Kind, fields: [String: String] = [:], hint: String = "") {
        self.id = id; self.version = version; self.title = title; self.kind = kind; self.fields = fields; self.hint = hint
    }
    public static func fieldNames(_ kind: Kind) -> [String] {
        switch kind {
        case .login: ["url", "username", "password"]
        case .card: ["provider", "reference", "last4", "expiry", "holder"]
        case .contact: ["name", "email", "phone", "address"]
        case .apiSecret: ["service", "secret"]
        }
    }
}

public struct WorkspaceVaultSummary: Equatable, Sendable, Identifiable {
    public let id: UUID
    public let title: String
    public let kind: WorkspaceVaultItem.Kind
    public let hint: String
}

/// The entire small vault is one atomic Keychain value. Neither snapshots nor model tools contain it.
public actor WorkspaceVaultService {
    private let credentials: any WorkspaceCredentialStore
    private let key: String
    private var mutating = false
    public init(credentials: any WorkspaceCredentialStore, ownerID: UUID) {
        self.credentials = credentials; key = "vault:" + ownerID.uuidString
    }
    private func items() async throws -> [WorkspaceVaultItem] {
        guard let data = try await credentials.read(key) else { return [] }
        return try JSONDecoder().decode([WorkspaceVaultItem].self, from: data)
    }
    public func list() async throws -> [WorkspaceVaultSummary] {
        try await items().map { .init(id: $0.id, title: $0.title, kind: $0.kind, hint: $0.hint) }.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }
    public func read(_ id: UUID) async throws -> WorkspaceVaultItem {
        guard let item = try await items().first(where: { $0.id == id }) else { throw WorkspaceStorageError.missingRecord }
        return item
    }
    public func save(_ item: WorkspaceVaultItem) async throws {
        guard !mutating else { throw WorkspaceStorageError.versionConflict }
        mutating = true; defer { mutating = false }
        var saved = try await items()
        let index = saved.firstIndex { $0.id == item.id }
        guard (index.map { saved[$0].version } ?? 0) == item.version else { throw WorkspaceStorageError.versionConflict }
        var updated = item; updated.version += 1
        if let index { saved[index] = updated } else { saved.append(updated) }
        try await persist(saved)
    }
    public func delete(_ id: UUID, expectedVersion: Int) async throws {
        guard !mutating else { throw WorkspaceStorageError.versionConflict }
        mutating = true; defer { mutating = false }
        var saved = try await items()
        guard let index = saved.firstIndex(where: { $0.id == id }), saved[index].version == expectedVersion else { throw WorkspaceStorageError.versionConflict }
        saved.remove(at: index); try await persist(saved)
    }
    public func importLogins(_ imported: [WorkspaceVaultItem]) async throws -> Int {
        guard !mutating else { throw WorkspaceStorageError.versionConflict }
        mutating = true; defer { mutating = false }
        guard !imported.isEmpty, imported.count <= 500, imported.allSatisfy({ $0.kind == .login && $0.version == 0 }) else { throw WorkspaceStorageError.invalidParameters }
        var saved = try await items(); var count = 0
        for var item in imported {
            if saved.contains(where: { $0.kind == .login && $0.fields["url"] == item.fields["url"] && $0.fields["username"] == item.fields["username"] }) { continue }
            item.version = 1; saved.append(item); count += 1
        }
        try await persist(saved); return count
    }
    private func persist(_ items: [WorkspaceVaultItem]) async throws {
        guard items.count <= 500, Set(items.map(\.id)).count == items.count else { throw WorkspaceStorageError.invalidParameters }
        for item in items {
            guard !item.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, item.title.utf8.count <= 800,
                  item.hint.utf8.count <= 4000, Set(item.fields.keys).isSubset(of: Set(WorkspaceVaultItem.fieldNames(item.kind))),
                  item.fields.values.allSatisfy({ $0.utf8.count <= 16_384 }) else { throw WorkspaceStorageError.invalidParameters }
            if item.kind == .card, let last = item.fields["last4"], !last.isEmpty {
                guard last.count == 4, last.allSatisfy(\.isNumber) else { throw WorkspaceStorageError.invalidParameters }
            }
        }
        let data = try JSONEncoder().encode(items)
        guard data.count <= 1_000_000 else { throw WorkspaceStorageError.invalidParameters }
        try await credentials.write(data, name: key)
    }
}

public enum WorkspaceVaultCSV {
    /// Parse the common exported name/url/username/password columns without logging raw input.
    public static func logins(_ text: String) throws -> [WorkspaceVaultItem] {
        guard text.utf8.count <= 1_000_000 else { throw WorkspaceStorageError.invalidParameters }
        var rows: [[String]] = [], row: [String] = [], field = "", quoted = false
        let input = Array(text); var index = 0
        while index < input.count {
            let char = input[index]
            if char == "\"" {
                if quoted, index + 1 < input.count, input[index + 1] == "\"" { field.append("\""); index += 1 }
                else { quoted.toggle() }
            } else if char == ",", !quoted { row.append(field); field = "" }
            else if (char == "\n" || char == "\r\n" || char == "\r"), !quoted { row.append(field); rows.append(row); row = []; field = "" }
            else { field.append(char) }
            index += 1
        }
        guard !quoted else { throw WorkspaceStorageError.invalidParameters }
        if !field.isEmpty || !row.isEmpty { row.append(field); rows.append(row) }
        guard let headers = rows.first?.map({ $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased().replacingOccurrences(of: "\u{feff}", with: "") }) else { throw WorkspaceStorageError.invalidParameters }
        func column(_ names: [String]) -> Int? { headers.firstIndex { names.contains($0) } }
        guard let username = column(["username", "login_username", "login", "email"]), let password = column(["password", "login_password"]) else { throw WorkspaceStorageError.invalidParameters }
        let url = column(["url", "website", "login_uri"]), name = column(["name", "title"])
        let result = try rows.dropFirst().filter { !$0.allSatisfy(\.isEmpty) }.map { values -> WorkspaceVaultItem in
            guard values.count == headers.count else { throw WorkspaceStorageError.invalidParameters }
            let site = url.map { values[$0] } ?? ""
            let title = name.map { values[$0] }.flatMap { $0.isEmpty ? nil : $0 } ?? (URL(string: site)?.host ?? values[username])
            return .init(title: title, kind: .login, fields: ["url": site, "username": values[username], "password": values[password]])
        }
        guard !result.isEmpty, result.count <= 500 else { throw WorkspaceStorageError.invalidParameters }
        return result
    }
}
