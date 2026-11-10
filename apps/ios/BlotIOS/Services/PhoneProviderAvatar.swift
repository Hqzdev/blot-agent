import Foundation

nonisolated struct PhoneProviderAvatarRequest: Equatable {
    let ownerID: UUID
    let url: URL
}

nonisolated final class PhoneProviderAvatar: NSObject, URLSessionTaskDelegate, Sendable {
    static func allows(_ url: URL) -> Bool {
        guard url.scheme == "https", url.user == nil, url.password == nil, url.fragment == nil,
              url.port == nil || url.port == 443, let host = url.host?.lowercased() else { return false }
        return host == "googleusercontent.com" || host.hasSuffix(".googleusercontent.com")
            || host == "ggpht.com" || host.hasSuffix(".ggpht.com") || host == "avatars.yandex.net"
    }
    func load(_ url: URL) async throws -> Data {
        guard Self.allows(url) else { throw URLError(.badURL) }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 15)
        request.setValue("image/*", forHTTPHeaderField: "Accept")
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpShouldSetCookies = false
        configuration.urlCredentialStorage = nil
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let (bytes, response) = try await session.bytes(for: request, delegate: self)
        let limit = 2 * 1024 * 1024
        guard let http = response as? HTTPURLResponse, http.statusCode == 200,
              response.expectedContentLength <= limit, response.mimeType?.hasPrefix("image/") == true else { throw URLError(.badServerResponse) }
        var data = Data()
        for try await byte in bytes {
            guard data.count < limit else { throw URLError(.dataLengthExceedsMaximum) }
            data.append(byte)
        }
        try Task.checkCancellation()
        let imageData = data
        return try await Task.detached(priority: .utility) { try PhoneAvatarImage.prepare(imageData) }.value
    }
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
        completionHandler(request.url.map(Self.allows) == true ? request : nil)
    }
}
