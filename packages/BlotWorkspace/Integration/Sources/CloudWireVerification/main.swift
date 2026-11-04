import BlotDomain
import BlotWorkspace
import Foundation

struct DeviceSeed: Codable {
    let identity: WorkspaceIdentity
    let accessToken: String
    let refreshToken: String
}
struct Seed: Codable {
    let devices: [DeviceSeed]
}
@main struct Verification {
    static func main() async throws {
        let arguments = CommandLine.arguments
        guard arguments.count == 4, let origin = URL(string: arguments[3]) else {
            throw NSError(domain: "Usage: CloudWireVerification prepare|verify directory origin", code: 1)
        }
        let directory = URL(filePath: arguments[2], directoryHint: .isDirectory)
        let seedURL = directory.appendingPathComponent("wire-seed.json")
        switch arguments[1] {
        case "prepare":
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let ownerID = UUID(), workspaceID = UUID()
            var devices: [DeviceSeed] = []
            for index in 0..<3 {
                let repository = try WorkspaceRepository(url: directory.appendingPathComponent("device-\(index).sqlite"))
                let identity = try await repository.joinWorkspace(ownerID: ownerID, workspaceID: workspaceID)
                let access = UUID().uuidString.replacingOccurrences(of: "-", with: "") + "wiretestkey"
                let refresh = UUID().uuidString.replacingOccurrences(of: "-", with: "") + "refreshtest"
                devices.append(DeviceSeed(identity: identity, accessToken: access, refreshToken: refresh))
            }
            try JSONEncoder().encode(Seed(devices: devices)).write(to: seedURL, options: .atomic)
            print("Prepared three isolated device databases and ephemeral test credentials.")
        case "verify":
            let seed = try JSONDecoder().decode(Seed.self, from: Data(contentsOf: seedURL))
            guard seed.devices.count == 3 else { throw WorkspaceSyncError.invalidChange }
            let http = try WorkspaceCloudHTTP(origin: origin, allowLoopbackHTTP: true)
            let sessionIDs = try JSONDecoder().decode([UUID].self, from: Data(contentsOf: directory.appendingPathComponent("session-ids.json")))
            var repositories: [WorkspaceRepository] = []
            var engines: [WorkspaceSyncEngine] = []
            var managers: [WorkspaceCloudDevices] = []
            var deviceKeys: [WorkspaceDeviceKeys] = []
            var sessions: [WorkspaceCloudSession] = []
            var stores: [EphemeralCredentials] = []
            for (index, device) in seed.devices.enumerated() {
                let repository = try WorkspaceRepository(url: directory.appendingPathComponent("device-\(index).sqlite"))
                repositories.append(repository)
                let store = EphemeralCredentials()
                let saved = WorkspaceCloudTokensForSeed(sessionID: sessionIDs[index], accessToken: device.accessToken, refreshToken: device.refreshToken,
                    expiresAt: ISO8601DateFormatter().string(from: Date().addingTimeInterval(900)), ownerID: device.identity.ownerID, workspaceID: device.identity.workspaceID, bootstrapAllowed: index == 0)
                try await store.write(JSONEncoder().encode(saved), name: "session")
                let session = WorkspaceCloudSession(http: http, credentials: store, credentialName: "session")
                _ = try await session.restore()
                let keys = try await WorkspaceDeviceKeys.open(identity: device.identity, credentials: store)
                let manager = WorkspaceCloudDevices(http: http, session: session, keys: keys, credentials: store, identity: device.identity)
                stores.append(store); sessions.append(session); managers.append(manager); deviceKeys.append(keys)
            }
            try await managers[0].bootstrap(name: "Wire Mac", kind: "DESKTOP")
            try await managers[0].bootstrap(name: "Wire Mac", kind: "DESKTOP") // Recover an already committed bootstrap.
            do {
                try await managers[1].bootstrap(name: "Unpaired Phone", kind: "PHONE")
                throw WorkspaceCloudError.invalidResponse
            } catch WorkspaceStorageError.permissionDenied {}
            try await pair(issuer: managers[0], receiver: managers[1], name: "Wire Phone", kind: "PHONE")
            try await pair(issuer: managers[1], receiver: managers[2], name: "Wire Extra Mac", kind: "DESKTOP")
            for (index, device) in seed.devices.enumerated() {
                let reopenedKeys = try await WorkspaceDeviceKeys.open(identity: device.identity, credentials: stores[index])
                let restoredTrust = WorkspaceCloudDevices(http: http, session: sessions[index], keys: reopenedKeys, credentials: stores[index], identity: device.identity)
                try await restoredTrust.restoreTrust()
                _ = try await restoredTrust.refreshDeviceTrust()
                let crypto = try await reopenedKeys.cryptography()
                let transport = WorkspaceCloudSyncTransport(http: http, authorization: sessions[index])
                engines.append(WorkspaceSyncEngine(repository: repositories[index], identity: device.identity, cryptography: crypto,
                    transport: transport, trust: restoredTrust))
            }
            let first = seed.devices[0], second = seed.devices[1]
            let chatA = WorkspaceChatService(repository: repositories[0], identity: first.identity)
            let chatB = WorkspaceChatService(repository: repositories[1], identity: second.identity)
            let conversationID = try await chatA.createConversation(commandID: UUID(), title: "Wire test")
            _ = try await chatA.sendMessage(commandID: UUID(), conversationID: conversationID, content: "Изолированное сообщение A")
            try await engines[0].synchronize()
            try await engines[1].synchronize()
            _ = try await chatA.sendMessage(commandID: UUID(), conversationID: conversationID, content: "Офлайн A")
            _ = try await chatB.sendMessage(commandID: UUID(), conversationID: conversationID, content: "Офлайн B")
            try await engines[1].synchronize()
            try await engines[0].synchronize()
            try await engines[1].synchronize()
            try await engines[0].synchronize()
            let a = try await repositories[0].projection(identity: first.identity)
            let b = try await repositories[1].projection(identity: second.identity)
            guard Set(a.messages.map(\.metadata.id)) == Set(b.messages.map(\.metadata.id)), a.messages.count == 3,
                  Set(a.messages.map(\.content)) == Set(b.messages.map(\.content)),
                  try await repositories[0].pendingSyncChanges(limit: 100).isEmpty,
                  try await repositories[1].pendingSyncChanges(limit: 100).isEmpty else { throw WorkspaceSyncError.replayConflict }
            let snapshotChat = try await chatA.createConversation(commandID: UUID(), title: "Snapshot chunks")
            for index in 0..<3 {
                _ = try await chatA.sendMessage(commandID: UUID(), conversationID: snapshotChat,
                    content: "SECRET-WIRE-SNAPSHOT-DO-NOT-LOG-\(index)" + String(repeating: "s", count: 100_000))
            }
            let thirdChat = WorkspaceChatService(repository: repositories[2], identity: seed.devices[2].identity)
            let pendingChat = try await thirdChat.createConversation(commandID: UUID(), title: "Local pending before bootstrap")
            let pendingMessage = try await thirdChat.sendMessage(commandID: UUID(), conversationID: pendingChat, content: "Pending local snapshot edit")
            let snapshotTransportA = WorkspaceCloudSnapshotTransport(http: http, authorization: sessions[0])
            let snapshotTransportC = WorkspaceCloudSnapshotTransport(http: http, authorization: sessions[2])
            let snapshotBlobsA = WorkspaceCloudAttachmentTransport(http: http, authorization: sessions[0])
            let interruptedBlobs = InterruptedSnapshotBlobs(underlying: WorkspaceCloudAttachmentTransport(http: http, authorization: sessions[2]))
            let snapshotsA = WorkspaceSnapshotSync(repository: repositories[0], identity: first.identity, keys: deviceKeys[0],
                cryptography: try await deviceKeys[0].cryptography(), engine: engines[0], transport: snapshotTransportA,
                blobs: snapshotBlobsA, trust: managers[0], cacheDirectory: directory.appendingPathComponent("snapshots-a"))
            let snapshotsC = WorkspaceSnapshotSync(repository: repositories[2], identity: seed.devices[2].identity, keys: deviceKeys[2],
                cryptography: try await deviceKeys[2].cryptography(), engine: engines[2], transport: snapshotTransportC,
                blobs: interruptedBlobs, trust: managers[2], cacheDirectory: directory.appendingPathComponent("snapshots-c"))
            let snapshotRequestID = UUID()
            _ = try await snapshotsC.request(commandID: snapshotRequestID)
            _ = try await snapshotsC.request(commandID: snapshotRequestID)
            guard try await snapshotsC.pendingRequests() == [snapshotRequestID] else { throw WorkspaceSyncError.invalidSnapshot }
            guard try await !snapshotsC.receive(requestID: snapshotRequestID) else { throw WorkspaceCloudError.invalidResponse }
            try await snapshotsA.fulfillPending()
            guard let offered = try await snapshotTransportC.status(id: snapshotRequestID).offer,
                  offered.chunkCount > 1 else { throw WorkspaceSyncError.invalidSnapshot }
            let tamperedSnapshot = WorkspaceSnapshotSync(repository: repositories[2], identity: seed.devices[2].identity, keys: deviceKeys[2],
                cryptography: try await deviceKeys[2].cryptography(), engine: engines[2],
                transport: TamperedSnapshotManifest(underlying: snapshotTransportC), blobs: interruptedBlobs,
                trust: managers[2], cacheDirectory: directory.appendingPathComponent("snapshots-tampered"))
            do {
                _ = try await tamperedSnapshot.receive(requestID: snapshotRequestID)
                throw WorkspaceCloudError.invalidResponse
            } catch WorkspaceSyncError.invalidSignature {}
            do {
                _ = try await snapshotsC.receive(requestID: snapshotRequestID)
                throw WorkspaceCloudError.invalidResponse
            } catch WorkspaceCloudError.rejected(status: 503, code: "isolated_download_interrupted") {}
            guard try await repositories[2].projection(identity: seed.devices[2].identity).messages.count == 1,
                  try await repositories[2].relayCursor() == 0 else { throw WorkspaceSyncError.invalidSnapshot }
            let tailMessage = try await chatA.sendMessage(commandID: UUID(), conversationID: conversationID, content: "After snapshot watermark")
            try await engines[0].synchronize()
            let resumedSnapshots = WorkspaceSnapshotSync(repository: repositories[2], identity: seed.devices[2].identity, keys: deviceKeys[2],
                cryptography: try await deviceKeys[2].cryptography(), engine: engines[2], transport: snapshotTransportC,
                blobs: interruptedBlobs, trust: managers[2], cacheDirectory: directory.appendingPathComponent("snapshots-c"))
            guard try await resumedSnapshots.receive(requestID: snapshotRequestID),
                  await interruptedBlobs.successfulReads(index: 0) == 1 else { throw WorkspaceSyncError.invalidSnapshot }
            let bootstrapped = try await repositories[2].projection(identity: seed.devices[2].identity)
            _ = try await resumedSnapshots.request(commandID: snapshotRequestID) // Replays the original cursor after installation.
            guard try await resumedSnapshots.pendingRequests().isEmpty else { throw WorkspaceSyncError.invalidSnapshot }
            guard bootstrapped.messages.contains(where: { $0.metadata.id == pendingMessage }),
                  bootstrapped.messages.contains(where: { $0.metadata.id == tailMessage }),
                  bootstrapped.messages.filter({ $0.conversationId == snapshotChat }).count == 3 else { throw WorkspaceSyncError.invalidSnapshot }
            let third = seed.devices[2]
            let agent = try await WorkspaceAgentService(repository: repositories[0], identity: first.identity).save(commandID: UUID(),
                draft: .init(name: "Lease test", instructions: "Only validate ownership"))
            let taskID = try await WorkspaceTaskService(repository: repositories[0], identity: first.identity).create(commandID: UUID(),
                conversationID: conversationID, agentID: agent, goal: "Lease verification", executorDeviceID: third.identity.deviceID)
            guard let task = try await repositories[0].record(BlotV3.Task.self, id: taskID, workspaceID: first.identity.workspaceID) else { throw WorkspaceStorageError.missingRecord }
            let ownerLeases = WorkspaceCloudLeases(http: http, authorization: sessions[0], identity: first.identity)
            let thirdLeases = WorkspaceCloudLeases(http: http, authorization: sessions[2], identity: third.identity)
            try await ownerLeases.register(task)
            let lease = try await thirdLeases.acquire(taskID: taskID)
            try await thirdLeases.check(lease)
            let otherProcess = WorkspaceCloudLeases(http: http, authorization: sessions[2], identity: third.identity)
            do {
                _ = try await otherProcess.acquire(taskID: taskID)
                throw WorkspaceCloudError.invalidResponse
            } catch WorkspaceCloudError.rejected(status: 409, code: "lease_held") {}
            let revokeID = UUID()
            let revoked = try await managers[0].revoke(commandID: revokeID, deviceID: third.identity.deviceID)
            guard revoked.epoch == 2, revoked.stoppedTasks.contains(taskID) else { throw WorkspaceCloudError.invalidResponse }
            guard try await managers[0].revoke(commandID: revokeID, deviceID: third.identity.deviceID) == revoked else { throw WorkspaceCloudError.invalidResponse }
            guard try await managers[1].receiveKeyRotations() else { throw WorkspaceSyncError.unknownKeyEpoch }
            for index in 0..<2 {
                engines[index] = WorkspaceSyncEngine(repository: repositories[index], identity: seed.devices[index].identity,
                    cryptography: try await deviceKeys[index].cryptography(),
                    transport: WorkspaceCloudSyncTransport(http: http, authorization: sessions[index]), trust: managers[index])
            }
            try await WorkspaceTaskService(repository: repositories[0], identity: first.identity).cancel(commandID: UUID(), taskID: taskID)
            let beforeRotationMessage = try await repositories[0].relayCursor()
            let attachmentData = Data(String(repeating: "SECRET-WIRE-ATTACHMENT-DO-NOT-LOG\n", count: 13_000).utf8)
            let filesA = WorkspaceFileService(repository: repositories[0], identity: first.identity, directory: directory.appendingPathComponent("files-a"))
            let filesB = WorkspaceFileService(repository: repositories[1], identity: second.identity, directory: directory.appendingPathComponent("files-b"))
            let artifactID = try await filesA.store(commandID: UUID(), name: "wire-notes.txt", mediaType: "text/plain", data: attachmentData)
            let fileTransportA = WorkspaceCloudAttachmentTransport(http: http, authorization: sessions[0])
            let attachmentA = WorkspaceAttachmentSync(repository: repositories[0], identity: first.identity, files: filesA,
                cryptography: try await deviceKeys[0].cryptography(), transport: fileTransportA, cacheDirectory: directory.appendingPathComponent("attachment-a"))
            try await attachmentA.upload(artifactID: artifactID)
            try await attachmentA.upload(artifactID: artifactID)
            let afterID = try await chatA.sendMessage(commandID: UUID(), conversationID: conversationID, content: "После отзыва", artifactIDs: [artifactID])
            try await engines[0].synchronize(); try await engines[1].synchronize()
            guard try await repositories[1].record(BlotV3.Message.self, id: afterID, workspaceID: first.identity.workspaceID)?.content == "После отзыва" else { throw WorkspaceSyncError.replayConflict }
            let attachmentB = WorkspaceAttachmentSync(repository: repositories[1], identity: second.identity, files: filesB,
                cryptography: try await deviceKeys[1].cryptography(), transport: WorkspaceCloudAttachmentTransport(http: http, authorization: sessions[1]),
                cacheDirectory: directory.appendingPathComponent("attachment-b"))
            try await attachmentB.download(artifactID: artifactID)
            guard try await filesB.data(for: artifactID) == attachmentData else { throw WorkspaceFileError.integrityMismatch }
            let newPackets = try await WorkspaceCloudSyncTransport(http: http, authorization: sessions[0]).pull(after: beforeRotationMessage, limit: 50)
            guard let packet = newPackets.deliveries.last?.packet, packet.keyEpoch == 2 else { throw WorkspaceSyncError.unknownKeyEpoch }
            let oldCrypto = try await deviceKeys[2].cryptography()
            let senderKey = try await managers[2].signingKey(for: first.identity.deviceID, sequence: packet.sequence)
            do {
                _ = try await oldCrypto.decrypt(packet, trustedSigningKey: senderKey)
                throw WorkspaceCloudError.invalidResponse
            } catch WorkspaceSyncError.unknownKeyEpoch {}
            do {
                try await thirdLeases.check(lease)
                throw WorkspaceCloudError.invalidResponse
            } catch WorkspaceCloudError.rejected(status: 401, code: "session_expired") {}
            do {
                try await engines[2].synchronize()
                throw WorkspaceCloudError.invalidResponse
            } catch WorkspaceCloudError.rejected(status: 401, code: "session_expired") {}
            let keychain = stores[0]
            guard let current = await sessions[0].current() else { throw WorkspaceCloudError.authenticationRequired }
            let saved = WorkspaceCloudTokensForSeed(sessionID: current.sessionID, accessToken: current.accessToken, refreshToken: current.refreshToken,
                expiresAt: "2020-01-01T00:00:00Z", ownerID: current.ownerID, workspaceID: current.workspaceID)
            try await keychain.write(JSONEncoder().encode(saved), name: "session")
            let session = WorkspaceCloudSession(http: http, credentials: keychain, credentialName: "session")
            _ = try await session.restore()
            async let tokenA = session.accessToken()
            async let tokenB = session.accessToken()
            let (one, two) = try await (tokenA, tokenB)
            guard one == two, one != current.accessToken else { throw WorkspaceCloudError.invalidResponse }
            guard let latest = await session.current() else { throw WorkspaceCloudError.authenticationRequired }
            let expiring = WorkspaceCloudTokensForSeed(sessionID: latest.sessionID, accessToken: latest.accessToken, refreshToken: latest.refreshToken,
                expiresAt: "2020-01-01T00:00:00Z", ownerID: latest.ownerID, workspaceID: latest.workspaceID)
            let delayed = SuspendedCredentials(initial: try JSONEncoder().encode(expiring))
            let raced = WorkspaceCloudSession(http: http, credentials: delayed, credentialName: "session")
            let restoring = _Concurrency.Task { () -> Bool in
                do { return try await raced.restore() != nil } catch { return false }
            }
            await delayed.waitForWrite()
            let forgetting = _Concurrency.Task { try await raced.forget() }
            while await raced.current() != nil { await _Concurrency.Task.yield() }
            await delayed.releaseWrite()
            try await forgetting.value
            guard await restoring.value == false, await delayed.read("session") == nil,
                  await raced.current() == nil, try await raced.restore() == nil else { throw WorkspaceCloudError.invalidResponse }
            print("PASS: Swift → signed AES-GCM → Java HTTP relay → SQLite; offline edits converge, duplicates do not multiply messages; native bootstrap, chained owner-approved pairing and ECDH key transfer succeed; signed multi-chunk snapshot waits for a donor, rejects a tampered manifest, resumes after interruption, preserves local changes and then receives the tail; revocation rotates history keys, fences the old device and cancels its lease; encrypted multi-chunk attachments arrive with SHA-256 verification; session refresh survives persistence and cannot restore credentials after logout.")
        default: throw WorkspaceCloudError.invalidConfiguration
        }
    }
    private static func pair(issuer: WorkspaceCloudDevices, receiver: WorkspaceCloudDevices, name: String, kind: String) async throws {
        let invite = try await issuer.createInvite()
        let claimed = try await receiver.claim(invite, name: name, kind: kind)
        guard let candidate = claimed.candidate else { throw WorkspaceCloudError.invalidResponse }
        let ownCandidate = try await receiver.candidateForConfirmation(name: name, kind: kind)
        let code = issuer.confirmationCode(invite: invite, candidate: candidate)
        guard code == receiver.confirmationCode(invite: invite, candidate: ownCandidate) else { throw WorkspaceSyncError.invalidSignature }
        // Simulated owner decision for a component test; the product UI must ask the owner.
        try await issuer.approve(invite, candidateID: candidate.id, confirmedCode: code)
        try await issuer.approve(invite, candidateID: candidate.id, confirmedCode: code)
        try await receiver.finishPairing(invite)
    }
}

