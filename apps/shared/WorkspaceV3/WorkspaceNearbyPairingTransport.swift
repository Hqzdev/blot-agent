import Foundation
import OSLog
@preconcurrency import MultipeerConnectivity

@MainActor
protocol WorkspacePairingTransport: AnyObject {
    var onEvent: ((WorkspacePairingTransportEvent) -> Void)? { get set }
    func host(_ link: WorkspacePairingLink)
    func join(_ link: WorkspacePairingLink)
    func send(_ message: WorkspacePairingMessage) throws
    func stop()
}

nonisolated enum WorkspacePairingTransportEvent {
    case connected, message(WorkspacePairingMessage), failed
}

/// A single encrypted nearby connection, discovered using the identifier in the scanned QR.
@MainActor
final class WorkspaceNearbyPairingTransport: NSObject, WorkspacePairingTransport {
    var onEvent: ((WorkspacePairingTransportEvent) -> Void)?
    private static let service = "blot-pair"
    private static let logger = Logger(subsystem: "dev.blot.pairing", category: "Nearby")
    private let peer = MCPeerID(displayName: UUID().uuidString)
    private var session: MCSession?
    private var advertiser: MCNearbyServiceAdvertiser?
    private var browser: MCNearbyServiceBrowser?
    private var selectedPeer: MCPeerID?
    private var link: WorkspacePairingLink?

    func host(_ link: WorkspacePairingLink) {
        configure(link)
        let advertiser = MCNearbyServiceAdvertiser(peer: peer,
            discoveryInfo: ["pairing": link.id.uuidString], serviceType: Self.service)
        self.advertiser = advertiser
        advertiser.delegate = self
        advertiser.startAdvertisingPeer()
    }

    func join(_ link: WorkspacePairingLink) {
        configure(link)
        let browser = MCNearbyServiceBrowser(peer: peer, serviceType: Self.service)
        self.browser = browser
        browser.delegate = self
        browser.startBrowsingForPeers()
    }

    func send(_ message: WorkspacePairingMessage) throws {
        guard let session, let selectedPeer, session.connectedPeers.contains(selectedPeer) else {
            throw WorkspacePairingFailure.disconnected
        }
        let data = try JSONEncoder().encode(message)
        guard data.count <= 32_768 else { throw WorkspacePairingFailure.invalidMessage }
        try session.send(data, toPeers: [selectedPeer], with: .reliable)
    }

    func stop() {
        advertiser?.stopAdvertisingPeer(); advertiser?.delegate = nil; advertiser = nil
        browser?.stopBrowsingForPeers(); browser?.delegate = nil; browser = nil
        session?.delegate = nil; session?.disconnect(); session = nil
        selectedPeer = nil; link = nil
    }

    private func configure(_ link: WorkspacePairingLink) {
        stop()
        self.link = link
        let session = MCSession(peer: peer, securityIdentity: nil, encryptionPreference: .required)
        self.session = session
        session.delegate = self
    }

    private func fail() { stop(); onEvent?(.failed) }
}

extension WorkspaceNearbyPairingTransport: MCNearbyServiceAdvertiserDelegate {
    nonisolated func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didReceiveInvitationFromPeer peerID: MCPeerID,
        withContext context: Data?, invitationHandler: @escaping (Bool, MCSession?) -> Void) {
        _Concurrency.Task { @MainActor [weak self] in
            guard let self, self.advertiser === advertiser, let link = self.link,
                  self.selectedPeer == nil, context == Data(link.secret.utf8), link.expiresAt > Date() else {
                invitationHandler(false, nil); return
            }
            self.selectedPeer = peerID
            invitationHandler(true, self.session)
        }
    }

    nonisolated func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didNotStartAdvertisingPeer error: Error) {
        _Concurrency.Task { @MainActor [weak self] in
            guard let self, self.advertiser === advertiser else { return }
            let failure = error as NSError
            Self.logger.error("Advertisement failed: domain=\(failure.domain, privacy: .public) code=\(failure.code)")
            self.fail()
        }
    }
}

extension WorkspaceNearbyPairingTransport: MCNearbyServiceBrowserDelegate {
    nonisolated func browser(_ browser: MCNearbyServiceBrowser, foundPeer peerID: MCPeerID,
        withDiscoveryInfo info: [String: String]?) {
        _Concurrency.Task { @MainActor [weak self] in
            guard let self, self.browser === browser, self.selectedPeer == nil,
                  let link = self.link, link.expiresAt > Date(), info?["pairing"] == link.id.uuidString,
                  let session = self.session else { return }
            self.selectedPeer = peerID
            browser.invitePeer(peerID, to: session, withContext: Data(link.secret.utf8), timeout: 20)
            browser.stopBrowsingForPeers()
        }
    }

    nonisolated func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {
        // After an invitation, MCSession owns connection state independently of discovery.
    }

    nonisolated func browser(_ browser: MCNearbyServiceBrowser, didNotStartBrowsingForPeers error: Error) {
        _Concurrency.Task { @MainActor [weak self] in
            guard let self, self.browser === browser else { return }
            let failure = error as NSError
            Self.logger.error("Discovery failed: domain=\(failure.domain, privacy: .public) code=\(failure.code)")
            self.fail()
        }
    }
}

extension WorkspaceNearbyPairingTransport: MCSessionDelegate {
    nonisolated func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        _Concurrency.Task { @MainActor [weak self] in
            guard let self, self.session === session, self.selectedPeer == peerID else { return }
            if state == .connected {
                self.advertiser?.stopAdvertisingPeer()
                self.onEvent?(.connected)
            } else if state == .notConnected { self.fail() }
        }
    }

    nonisolated func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
        _Concurrency.Task { @MainActor [weak self] in
            guard let self, self.session === session, self.selectedPeer == peerID else { return }
            guard data.count <= 32_768, let message = try? JSONDecoder().decode(WorkspacePairingMessage.self, from: data) else {
                self.fail(); return
            }
            self.onEvent?(.message(message))
        }
    }

    nonisolated func session(_ session: MCSession, didReceive stream: InputStream, withName name: String, fromPeer peerID: MCPeerID) {
        stream.close()
    }
    nonisolated func session(_ session: MCSession, didStartReceivingResourceWithName name: String,
        fromPeer peerID: MCPeerID, with progress: Progress) {
        progress.cancel()
        rejectResource(session)
    }
    nonisolated func session(_ session: MCSession, didFinishReceivingResourceWithName name: String,
        fromPeer peerID: MCPeerID, at localURL: URL?, withError error: Error?) { rejectResource(session) }

    private nonisolated func rejectResource(_ session: MCSession) {
        _Concurrency.Task { @MainActor [weak self] in
            guard let self, self.session === session else { return }
            self.fail()
        }
    }
}
