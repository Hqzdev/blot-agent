import BlotWorkspace
import CoreImage
import XCTest

@MainActor
final class WorkspaceDevicePairingTests: XCTestCase {
    func testQRThenComputerCodePairsBothAuthoritiesWithoutManualPackets() async throws {
        let fixture = try await NearbyPairingFixture()
        try await fixture.connect()
        XCTAssertEqual(fixture.mac.displayCode.count, 6)
        XCTAssertTrue(fixture.phone.displayCode.isEmpty, "The phone asks for the computer's code")
        fixture.phone.code = fixture.mac.displayCode
        fixture.phone.confirm()
        try await wait { fixture.mac.phase == .complete && fixture.phone.phase == .complete }
        let macPeers = try await fixture.macAuthority.devices()
        let phonePeers = try await fixture.phoneAuthority.devices()
        XCTAssertEqual(macPeers.map(\.id), [fixture.phoneID.deviceID])
        XCTAssertEqual(phonePeers.map(\.id), [fixture.macID.deviceID])
        try await fixture.close()
    }

    func testWrongCodeDoesNotSendConfirmationOrTrustEitherDevice() async throws {
        let fixture = try await NearbyPairingFixture()
        try await fixture.connect()
        let count = fixture.phoneWire.sent.count
        fixture.phone.code = fixture.mac.displayCode == "000000" ? "111111" : "000000"
        fixture.phone.confirm()
        XCTAssertEqual(fixture.phone.failure, .wrongCode)
        XCTAssertEqual(fixture.phone.phase, .enteringCode)
        XCTAssertEqual(fixture.phoneWire.sent.count, count)
        let macPeers = try await fixture.macAuthority.devices()
        let phonePeers = try await fixture.phoneAuthority.devices()
        XCTAssertTrue(macPeers.isEmpty && phonePeers.isEmpty)
        fixture.phone.code = fixture.mac.displayCode
        fixture.phone.confirm()
        try await wait { fixture.mac.phase == .complete && fixture.phone.phase == .complete }
        try await fixture.close()
    }

    func testActualQRCodeCanBeDecodedAndExpiredOrForeignCodesAreRejected() async throws {
        let fixture = try await NearbyPairingFixture()
        await fixture.mac.host(using: fixture.macCommands)
        let image = try XCTUnwrap(WorkspacePairingQRCode.image(for: fixture.mac.qrCode))
        let detector = try XCTUnwrap(CIDetector(ofType: CIDetectorTypeQRCode, context: CIContext(),
            options: [CIDetectorAccuracy: CIDetectorAccuracyHigh]))
        let features = detector.features(in: CIImage(cgImage: image))
        let decoded = try XCTUnwrap((features.first as? CIQRCodeFeature)?.messageString)
        XCTAssertEqual(decoded, fixture.mac.qrCode)
        let link = try WorkspacePairingLink.decode(decoded)
        XCTAssertThrowsError(try WorkspacePairingLink.decode(decoded, now: link.expiresAt.addingTimeInterval(1)))
        XCTAssertThrowsError(try WorkspacePairingLink.decode("https://example.com"))
        await fixture.phone.join("not-a-blot-code", using: fixture.phoneCommands)
        XCTAssertEqual(fixture.phone.phase, .failed)
        XCTAssertEqual(fixture.phone.failure, .invalidQR)
        try await fixture.close()
    }

    func testFiveWrongRemoteCodesStopAttemptWithoutGrantingTrust() async throws {
        let fixture = try await NearbyPairingFixture()
        try await fixture.connect()
        let wrong = fixture.mac.displayCode == "000000" ? "111111" : "000000"
        for _ in 0..<5 { fixture.macWire.onEvent?(.message(.confirm(wrong))) }
        try await wait { fixture.mac.phase == .failed }
        XCTAssertEqual(fixture.mac.failure, .tooManyAttempts)
        let peers = try await fixture.macAuthority.devices()
        XCTAssertTrue(peers.isEmpty)
        try await fixture.close()
    }

    func testPrematureReceiptAndCallbacksFromOldAttemptCannotCompletePairing() async throws {
        let fixture = try await NearbyPairingFixture()
        await fixture.mac.host(using: fixture.macCommands)
        let oldEvent = fixture.macWire.onEvent
        fixture.macWire.onEvent?(.message(.received))
        await _Concurrency.Task.yield()
        XCTAssertEqual(fixture.mac.phase, .waitingForPhone)
        let oldQR = fixture.mac.qrCode
        await fixture.mac.host(using: fixture.macCommands)
        XCTAssertNotEqual(fixture.mac.qrCode, oldQR)
        oldEvent?(.failed)
        oldEvent?(.message(.received))
        for _ in 0..<10 { await _Concurrency.Task.yield() }
        XCTAssertEqual(fixture.mac.phase, .waitingForPhone)
        XCTAssertNil(fixture.mac.failure)
        try await fixture.close()
    }

