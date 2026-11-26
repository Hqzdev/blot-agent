import Foundation

public struct WorkspaceRelease: Codable, Sendable {
    public let version: String; public let build: Int; public let minimumOS: String; public let downloadURL: URL; public let notes: String; public let publishedAt: String
    public func isNewer(version installed: String, build installedBuild: Int) -> Bool {
        let order = version.compare(installed, options: .numeric)
        return order == .orderedDescending || order == .orderedSame && build > installedBuild
    }
}
public struct WorkspaceReleaseService: Sendable {
    private let http: WorkspaceCloudHTTP
    public init(http: WorkspaceCloudHTTP) { self.http = http }
    public func latest(platform: String, channel: String) async throws -> WorkspaceRelease? {
        let data = try await http.releaseMetadata(platform: platform, channel: channel)
        guard let data else { return nil }
        let release = try JSONDecoder().decode(WorkspaceRelease.self, from: data)
        guard release.downloadURL.scheme == "https", release.downloadURL.host != nil, release.downloadURL.user == nil,
              release.downloadURL.password == nil, release.build > 0, release.notes.utf8.count <= 128_000,
              release.version.range(of: #"^[0-9]+(\.[0-9]+){1,3}$"#, options: .regularExpression) != nil else { throw WorkspaceCloudError.invalidResponse }
        return release
    }
}
