import BlotDomain
import BlotWorkspace
import CryptoKit
import Foundation
import OSLog
import Observation

nonisolated struct WorkspaceAccountProfile: Codable, Sendable {
    let id: UUID
    let email: String
    let name: String
    let verified: Bool
    var avatarURL: URL? = nil
}

/// Account lifecycle owns the local session. Commands never implicitly create an anonymous workspace.
@MainActor @Observable
final class WorkspaceAccountApplicationService: WorkspaceDevicePairingProviding, WorkspaceDeviceProviding, WorkspaceAccountDeleting, WorkspaceFileProviding, WorkspaceSkillProviding, WorkspaceService, WorkspaceAccountService, WorkspaceCommandProviding, WorkspaceAccountSynchronizing {
    private var defaultWorkspacePrepared = false
    private let browser = WorkspaceBrowserAuthenticator()
    private let installation: AppleInstallationConfiguration
    private let http: WorkspaceCloudHTTP
    private let session: WorkspaceCloudSession
    private let credentials: WorkspaceKeychain
    private let directory: URL
    private let authenticationLog = Logger(subsystem: "dev.blot.authentication", category: "AccountSession")
    private var erasingAccount = false
    private var local: LocalWorkspaceService?
    private var localDirectory: URL?
    private var processLock: WorkspaceProcessLock?
    private var cloudBackup: WorkspaceCloudBackup?
    private(set) var profile: WorkspaceAccountProfile?
    var workspacePairing: (any WorkspaceDevicePairingCommands)? { local?.workspacePairing }
    var workspaceDevices: (any WorkspaceDeviceCommands)? { local?.workspaceDevices }
    var workspaceFiles: (any WorkspaceFileCommands)? { local }
    var workspaceSkills: (any WorkspaceSkillCommands)? { local }
    var workspaceCommands: (any WorkspaceCommandService)? { local }
    var isAuthenticated: Bool { local != nil }

    init(installation: AppleInstallationConfiguration, directory: URL) throws {
        self.installation = installation
        guard let origin = installation.accountServiceURL else { throw WorkspaceCloudError.invalidConfiguration }
        http = try WorkspaceCloudHTTP(origin: origin, allowLoopbackHTTP: true)
        let originID = SHA256.hash(data: Data(origin.absoluteString.utf8)).map { String(format: "%02x", $0) }.joined()
        self.directory = directory.appendingPathComponent(originID, isDirectory: true)
        credentials = WorkspaceKeychain(service: "dev.blot.apple.accounts." + originID)
        session = WorkspaceCloudSession(http: http, credentials: credentials, credentialName: "account-session")
    }
    func load() async throws -> WorkspaceSnapshot? {
        if !defaultWorkspacePrepared {
            do { try await LocalWorkspaceService.prepareDefaultWorkspaceRoot(); defaultWorkspacePrepared = true }
            catch { authenticationLog.error("Could not prepare the local Blot working folder") }
        }
        try await WorkspaceAccountErasure(root: directory, credentials: credentials).resume { owner in
            try await MainActor.run { try WorkspaceModelCredentialStore.removeAccount(owner) }; await WorkspaceBrowserProfile.erase(self.directory.appendingPathComponent(owner.uuidString)); try await LocalWorkspaceService.eraseSessionFiles(ownerID: owner)
        }
        try await installation.install(credentials: WorkspaceKeychain(service: "dev.blot.apple.build-managed"))
        let tokens: WorkspaceCloudTokens?
        do { tokens = try await session.restore() }
        catch is URLError { tokens = await session.current() }
        guard let tokens else { return nil }
        do {
            authenticationLog.info("Restoring saved account session")
            try await open(tokens)
            authenticationLog.info("Saved account workspace ready")
        } catch {
            reportAuthenticationFailure(error, stage: "restore-workspace")
            throw error
        }
        return try await local?.load()
    }
    func execute(_ request: WorkspaceRequest, snapshot: WorkspaceSnapshot) async throws -> WorkspaceSnapshot {
        guard !erasingAccount else { throw WorkspaceStorageError.permissionDenied }
        let account = request.form.account
        switch request.action {
        case .register, .resendVerification:
            try await session.register(email: account.email, password: account.password, name: account.name)
            return snapshot
        case .signIn:
            try await open(session.login(email: account.email, password: account.password))
            return try await requireLocal().load() ?? WorkspaceSnapshot()
        case .verify:
            try await open(session.verify(email: account.email, code: account.code))
            return try await requireLocal().load() ?? WorkspaceSnapshot()
        case .recover:
            try await session.requestPasswordReset(email: account.email)
            return snapshot
        case .resetPassword:
            try await session.resetPassword(email: account.email, code: account.code, password: account.password)
            return snapshot
        case .oauth:
            guard local == nil else { throw WorkspaceCloudError.authenticationRequired }
            guard let url = installation.authURL else { throw WorkspaceCloudError.invalidConfiguration }
            #if os(macOS)
            let platform = "macos"
            #else
            let platform = "ios"
            #endif
            let authorization = try WorkspaceBrowserAuthorization(loginURL: url, platform: platform,
                registering: request.form.account.browserRegistering)
            var stage = "browser"
            do {
                authenticationLog.info("Starting account browser authorization")
                let callback = try await browser.signIn(authorization)
                stage = "token-exchange"
                authenticationLog.info("Browser callback received; exchanging one-time code")
                let tokens = try await session.exchange(authorization: authorization, callback: callback)
                stage = "open-workspace"
                authenticationLog.info("Account session saved; opening local workspace")
                try await open(tokens)
                let result = try await requireLocal().load() ?? WorkspaceSnapshot()
                authenticationLog.info("Account sign-in complete")
                return result
            } catch {
                reportAuthenticationFailure(error, stage: stage)
                throw error
            }
        default:
            let result = try await requireLocal().execute(request, snapshot: snapshot)
            return result
        }
    }
    func synchronizeAccount() async throws {
        guard let cloudBackup else { throw WorkspaceCloudError.authenticationRequired }
        try await cloudBackup.synchronize()
    }

