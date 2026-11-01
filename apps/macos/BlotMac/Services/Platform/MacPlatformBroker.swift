import BlotDesign
import Foundation
import BlotAPI

/// Канал создаётся родительским приложением до запуска Java и не публикуется в сети.
@MainActor
final class MacPlatformBroker {
    private let input: FileHandle
    private let output: FileHandle
    private var buffer = Data()
    init(input: FileHandle, output: FileHandle) {
        self.input = input; self.output = output
        output.readabilityHandler = { [weak self] handle in
            let bytes = handle.availableData
            Task { @MainActor [weak self] in self?.receive(bytes) }
        }
    }
    func stop() { ProjectBookmarks.shared.close(); _Concurrency.Task { await VirtualMachineExecution.shared.shutdown() }; output.readabilityHandler = nil; try? input.close(); try? output.close() }
    private func receive(_ bytes: Data) {
        guard !bytes.isEmpty else { stop(); return }
        buffer.append(bytes)
        guard buffer.count <= 1_048_576 else { stop(); return }
        while let end = buffer.firstIndex(of: 10) {
            let line = Data(buffer[..<end]); buffer.removeSubrange(...end)
            _Concurrency.Task { await respond(line) }
        }
    }
    private func respond(_ line: Data) async {
        guard let request = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
              let id = request["id"] as? String, let method = request["method"] as? String,
              let arguments = request["arguments"] as? [String: Any] else { return }
        var response: [String: Any] = ["id": id, "ok": true]
        do {
            let key = arguments["key"] as? String ?? ""
            guard key.count <= 8192 else { throw URLError(.cannotParseResponse) }
            let name = "backendSecret." + key
            switch method {
            case "project.bookmark":
                response["value"] = try ProjectBookmarks.shared.transfer(arguments["path"] as? String ?? "")
            case "vm.start": response["value"] = try VirtualMachineExecution.shared.start(arguments)
            case "vm.status": response["value"] = try VirtualMachineExecution.shared.status(arguments["id"] as? String ?? "")
            case "vm.release": try await VirtualMachineExecution.shared.release(arguments["id"] as? String ?? "")
            case "secret.get":
                if let value = try BackendKeychain.read(name) { response["value"] = value } else { response["value"] = NSNull() }
            case "secret.put":
                guard let value = arguments["value"] as? String, value.utf8.count <= 65_536 else { throw URLError(.cannotParseResponse) }
                try BackendKeychain.write(value, key: name)
            case "secret.remove": try BackendKeychain.remove(name)
            default: throw URLError(.unsupportedURL)
            }
        } catch { response = ["id": id, "ok": false, "error": error.localizedDescription] }
        guard var data = try? JSONSerialization.data(withJSONObject: response) else { return }
        data.append(10)
        try? input.write(contentsOf: data)
    }
}
