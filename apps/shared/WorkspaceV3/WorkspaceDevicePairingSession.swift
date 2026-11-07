import BlotWorkspace
import Foundation
import Observation

/// Coordinates the signed trust exchange; views expose only QR scanning and the six-digit code.
@MainActor @Observable
final class WorkspaceDevicePairingSession {
    enum Phase: Equatable { case idle, preparing, waitingForPhone, connecting, inspecting, enteringCode, approving, confirming, finishing, waitingForReceipt, complete, failed }
    private(set) var phase = Phase.idle
    private(set) var qrCode = ""
    private(set) var displayCode = ""
    private(set) var peerName = ""
    private(set) var failure: WorkspacePairingFailure?
    var code = ""
    private let transport: any WorkspacePairingTransport
    private var commands: (any WorkspaceDevicePairingCommands)?
    private var claim: WorkspacePairingClaim?
    private var hosting = false
    private var incorrectAttempts = 0
    private var generation = UUID()
    private var expiry: _Concurrency.Task<Void, Never>?
    private var connectionTimeout: _Concurrency.Task<Void, Never>?

    init(transport: (any WorkspacePairingTransport)? = nil) {
        self.transport = transport ?? WorkspaceNearbyPairingTransport()
    }

    func host(using commands: any WorkspaceDevicePairingCommands) async {
        reset(using: commands, hosting: true)
        phase = .preparing
        let generation = generation
        do {
            let invitation = try await commands.createDeviceInvite()
            guard self.generation == generation else { return }
            let link = WorkspacePairingLink(invitation: invitation)
            qrCode = try link.encoded
            phase = .waitingForPhone
            transport.host(link)
            scheduleExpiry(link, generation: generation)
        } catch { fail(.unavailable, generation: generation) }
    }

    func join(_ qrCode: String, using commands: any WorkspaceDevicePairingCommands) async {
        reset(using: commands, hosting: false)
        phase = .connecting
        let generation = generation
        do {
            let link = try WorkspacePairingLink.decode(qrCode)
            let claim = try await commands.claimDevice(link.invitation)
            guard self.generation == generation else { return }
            self.claim = claim; peerName = claim.name
            transport.join(link)
            scheduleExpiry(link, generation: generation)
            connectionTimeout = _Concurrency.Task { [weak self] in
                do { try await _Concurrency.Task.sleep(for: .seconds(25)) }
                catch { return }
                self?.fail(.disconnected, generation: generation)
            }
        } catch { fail(error as? WorkspacePairingFailure ?? .invalidQR, generation: generation) }
    }

    func confirm() {
        guard !hosting, phase == .enteringCode, let claim else { return }
        guard code.utf8.count == 6, code.allSatisfy({ $0.isASCII && $0.isNumber }), code == claim.code else {
            failure = .wrongCode
            code = ""
            return
        }
        failure = nil
        do { try transport.send(.confirm(code)); phase = .confirming }
        catch { fail(.disconnected, generation: generation) }
    }

    func stop() {
        generation = UUID()
        expiry?.cancel(); expiry = nil
        connectionTimeout?.cancel(); connectionTimeout = nil
        transport.onEvent = nil; transport.stop()
        commands = nil; claim = nil
    }

    private func reset(using commands: any WorkspaceDevicePairingCommands, hosting: Bool) {
        stop()
        self.commands = commands; self.hosting = hosting
        phase = .idle; failure = nil; code = ""; displayCode = ""; qrCode = ""; peerName = ""; incorrectAttempts = 0
        let generation = generation
        transport.onEvent = { [weak self] event in
            _Concurrency.Task { @MainActor [weak self] in await self?.handle(event, generation: generation) }
        }
    }

    private func handle(_ event: WorkspacePairingTransportEvent, generation: UUID) async {
        guard self.generation == generation, phase != .complete, phase != .failed, let commands else { return }
        do {
            switch event {
            case .failed: fail(.disconnected, generation: generation)
            case .connected:
                if !hosting, phase == .connecting, let claim { try transport.send(.claim(claim.token)) }
            case .message(let message):
                switch message {
                case .claim(let token):
                    guard hosting, phase == .waitingForPhone, token.utf8.count <= 16_384 else { return }
                    phase = .inspecting
                    let candidate = try await commands.inspectDeviceClaim(token)
                    guard self.generation == generation else { return }
                    claim = candidate; displayCode = candidate.code; peerName = candidate.name
                    phase = .enteringCode
                    try transport.send(.ready)
                case .ready:
                    guard !hosting, phase == .connecting else { return }
                    phase = .enteringCode
                    connectionTimeout?.cancel(); connectionTimeout = nil
                case .confirm(let code):
                    guard hosting, phase == .enteringCode, let claim else { return }
                    guard code == claim.code else {
                        incorrectAttempts += 1
                        if incorrectAttempts >= 5 { fail(.tooManyAttempts, generation: generation) }
                        return
                    }
                    phase = .approving
                    let approval = try await commands.approveDevice(claim.token, code: code)
                    guard self.generation == generation else { return }
                    phase = .waitingForReceipt
                    try transport.send(.approval(approval))
                case .approval(let token):
                    guard !hosting, phase == .confirming else { return }
                    phase = .finishing
                    try await commands.finishDevicePairing(token)
                    guard self.generation == generation else { return }
                    try transport.send(.received)
                    finish()
                case .received:
                    guard hosting, phase == .waitingForReceipt else { return }
                    finish()
                }
            }
        } catch { fail(.unavailable, generation: generation) }
    }

    private func finish() {
        phase = .complete; failure = nil
        expiry?.cancel(); expiry = nil
        connectionTimeout?.cancel(); connectionTimeout = nil
    }

    private func fail(_ failure: WorkspacePairingFailure, generation: UUID) {
        guard self.generation == generation else { return }
        self.failure = failure; phase = .failed
        self.generation = UUID()
        expiry?.cancel(); expiry = nil
        connectionTimeout?.cancel(); connectionTimeout = nil
        transport.onEvent = nil; transport.stop()
    }

    private func scheduleExpiry(_ link: WorkspacePairingLink, generation: UUID) {
        expiry = _Concurrency.Task { [weak self] in
            do { try await _Concurrency.Task.sleep(for: .seconds(max(0, link.expiresAt.timeIntervalSinceNow))) }
            catch { return }
            self?.fail(.expired, generation: generation)
        }
    }
}