    func requestAccountDeletion() async throws {
        guard local != nil else { throw WorkspaceCloudError.authenticationRequired }
        try await http.empty(method: "POST", path: ["v1", "auth", "account", "delete", "request"], accessToken: session.accessToken())
    }
    func confirmAccountDeletion(code: String) async throws {
        guard !erasingAccount, local != nil, let owner = profile?.id, let tokens = await session.current(),
              tokens.ownerID == owner, code.range(of: #"^[0-9]{6}$"#, options: .regularExpression) != nil else { throw WorkspaceStorageError.invalidParameters }
        erasingAccount = true; defer { erasingAccount = false }
        let identity = try await requireLocal().repository.accountIdentity(ownerID: owner, workspaceID: tokens.workspaceID)
        let erasure = WorkspaceAccountErasure(root: directory, credentials: credentials)
        await local?.suspendAccountOperations()
        await cloudBackup?.stop()
        do {
            try await http.empty(method: "POST", path: ["v1", "auth", "account", "delete"], body: JSONEncoder().encode(["code": code]), accessToken: session.accessToken())
        } catch {
            try? await local?.resumeAccountOperations()
            await cloudBackup?.start()
            throw error
        }
        do {
            try erasure.mark(identity)
            try await endSession(removing: nil, revokeRemote: false)
            try await erasure.resume { owner in try await MainActor.run { try WorkspaceModelCredentialStore.removeAccount(owner) }; await WorkspaceBrowserProfile.erase(self.directory.appendingPathComponent(owner.uuidString)); try await LocalWorkspaceService.eraseSessionFiles(ownerID: owner) }
        } catch {
            try? await endSession(removing: nil, revokeRemote: false)
            throw WorkspaceAccountDeletionFailure.localCleanupIncomplete
        }
    }

    func signOut() async throws { try await endSession(removing: nil) }

    private func endSession(removing directory: URL?, revokeRemote: Bool = true) async throws {
        let previous = local
        let ownerID = profile?.id
        // Invalidate access before joining workers, closing SQLite and removing files.
        local = nil; localDirectory = nil; profile = nil
        await previous?.stopAll()
        await cloudBackup?.stop()
        cloudBackup = nil
        var failure: (any Error)?
        var closed = false
        do { try await previous?.close(); closed = true } catch { failure = error }
        processLock = nil
        if let directory, closed {
            do {
                if FileManager.default.fileExists(atPath: directory.path) { try FileManager.default.removeItem(at: directory) }
                if let ownerID { try await credentials.remove("profile:" + ownerID.uuidString) }
            } catch { failure = error }
        }
        do { if revokeRemote { try await session.logout() } else { try await session.forget() } } catch { if failure == nil { failure = error } }
        if let failure { throw failure }
    }


    private func requireLocal() throws -> LocalWorkspaceService {
        guard let local else { throw WorkspaceCloudError.authenticationRequired }
        return local
    }
    private func reportAuthenticationFailure(_ error: any Error, stage: String) {
        if case let WorkspaceCredentialError.unavailable(status) = error {
            authenticationLog.error("Account sign-in failed stage=\(stage, privacy: .public) KeychainOSStatus=\(status)")
        } else if case let WorkspaceCloudError.rejected(status, _) = error {
            authenticationLog.error("Account sign-in failed stage=\(stage, privacy: .public) HTTP=\(status)")
        } else {
            let failure = error as NSError
            authenticationLog.error("Account sign-in failed stage=\(stage, privacy: .public) domain=\(failure.domain, privacy: .public) code=\(failure.code)")
        }
    }
    private func open(_ tokens: WorkspaceCloudTokens) async throws {
        if let local {
            let snapshot = try await local.currentSnapshot()
            guard snapshot.ownerID == tokens.ownerID else { throw WorkspaceSyncError.identityMismatch }
            return
        }
        let accountDirectory = directory.appendingPathComponent(tokens.ownerID.uuidString, isDirectory: true)
            .appendingPathComponent(tokens.workspaceID.uuidString, isDirectory: true)
        let lock = try WorkspaceProcessLock(directory: accountDirectory)
        let database = accountDirectory.appendingPathComponent("workspace-v3.sqlite")
        let repository = try WorkspaceRepository(url: database)
        do {
            let identity = try await repository.accountIdentity(ownerID: tokens.ownerID, workspaceID: tokens.workspaceID)
            let backup = WorkspaceCloudBackup(repository: repository, identity: identity,
                transport: WorkspaceHTTPBackupTransport(http: http, authorization: session))
            // Offline access remains available; the worker retries when connectivity returns.
            await backup.refresh()
            let deviceAuthority = try await WorkspaceDeviceAuthority.open(identity: identity, credentials: credentials)
            let model = try installation.makeModel()
            let modelCredentials = WorkspaceModelCredentialStore(accountNamespace: identity.ownerID.uuidString + ":" + identity.deviceID.uuidString)
            let service = try LocalWorkspaceService(databaseURL: database, repository: repository, identity: identity,
                maximumOutputTokens: installation.gigaChat.outputTokens, runTokenBudget: installation.gigaChat.runTokenBudget, deviceAuthority: deviceAuthority, mcpCredentials: credentials,
                automaticBrowserAccess: true, automaticSessionFiles: true, makeModel: { modelID in
                    if modelID == "gigachat" { return model }
                    let config = try modelCredentials.load()
                    return try CompatibleChatModel(endpoint: config.endpoint, model: config.model, apiKey: config.apiKey)
                })
            _ = try await service.load()
            local = service; localDirectory = accountDirectory; processLock = lock
            cloudBackup = backup
            await backup.start()
            if let cached = try await credentials.read("profile:" + tokens.ownerID.uuidString) {
                profile = try? JSONDecoder().decode(WorkspaceAccountProfile.self, from: cached)
            }
            if profile == nil { await refreshProfile(ownerID: tokens.ownerID, local: service) }
            else { _Concurrency.Task { [weak self] in await self?.refreshProfile(ownerID: tokens.ownerID, local: service) } }

        } catch { try? await repository.close(); throw error }
    }
    private func refreshProfile(ownerID: UUID, local expected: LocalWorkspaceService) async {
        if let value = try? await http.request(WorkspaceAccountProfile.self, method: "GET", path: ["v1", "auth", "me"], accessToken: session.accessToken()),
           local === expected, value.id == ownerID {
            profile = value
            try? await credentials.write(JSONEncoder().encode(value), name: "profile:" + value.id.uuidString)
        }
    }

}

extension WorkspaceAccountApplicationService: WorkspaceAccountPasswordChanging, WorkspaceLocalAccountDeleting {
    func requestPasswordChangeCode() async throws {
        guard local != nil, let profile else { throw WorkspaceCloudError.authenticationRequired }
        try await session.requestPasswordReset(email: profile.email)
    }
    func changePassword(code: String, password: String) async throws {
        guard local != nil, let profile else { throw WorkspaceCloudError.authenticationRequired }
        try await session.resetPassword(email: profile.email, code: code, password: password)
    }
    func deleteLocalAccountData() async throws {
        guard local != nil, let directory = localDirectory else { throw WorkspaceCloudError.authenticationRequired }
        try await endSession(removing: directory)
    }
}
