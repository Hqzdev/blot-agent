import BlotDesign
import Foundation

/// Launcher передаёт .env через приватный канал stdin до запуска Java.
@MainActor
final class OperatorEnvironmentInput {
    private var loaded = false
    private var encoded: Data?

    func configuration() throws -> Data? {
        if loaded { return encoded }
        guard ProcessInfo.processInfo.environment["BLOT_ENV_STDIN"] == "1" else { return nil }
        var data = Data()
        // Pipe может вернуть только часть файла за одно чтение. Дочитываем до EOF с лимитом.
        while let chunk = try FileHandle.standardInput.read(upToCount: min(16_384, 262_145 - data.count)), !chunk.isEmpty {
            data.append(chunk)
            guard data.count <= 262_144 else { throw invalidConfiguration() }
        }
        guard String(data: data, encoding: .utf8) != nil else {
            throw invalidConfiguration()
        }
        var result = data.base64EncodedData()
        result.append(10)
        encoded = result
        loaded = true
        return result
    }

    private func invalidConfiguration() -> NSError {
        NSError(domain: "BlotConfiguration", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "Нужен .env в UTF-8 размером до 256 KiB"])
    }
}
