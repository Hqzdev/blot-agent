import Foundation

/// Metadata and bytes are encoded together; no model-supplied header or URL is used.
struct GoogleDriveUpload: Sendable {
    static let maximumBytes = 5 * 1024 * 1024
    let name: String
    let mimeType: String
    let parentID: String?
    let data: Data

    init(name: String, mimeType: String, parentID: String?, data: Data) throws {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, name.utf8.count <= 1024,
              !name.contains(where: { $0.isNewline || $0.isASCII && $0.asciiValue! < 32 }),
              mimeType.range(of: #"^[a-zA-Z0-9.+-]+/[a-zA-Z0-9.+-]+$"#, options: .regularExpression) != nil,
              data.count <= Self.maximumBytes,
              parentID.map({ $0.range(of: #"^[A-Za-z0-9_-]{1,200}$"#, options: .regularExpression) != nil }) ?? true else {
            throw WorkspaceStorageError.invalidParameters
        }
        self.name = name; self.mimeType = mimeType; self.parentID = parentID; self.data = data
    }

    func multipart() throws -> (contentType: String, body: Data) {
        var boundary = "blot-" + UUID().uuidString
        while data.range(of: Data(boundary.utf8)) != nil { boundary = "blot-" + UUID().uuidString }
        var metadata: [String: Any] = ["name": name, "mimeType": mimeType]
        if let parentID { metadata["parents"] = [parentID] }
        var body = Data("--\(boundary)\r\nContent-Type: application/json; charset=UTF-8\r\n\r\n".utf8)
        body.append(try JSONSerialization.data(withJSONObject: metadata, options: [.sortedKeys]))
        body.append(Data("\r\n--\(boundary)\r\nContent-Type: \(mimeType)\r\n\r\n".utf8))
        body.append(data)
        body.append(Data("\r\n--\(boundary)--\r\n".utf8))
        return ("multipart/related; boundary=\(boundary)", body)
    }
}
