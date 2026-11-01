import BlotDesign
import Foundation
import Observation
import BlotAPI

@MainActor
@Observable
final class BackendRuntime {
    static let shared = BackendRuntime()
    private(set) var client = BackendClient(baseURL: URL(string: "http://127.0.0.1:8080/")!)
    private(set) var startupError: String?
    private var process: Process?
    private var broker: MacPlatformBroker?
    private var discovery: NetService?
    private var bluetooth: MacBluetoothTunnel?
    private var blePort: UInt16?
    private(set) var fingerprint: String?
    private(set) var installationId: String?
    var bluetoothName: String { "Blot " + String(installationId?.prefix(8) ?? "Mac") }
    func enableBluetooth() {
        guard bluetooth == nil, let blePort else { return }
        bluetooth = MacBluetoothTunnel(port: blePort, name: bluetoothName)
    }
    private var stopping = false
    private var restarts: [Date] = []
    private var starting: _Concurrency.Task<Void, any Error>?
    private let operatorEnvironment = OperatorEnvironmentInput()

    func start() async throws {
        if let starting { return try await starting.value }
        let task = _Concurrency.Task { try await self.launch() }
        starting = task
        do { try await task.value } catch { startupError = error.localizedDescription; starting = nil; throw error }
    }

    private func launch() async throws {
        let configuration = try operatorEnvironment.configuration()
        let resumeBluetooth = bluetooth != nil
        bluetooth?.stop(); bluetooth = nil
        discovery?.stop(); discovery = nil
        broker?.stop(); broker = nil
        let resources = Bundle.main.resourceURL!.appendingPathComponent("Backend")
        let java = resources.appendingPathComponent("runtime/Contents/Home/bin/java")
        let jar = resources.appendingPathComponent("blot-backend.jar")
        guard FileManager.default.isExecutableFile(atPath: java.path), FileManager.default.fileExists(atPath: jar.path) else {
            throw NSError(domain: "BlotBackend", code: 1, userInfo: [NSLocalizedDescriptionKey: "This build is missing Java or blot-backend.jar. Rebuild the BlotMac scheme or run script/build_and_run.sh. App: \(Bundle.main.bundlePath)"])
        }
        let data = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                               appropriateFor: nil, create: true).appendingPathComponent("Blot/local")
        try FileManager.default.createDirectory(at: data, withIntermediateDirectories: true,
                                               attributes: [.posixPermissions: 0o700])
        let ready = data.appendingPathComponent("ready.json")
        try? FileManager.default.removeItem(at: ready)
        let server = Process()
        server.executableURL = java
        server.arguments = ["--enable-native-access=ALL-UNNAMED", "-Dorg.sqlite.lib.path=\(resources.appendingPathComponent("native").path)", "-jar", jar.path,
                            "--server.port=0", "--server.address=0.0.0.0", "--blot.tls.enabled=true", "--blot.data-directory=\(data.path)",
                            "--blot.platform-bridge=stdio", "--blot.project-access-library=\(resources.appendingPathComponent("native/libBlotProjectAccess.dylib").path)"]
        server.environment = ["HOME": NSHomeDirectory(), "PATH": "/usr/bin:/bin:/usr/sbin:/sbin",
                              "TMPDIR": FileManager.default.temporaryDirectory.path]
        if configuration != nil {
            server.environment?["BLOT_ENV_STDIN"] = "1"
        } else if let file = ProcessInfo.processInfo.environment["BLOT_ENV_FILE"], !file.isEmpty {
            server.environment?["BLOT_ENV_FILE"] = file
        }
        let ca = resources.appendingPathComponent("provider-ca.pem")
        if configuration != nil, FileManager.default.fileExists(atPath: ca.path) {
            server.environment?["BLOT_GIGACHAT_CA_FILE"] = ca.path
        }
        // Сокет нужен доверенному Git; программы агента получают отдельное окружение внутри VM.
        if let socket = ProcessInfo.processInfo.environment["SSH_AUTH_SOCK"] { server.environment?["SSH_AUTH_SOCK"] = socket }
        let log = data.appendingPathComponent("logs/backend.log")
        let requests = Pipe()
        let responses = Pipe()
        server.standardOutput = requests
        server.standardInput = responses
        server.standardError = FileHandle.nullDevice
        broker = MacPlatformBroker(input: responses.fileHandleForWriting, output: requests.fileHandleForReading)
        stopping = false
        server.terminationHandler = { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, !self.stopping else { return }
                self.starting = nil
                self.restarts.removeAll { Date().timeIntervalSince($0) > 60 }
                guard self.restarts.count < 3 else { self.startupError = "Backend repeatedly stopped. Open diagnostics before restarting."; return }
                self.restarts.append(Date())
                try? await Task.sleep(for: .seconds(2))
                try? await self.start()
            }
        }
        try server.run()
        process = server
        if let configuration { try responses.fileHandleForWriting.write(contentsOf: configuration) }
        for _ in 0..<600 {
            if !server.isRunning { throw NSError(domain: "BlotBackend", code: 2, userInfo: [NSLocalizedDescriptionKey: "The Blot server stopped while starting. Diagnostics: \(log.path)"]) }
            if let bytes = try? Data(contentsOf: ready), let state = try? JSONDecoder().decode(Ready.self, from: bytes), state.pid == Int(server.processIdentifier) {
                let endpoint = URL(string: "\(state.scheme ?? "http")://127.0.0.1:\(state.port)/")!
                let session = state.fingerprint.map { PinnedBackendSession(fingerprint: $0).makeSession() } ?? .shared
                let live = BackendClient(baseURL: endpoint, session: session)
                let compatibility: [String: BackendJSON] = try await live.get("v2/compatibility", as: [String: BackendJSON].self)
                guard case .array(let versions) = compatibility["schemaVersions"], versions.contains(.integer(2)) else { throw URLError(.cannotParseResponse) }
                if let token = try? BackendKeychain.read("session") { await live.useToken(token) }
                try await client.transferSession(to: live)
                client = live
                fingerprint = state.fingerprint
                installationId = state.installationId
                blePort = state.blePort.flatMap(UInt16.init(exactly:))
                let service = NetService(domain: "local.", type: "_blot._tcp.", name: "Blot \(state.installationId?.prefix(8) ?? "Mac")", port: Int32(state.port))
                if let id = state.installationId {
                    service.setTXTRecord(NetService.data(fromTXTRecord: ["installationId": Data(id.utf8)]))
                }
                service.publish()
                discovery = service
                if resumeBluetooth { enableBluetooth() }
                startupError = nil
                return
            }
            try await _Concurrency.Task.sleep(for: .milliseconds(100))
        }
        server.terminate()
        throw URLError(.timedOut)
    }

    func stop() { stopping = true; broker?.stop(); broker = nil; bluetooth?.stop(); bluetooth = nil; discovery?.stop(); discovery = nil; process?.terminate(); process = nil; starting = nil }
    private nonisolated struct Ready: Decodable { let port: Int; let pid: Int; let scheme: String?; let fingerprint: String?; let blePort: Int?; let installationId: String? }
}
