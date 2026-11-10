import BlotWorkspace
import Foundation

@main struct VerifyNativeXPC {
    static func main() async throws {
        let executor = NativeXPCClient()
        let command = NativeCommand(projectID: UUID(), root: "/private/tmp", executable: "/bin/sh", arguments: ["-c", "printf 'native xpc'; printf 'error channel' >&2"])
        _ = try await executor.request(.init(.start, command: command))
        let deadline = ContinuousClock.now.advanced(by: .seconds(5))
        while ContinuousClock.now < deadline {
            let result = try await executor.request(.init(.status, command: command))
            let data = try JSONEncoder().encode(result)
            let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
            let state = try decoder.decode(NativeProcessSnapshot.self, from: data)
            if state.finishedAt != nil {
                precondition(state.stdout == "native xpc" && state.stderr == "error channel" && state.exitCode == 0)
                await executor.stopAll(); print("PASS: sandboxed signed host → private authenticated XPC → native command → stdout/stderr")
                return
            }
            try await _Concurrency.Task.sleep(for: .milliseconds(20))
        }
        await executor.stopAll(); throw NativeExecutionError.unavailable
    }
}