private struct WorkspaceCloudTokensForSeed: Encodable {
    let sessionID: UUID
    let accessToken: String
    let refreshToken: String
    let expiresAt: String
    let ownerID: UUID
    let workspaceID: UUID
    let deviceID: UUID? = nil
    var bootstrapAllowed: Bool? = nil
}
private actor EphemeralCredentials: WorkspaceCredentialStore {
    private var values: [String: Data] = [:]
    func read(_ name: String) -> Data? { values[name] }
    func write(_ value: Data, name: String) { values[name] = value }
    func remove(_ name: String) { values.removeValue(forKey: name) }
}

private actor SuspendedCredentials: WorkspaceCredentialStore {
    private var value: Data?
    private var writeStarted = false
    private var writeWaiters: [CheckedContinuation<Void, Never>] = []
    private var release: CheckedContinuation<Void, Never>?
    init(initial: Data) { value = initial }
    func read(_ name: String) -> Data? { value }
    func write(_ data: Data, name: String) async {
        await withCheckedContinuation { continuation in
            release = continuation
            writeStarted = true
            for waiter in writeWaiters { waiter.resume() }
            writeWaiters = []
        }
        value = data
    }
    func remove(_ name: String) { value = nil }
    func waitForWrite() async {
        if writeStarted { return }
        await withCheckedContinuation { writeWaiters.append($0) }
    }
    func releaseWrite() { release?.resume(); release = nil }
}

