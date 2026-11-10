#if os(macOS)
import Foundation

/// Only this helper chooses the default location; a model cannot replace ~/Blot with an arbitrary path.
struct NativeWorkspaceStorage {
    let home: URL
    var root: URL { home.appendingPathComponent("Blot", isDirectory: true) }
    private func identifier(_ key: String, _ parameters: [String: String]) throws -> UUID {
        guard let text = parameters[key], let value = UUID(uuidString: text) else { throw NativeExecutionError.invalidRequest }
        return value
    }
    func prepare(_ parameters: [String: String]) throws -> ChatJSON {
        let files = try NativeScopedFiles(root: home); defer { files.closeRoot() }
        try files.mkdir("Blot")
        if parameters.isEmpty { return .object(["root": .string(root.path)]) }
        let owner = try identifier("owner_id", parameters), workspace = try identifier("workspace_id", parameters)
        let ownerPath = "Blot/Sessions/" + owner.uuidString
        try files.mkdir(ownerPath)
        let marker = ownerPath + "/.BlotOwner.json"
        let markerData = try JSONSerialization.data(withJSONObject: ["format": "1", "owner_id": owner.uuidString], options: [.sortedKeys])
        if let existing = try? files.read(marker, maximum: 1024) {
            guard existing == markerData else { throw NativeExecutionError.accessDenied }
        } else {
            let entries = try files.list(ownerPath).mcpFields["entries"]
            guard entries == .array([]) else { throw NativeExecutionError.accessDenied }
            _ = try files.write(marker, data: markerData, expected: "missing")
        }
        let scope = "Blot/Sessions/" + owner.uuidString + "/" + workspace.uuidString
        try files.mkdir(scope)
        var fields: [String: ChatJSON] = ["root": .string(root.path), "workspace_root": .string(home.appendingPathComponent(scope).path)]
        if parameters["conversation_id"] != nil {
            let conversation = try identifier("conversation_id", parameters)
            let session = scope + "/" + conversation.uuidString
            try files.mkdir(session + "/Files"); try files.mkdir(session + "/Messages")
            fields["session_root"] = .string(home.appendingPathComponent(session).path)
            fields["files_root"] = .string(home.appendingPathComponent(session + "/Files").path)
        }
        return .object(fields)
    }
    func erase(_ parameters: [String: String]) throws -> ChatJSON {
        let owner = try identifier("owner_id", parameters)
        let relative = "Blot/Sessions/" + owner.uuidString
        let files = try NativeScopedFiles(root: home); defer { files.closeRoot() }
        let target = home.appendingPathComponent(relative)
        guard FileManager.default.fileExists(atPath: target.path) else { return .object(["state": .string("absent")]) }
        let data = try files.read(relative + "/.BlotOwner.json", maximum: 1024)
        guard let fields = try JSONSerialization.jsonObject(with: data) as? [String: String], fields["format"] == "1", fields["owner_id"] == owner.uuidString,
              target.resolvingSymlinksInPath().path == target.path else { throw NativeExecutionError.accessDenied }
        try FileManager.default.removeItem(at: target)
        return .object(["state": .string("succeeded")])
    }
    func record(_ parameters: [String: String], removing: Bool) throws -> ChatJSON {
        let prepared = try prepare(parameters).mcpFields
        guard let path = prepared["session_root"]?.mcpString else { throw NativeExecutionError.invalidRequest }
        let files = try NativeScopedFiles(root: URL(fileURLWithPath: path)); defer { files.closeRoot() }
        let name: String
        switch parameters["record_type"] {
        case "conversation": name = "Session.json"
        case "message": name = "Messages/" + (try identifier("record_id", parameters)).uuidString + ".json"
        default: throw NativeExecutionError.invalidRequest
        }
        if removing { try files.remove(name) }
        else {
            guard let content = parameters["record"], let data = content.data(using: .utf8), data.count <= 1_048_576,
                  (try? JSONSerialization.jsonObject(with: data)) is [String: Any] else { throw NativeExecutionError.invalidRequest }
            _ = try files.write(name, data: data, expected: "managed", maximum: 1_048_576)
        }
        return .object(["state": .string("succeeded")])
    }
    func copyArtifact(_ parameters: [String: String]) throws -> ChatJSON {
        let prepared = try prepare(parameters).mcpFields
        let artifact = try identifier("record_id", parameters)
        guard let path = prepared["session_root"]?.mcpString, let source = parameters["source"], source.hasPrefix("/"), !source.contains("\0"),
              let name = parameters["name"], !name.isEmpty, name != ".", name != "..", !name.contains("/"), !name.contains("\\"), !name.contains("\0"), name.utf8.count <= 200,
              let expected = parameters["expected_hash"], let hash = parameters["hash"], hash.range(of: "^[a-f0-9]{64}$", options: .regularExpression) != nil else { throw NativeExecutionError.invalidRequest }
        let sourceURL = URL(fileURLWithPath: source).standardizedFileURL
        let input = try NativeScopedFiles(root: sourceURL.deletingLastPathComponent()); defer { input.closeRoot() }
        let data = try input.read(sourceURL.lastPathComponent, maximum: 32 * 1024 * 1024)
        guard NativeScopedFiles.hash(data) == hash else { throw NativeExecutionError.changed }
        let output = try NativeScopedFiles(root: URL(fileURLWithPath: path)); defer { output.closeRoot() }
        let folder = "Artifacts/" + artifact.uuidString
        try output.mkdir(folder)
        let destination = folder + "/" + name
        if let current = try? output.read(destination, maximum: 32 * 1024 * 1024), NativeScopedFiles.hash(current) == hash { return .object(["state": .string("succeeded")]) }
        guard expected == "missing" || expected.range(of: "^[a-f0-9]{64}$", options: .regularExpression) != nil else { throw NativeExecutionError.invalidRequest }
        _ = try output.write(destination, data: data, expected: expected, maximum: 32 * 1024 * 1024)
        return .object(["state": .string("succeeded")])
    }
}
#endif
