import BlotDomain
import CryptoKit
import Foundation

@MainActor
enum PhoneWorkspaceFiles {
    private static var root: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Blot/Files", isDirectory: true)
    }

    static func url(for artifact: BlotV3.Artifact) -> URL? {
        let url = root.appendingPathComponent(artifact.relativePath).standardizedFileURL
        guard url.path.hasPrefix(root.path + "/"), FileManager.default.fileExists(atPath: url.path) else { return nil }
        return url
    }

    static func prepare(_ artifacts: [BlotV3.Artifact]) throws -> [BlotV3.Artifact] {
        try artifacts.map { artifact in
            if url(for: artifact) != nil { return artifact }
            let name = artifact.name == "landing-variants.png" ? "landing-variants.svg" : artifact.name
            let file = name as NSString
            guard let source = Bundle.main.url(forResource: file.deletingPathExtension, withExtension: file.pathExtension, subdirectory: "WorkspaceFiles")
                ?? Bundle.main.url(forResource: file.deletingPathExtension, withExtension: file.pathExtension) else { return artifact }
            let data = try Data(contentsOf: source)
            let relativePath = artifact.metadata.id.uuidString + "/" + name
            let destination = root.appendingPathComponent(relativePath)
            try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: destination, options: .atomic)
            let mediaType = file.pathExtension == "svg" ? "image/svg+xml" : file.pathExtension == "csv" ? "text/csv" : "text/markdown"
            return try .init(metadata: artifact.metadata, execution: artifact.execution, name: name, mediaType: mediaType,
                byteCount: data.count, hash: SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined(), relativePath: relativePath)
        }
    }
}