/// Simulated network loss, while all successful requests still use the real HTTP blob service.
private actor InterruptedSnapshotBlobs: WorkspaceAttachmentTransport {
    let underlying: any WorkspaceAttachmentTransport
    private var interrupted = false
    private var reads: [Int: Int] = [:]
    init(underlying: any WorkspaceAttachmentTransport) { self.underlying = underlying }
    func put(_ chunk: WorkspaceEncryptedFileChunk) async throws { try await underlying.put(chunk) }
    func get(blobID: UUID, index: Int) async throws -> WorkspaceEncryptedFileChunk {
        if index == 1, !interrupted {
            interrupted = true
            throw WorkspaceCloudError.rejected(status: 503, code: "isolated_download_interrupted")
        }
        let value = try await underlying.get(blobID: blobID, index: index)
        reads[index, default: 0] += 1
        return value
    }
    func successfulReads(index: Int) -> Int { reads[index, default: 0] }
}

private struct TamperedSnapshotManifest: WorkspaceSnapshotTransport {
    let underlying: any WorkspaceSnapshotTransport
    func request(id: UUID, minimumCursor: Int64) async throws -> WorkspaceSnapshotStatus { try await underlying.request(id: id, minimumCursor: minimumCursor) }
    func pending() async throws -> [WorkspaceSnapshotRequest] { try await underlying.pending() }
    func publish(_ offer: WorkspaceSnapshotOffer) async throws { try await underlying.publish(offer) }
    func status(id: UUID) async throws -> WorkspaceSnapshotStatus {
        let status = try await underlying.status(id: id)
        var object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(status)) as! [String: Any]
        var offer = object["offer"] as! [String: Any]
        offer["relayCursor"] = (offer["relayCursor"] as! NSNumber).int64Value + 1
        object["offer"] = offer
        return try JSONDecoder().decode(WorkspaceSnapshotStatus.self, from: JSONSerialization.data(withJSONObject: object))
    }
}