    func testConnectionFailureCanRestartWithNewQR() async throws {
        let fixture = try await NearbyPairingFixture()
        try await fixture.connect()
        fixture.macWire.onEvent?(.failed)
        try await wait { fixture.mac.phase == .failed }
        XCTAssertEqual(fixture.mac.failure, .disconnected)
        await fixture.mac.host(using: fixture.macCommands)
        XCTAssertEqual(fixture.mac.phase, .waitingForPhone)
        XCTAssertTrue(fixture.mac.displayCode.isEmpty)
        XCTAssertNil(fixture.mac.failure)
        try await fixture.close()
    }

    private func wait(_ condition: () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(3)
        while !condition() && Date() < deadline { await _Concurrency.Task.yield() }
        XCTAssertTrue(condition())
        if !condition() { throw WorkspacePairingFailure.unavailable }
    }
}

private actor NearbyPairingCredentials: WorkspaceCredentialStore {
    private var values: [String: Data] = [:]
    func read(_ name: String) -> Data? { values[name] }
    func write(_ value: Data, name: String) { values[name] = value }
    func remove(_ name: String) { values[name] = nil }
}

@MainActor
private final class NearbyPairingFixture {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let macID: WorkspaceIdentity
    let phoneID: WorkspaceIdentity
    let macAuthority: WorkspaceDeviceAuthority
    let phoneAuthority: WorkspaceDeviceAuthority
    let macCommands: LocalWorkspaceService
    let phoneCommands: LocalWorkspaceService
    let macWire = InMemoryPairingTransport(), phoneWire = InMemoryPairingTransport()
    let mac: WorkspaceDevicePairingSession
    let phone: WorkspaceDevicePairingSession

    init() async throws {
        let owner = UUID(), workspace = UUID()
        macID = .init(ownerID: owner, workspaceID: workspace, deviceID: UUID())
        phoneID = .init(ownerID: owner, workspaceID: workspace, deviceID: UUID())
        macAuthority = try await .open(identity: macID, credentials: NearbyPairingCredentials())
        phoneAuthority = try await .open(identity: phoneID, credentials: NearbyPairingCredentials())
        macCommands = try LocalWorkspaceService(databaseURL: directory.appendingPathComponent("mac/workspace.sqlite"),
            identity: macID, deviceAuthority: macAuthority)
        phoneCommands = try LocalWorkspaceService(databaseURL: directory.appendingPathComponent("phone/workspace.sqlite"),
            identity: phoneID, deviceAuthority: phoneAuthority)
        macWire.counterpart = phoneWire; phoneWire.counterpart = macWire
        mac = WorkspaceDevicePairingSession(transport: macWire)
        phone = WorkspaceDevicePairingSession(transport: phoneWire)
    }

    func connect() async throws {
        await mac.host(using: macCommands)
        await phone.join(mac.qrCode, using: phoneCommands)
        let deadline = Date().addingTimeInterval(3)
        while (mac.phase != .enteringCode || phone.phase != .enteringCode) && Date() < deadline {
            await _Concurrency.Task.yield()
        }
        XCTAssertEqual(mac.phase, .enteringCode)
        XCTAssertEqual(phone.phase, .enteringCode)
        if mac.phase != .enteringCode || phone.phase != .enteringCode { throw WorkspacePairingFailure.unavailable }
    }

    func close() async throws {
        mac.stop(); phone.stop()
        try await macCommands.close(); try await phoneCommands.close()
        try FileManager.default.removeItem(at: directory)
    }
}

@MainActor
private final class InMemoryPairingTransport: WorkspacePairingTransport {
    var onEvent: ((WorkspacePairingTransportEvent) -> Void)?
    weak var counterpart: InMemoryPairingTransport?
    private var link: WorkspacePairingLink?
    private var connected = false
    private(set) var sent: [WorkspacePairingMessage] = []
    func host(_ link: WorkspacePairingLink) { self.link = link }
    func join(_ link: WorkspacePairingLink) {
        guard counterpart?.link == link else { onEvent?(.failed); return }
        connected = true; counterpart?.connected = true
        counterpart?.onEvent?(.connected); onEvent?(.connected)
    }
    func send(_ message: WorkspacePairingMessage) throws {
        guard connected else { throw WorkspacePairingFailure.disconnected }
        sent.append(message); counterpart?.onEvent?(.message(message))
    }
    func stop() { connected = false; link = nil }
}
