import BlotDomain
import BlotWorkspace
import Foundation
import Observation
import OSLog


@MainActor @Observable
final class WorkspaceStore {
    enum Mode { case live, preview }
    enum ScreenState: String, CaseIterable { case normal, empty, loading, error, offline, limit, unavailable, unknown }
    let mode: Mode
    private let service: any WorkspaceService
    private var commands: (any WorkspaceCommandService)? { (service as? any WorkspaceCommandProviding)?.workspaceCommands }
    @ObservationIgnored private var observation: _Concurrency.Task<Void, Never>?
    @ObservationIgnored private var restoringPresentation = false
    private var sessionGeneration = UUID()
    @ObservationIgnored private let authenticationLog = Logger(subsystem: "dev.blot.authentication", category: "BrowserHandoff")
    private(set) var snapshot = WorkspaceSnapshot() {
        didSet { if mode == .live { refreshLocalChatState() } }
    }
    private(set) var busy = false
    private(set) var history: [WorkspaceRoute] = []
    var route: WorkspaceRoute
    var rootRoute: WorkspaceRoute
    var settingsRoute: WorkspaceRoute?
    var tab: WorkspaceRoute = .chats
    var form = WorkspaceForm() {
        didSet {
            if !restoringComposer, form.composer.draft != oldValue.composer.draft, !form.composer.draft.isEmpty,
               route == .chat, let id = selectedConversationID { chatActivity.activate(id) }
            #if os(iOS)
            persistWorkspace()
            #else
            persistChatState()
            #endif
        }
    }
    var screenState = ScreenState.normal
    var invalidField: String?
    var error: String?
    var notice: String?
    @ObservationIgnored private var restoringComposer = false
    var selectedConversationID: UUID? {
        willSet {
            if newValue != selectedConversationID, let id = selectedConversationID { conversationDrafts[id] = form.composer }
        }
        didSet {
            if oldValue != selectedConversationID {
                restoringComposer = true
                form.composer = selectedConversationID.flatMap { conversationDrafts[$0] } ?? WorkspaceComposerForm()
                restoringComposer = false
            }
        }
    }
    var selectedAgentID: UUID?
    var selectedRecordID: UUID?
    var inspectorVisible = false
    var sidebarVisible = true
    var catalogVisible = false
    var groupCreationVisible = false
    var conflictsVisible = false
    var messageNavigationTarget: UUID?
    var taskPaused = false
    let chatActivity = WorkspaceChatActivity()
    private(set) var chatInteractions = WorkspaceChatInteractions() {
        didSet {
            persistChatState()
        }
    }
    var pendingChatDeletionID: UUID?
    var pendingChatRenameID: UUID?
    var chatTitleDraft = ""
    private(set) var replyFocusRequest = UUID()
    private var conversationDrafts: [UUID: WorkspaceComposerForm] = [:]
    private var liveResponses: [UUID: _Concurrency.Task<Void, Never>] = [:]
    @ObservationIgnored private var loadedWorkspace = false
    @ObservationIgnored private var loadingWorkspace: _Concurrency.Task<Void, Never>?
    private var pendingSendCommands: [UUID: (UUID, String)] = [:]
    @ObservationIgnored private var pendingReadConversations: Set<UUID> = []
    private(set) var failedSends: [UUID: WorkspaceComposerForm] = [:]
    @ObservationIgnored private var readingConversationID: UUID?
    @ObservationIgnored private var readingLatest = false
    #if os(macOS)
    let desktopContent = MacConversationPresentation()
    #endif
    #if os(iOS)
    var authenticationSession: PhoneAuthenticationSession?
    var authenticationRoute: WorkspaceRoute? {
        get { authenticationSession?.route }
        set {
            if let newValue {
                if authenticationSession != nil { authenticationSession?.route = newValue }
                else { authenticationSession = PhoneAuthenticationSession(route: newValue) }
            } else { authenticationSession = nil }
        }
    }
    var notificationPreferences = PhoneNotificationPreferences() { didSet { persistWorkspace() } }
    var tokenUsage: [PhoneTokenUsage] {
        (snapshot.modelSteps ?? []).compactMap { step in
            guard let input = step.inputTokens, let output = step.outputTokens else { return nil }
            let agentID = snapshot.configurations?.first { $0.metadata.id == step.configurationId }?.agentId
            let name = snapshot.agents.first { $0.metadata.id == agentID }?.name ?? "Blot Agent"
            return .init(id: step.metadata.id, date: step.metadata.createdAt, modelID: step.modelId,
                agentName: name, inputTokens: input, outputTokens: output)
        }
    }
    var unknownUsageCount: Int { (snapshot.modelSteps ?? []).filter { $0.state != .running && ($0.inputTokens == nil || $0.outputTokens == nil) }.count }
    let notifications = PhoneNotifications()
    var profileEditorVisible = false
    var profile = PhoneProfileRecord() { didSet { persistWorkspace() } }
    var agentCreationVisible = false
    var pluginCatalogVisible = false
    var agentPickerVisible = false
    var agentAppearanceVisible = false
    var preferredAgentID: UUID?
    private var prefersGeneralChat = false
    let navigation = PhoneWorkspaceNavigation()
    #endif
    var language: String {
        didSet {
            if mode == .live { UserDefaults.standard.set(language, forKey: "blot.v3.language") }
            #if os(iOS)
            persistWorkspace()
            #endif
        }
    }
    var isPreview: Bool { mode != .live }

    init(mode: Mode = .live, route: WorkspaceRoute? = nil, service: (any WorkspaceService)? = nil) {
        self.mode = mode
        self.inspectorVisible = mode == .preview
        self.route = route ?? .welcome
        self.rootRoute = route ?? .welcome
        if let route, [.chats, .agents, .files, .settings].contains(route) { self.tab = route }
        #if os(iOS)
        if mode == .preview, let route, ![WorkspaceRoute.welcome, .chats, .agents, .files, .settings].contains(route) {
            self.rootRoute = route.isAuthentication ? .welcome : .chats
            self.history = [route]
        }
        #endif
        self.service = service ?? (mode == .live ? UnavailableWorkspaceService() : PreviewWorkspaceService())
        self.language = mode == .preview ? "en" : UserDefaults.standard.string(forKey: "blot.v3.language") ?? "ru"
        if mode != .live {
            do {
                let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
                snapshot = try decoder.decode(WorkspaceSnapshot.self, from: WorkspacePreviewData.data)
                #if os(iOS)
                snapshot = try WorkspaceChatOperations.migratePins(in: snapshot, agentIDs: Set(snapshot.agents.prefix(3).map(\.metadata.id)))
                chatInteractions.pinnedOrder = snapshot.agents.prefix(3).compactMap { agent in
                    snapshot.conversations.first { $0.agentId == agent.metadata.id && $0.pinned }?.metadata.id
                }
                #endif
                selectedConversationID = snapshot.conversations.first?.metadata.id
                selectedAgentID = route == .agentProfile ? snapshot.agents.dropFirst().first?.metadata.id : snapshot.agents.first?.metadata.id
                form.agent.name = "Designer"
                if mode == .preview { form.account.name = "Yaroslav" }
                form.schedule.name = "Morning digest"
                var calendar = Calendar(identifier: .gregorian)
                calendar.timeZone = TimeZone(identifier: "Asia/Yekaterinburg")!
                form.schedule.time = calendar.date(from: DateComponents(year: 2026, month: 11, day: 2, hour: 8, minute: 30))!
                if mode == .preview { form.account.email = "preview@blot.local" }
                form.agent.instructions = "Help with interfaces: research references, propose options and check usability."
                form.schedule.goal = "Build a morning digest: today's meetings, priority tasks and key emails."
            } catch { self.error = "Preview data could not be decoded: \(error.localizedDescription)" }
        }
        #if os(iOS)
        if mode != .live {
            do { snapshot.artifacts = try PhoneWorkspaceFiles.prepare(snapshot.artifacts) }
            catch { self.error = t("Couldn’t load local files.") }
            if mode == .preview, route == .file { selectedRecordID = snapshot.artifacts.first?.metadata.id }
        }
        #endif
    
    }
    var currentConversation: BlotV3.Conversation? { snapshot.conversations.first { $0.metadata.id == selectedConversationID } }
    var currentMessages: [BlotV3.Message] {
        let messages = snapshot.messages.filter { $0.conversationId == selectedConversationID }
        return mode == .live ? WorkspaceMessageOrder.ordered(messages) : messages
    }

    func loadWorkspace() async {
        if let loadingWorkspace { await loadingWorkspace.value; return }
        guard mode == .live, !loadedWorkspace else { return }
        let worker = _Concurrency.Task { [weak self] in
            guard let self else { return }
            await self.restoreInitialWorkspace()
        }
        loadingWorkspace = worker
        await worker.value
        loadingWorkspace = nil
    }

    private func restoreInitialWorkspace() async {
        guard mode == .live, !loadedWorkspace else { return }
        loadedWorkspace = true
        do {
            if let saved = try await service.load() {
                snapshot = saved
                await enterWorkspace()
            }
        } catch {
            loadedWorkspace = false
            self.error = WorkspaceFailureCopy.message(error)
        }
    }

    private func enterWorkspace() async {
        restoringPresentation = true
        defer { restoringPresentation = false }
        if let data = try? await commands?.presentationState(), let saved = try? JSONDecoder().decode(WorkspacePresentationState.self, from: data) {
            conversationDrafts = saved.drafts; chatInteractions = saved.interactions
            form.personalization = saved.personalization
            form.account.name = saved.firstName; form.account.lastName = saved.lastName; form.account.email = saved.email
        }
        if let profile = (service as? any WorkspaceAccountService)?.profile {
            form.account.name = profile.name; form.account.email = profile.email
        }
        #if os(iOS)
        authenticationRoute = nil; notifications.accountActive = true
        navigation.reset()
        #endif
        form.account.password = ""; form.account.code = ""
        #if os(macOS)
        selectTab(.home)
        #else
        selectTab(.chats)
        #endif
        observeWorkspace()
    }

    private func observeWorkspace() {
        observation?.cancel()
        guard let commands else { return }
        let generation = sessionGeneration
        observation = _Concurrency.Task { [weak self] in
            for await _ in await commands.changes() {
                guard !_Concurrency.Task.isCancelled, let self, self.sessionGeneration == generation else { return }
                do {
                    let saved = try await commands.currentSnapshot()
                    guard self.sessionGeneration == generation else { return }
                    if saved != self.snapshot { self.snapshot = saved }
                } catch { self.error = "Не удалось обновить локальные данные." }
            }
        }
    }

    func openAuthenticationURL(_ url: URL) {
        #if os(macOS)
        let scheme = "blot-agent-macos"
        #else
        let scheme = "blot-agent-ios"
        #endif
        guard mode == .live, url.scheme == scheme, url.host == nil, url.path == "/oauth/start",
              url.query == nil, url.fragment == nil, url.user == nil, url.password == nil else { return }
        authenticationLog.info("Received website sign-in launch")
        _Concurrency.Task {
            await loadWorkspace()
            guard !busy else { authenticationLog.info("Sign-in already in progress"); return }
            if (service as? any WorkspaceAccountService)?.isAuthenticated == true {
                notice = "Вы уже вошли в приложение. Для смены аккаунта сначала выйдите."
                return
            }
            authenticationLog.info("Starting browser sign-in")
            form.account.browserRegistering = false
            await perform(.oauth)
        }
    }

    func openConversation(_ id: UUID) {
        #if os(macOS)
        if desktopContent.prefersWideLayout(id) { inspectorVisible = false }
        #endif
        updateChatVisibility(nil, atLatest: false)
        selectedConversationID = id
        selectedAgentID = currentConversation?.agentId
        navigate(.chat)
    }
    func openAgentChat(_ id: UUID?) async {
        selectedAgentID = id
        if let id, let conversation = snapshot.conversations.filter({ $0.agentId == id && !$0.archived }).max(by: { $0.metadata.updatedAt < $1.metadata.updatedAt }) { openConversation(conversation.metadata.id) }
        else { await perform(.createConversation, next: .chat) }
    }
    #if os(macOS)
    func sendDesktopMessage() async {
        guard !busy, !form.composer.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !form.composer.attachments.isEmpty else { return }
        if [.home, .newChat].contains(route) || selectedConversationID == nil {
            let composer = form.composer
            await perform(.createConversation)
            guard error == nil else { return }
            form.composer = composer
        }
        await perform(.send, next: .chat)
    }

    func createDesktopAgentAndStartChat() async {
        guard !busy else { return }
        if form.agent.instructions.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            form.agent.instructions = t("Help the user with tasks related to this role. Ask for missing details before acting.") + " " + form.agent.name
        }
        let count = snapshot.agents.count
        await perform(.createAgent)
        guard error == nil, snapshot.agents.count > count, let agent = snapshot.agents.last else { return }
        await perform(.createConversation)
        guard error == nil, let id = selectedConversationID else { return }
        desktopContent.prepareFirstConversation(id, agent: agent)
        inspectorVisible = false
        selectTab(.chat)
    }

    func sendDesktopAnswer(_ text: String, questionID: UUID) async {
        guard !busy, desktopContent.answers[questionID] == nil else { return }
        let original = form.composer
        let conversationID = selectedConversationID
        form.composer = WorkspaceComposerForm(draft: text)
        await sendDesktopMessage()
        if error == nil { desktopContent.answered(questionID, text: text) }
        if selectedConversationID == conversationID { form.composer = original }
    }
    #endif
    func t(_ english: String) -> String { WorkspaceCopy.text(english, language: language) }
    func navigate(_ destination: WorkspaceRoute) {
        if mode == .live, [.signIn, .createAccount].contains(destination) {
            form.account.browserRegistering = destination == .createAccount
            _Concurrency.Task { await perform(.oauth) }
            return
        }
        guard mode != .live || commands != nil || destination.isAuthentication else { return }
        if destination != .chat { updateChatVisibility(nil, atLatest: false) }
        error = nil; notice = nil
        #if os(macOS)
        if destination == .home { selectedConversationID = nil }
        if destination == .createAgent {
            form.agent = WorkspaceAgentForm(name: UserDefaults.standard.string(forKey: MacTeamPreferenceKey.defaultRole) ?? "",
                instructions: UserDefaults.standard.string(forKey: MacTeamPreferenceKey.defaultInstructions) ?? "",
                shape: "round", color: "blue")
        }
        #endif
        #if os(iOS)
        PhoneKeyboard.dismiss()
        if destination == .newChat, mode != .preview {
            _Concurrency.Task { await startNewChat() }
            return
        }
        if destination == .createAgent { beginAgentCreation(); return }
        if destination == .createSchedule { prepareSchedule() }
        if destination == .connections { pluginCatalogVisible = true; return }
        if [.signIn, .createAccount].contains(destination) {
            authenticationRoute = destination
            return
        }
        #endif
        if destination == .createSchedule, mode == .live {
            form.schedule.deviceID = form.schedule.deviceID ?? snapshot.localDeviceID
            form.schedule.agentID = form.schedule.agentID ?? selectedAgentID ?? snapshot.agents.first?.metadata.id
        }
        if destination.isSetting {
            #if os(macOS)
            settingsRoute = destination
            #else
            history.append(destination); route = destination
            #endif
        } else {
            history.append(destination); route = destination
        }
    }
    func back() {
        updateChatVisibility(nil, atLatest: false)
        #if os(iOS)
        PhoneKeyboard.dismiss()
        #endif
        error = nil; _ = history.popLast(); route = history.last ?? rootRoute
    }
    func restoreNavigation(_ path: [WorkspaceRoute]) {
        #if os(iOS)
        if path != history { PhoneKeyboard.dismiss() }
        #endif
        history = path; route = path.last ?? rootRoute
    }
    func selectTab(_ destination: WorkspaceRoute) {
        guard mode != .live || commands != nil || destination.isAuthentication else { return }
        if destination != .chat { updateChatVisibility(nil, atLatest: false) }
        #if os(iOS)
        PhoneKeyboard.dismiss()
        if PhoneTabBar.isTab(rootRoute) {
            navigation.remember(.init(path: history, conversationID: selectedConversationID,
                                      agentID: selectedAgentID, recordID: selectedRecordID), for: rootRoute)
        }
        let context = navigation.context(for: destination)
        tab = destination; rootRoute = destination
        history = context?.path ?? []; route = history.last ?? destination
        if let context {
            selectedConversationID = context.conversationID
            selectedAgentID = context.agentID; selectedRecordID = context.recordID
        }
        #else
        tab = destination; rootRoute = destination; route = destination; history = []
        #endif
        error = nil
    }
    func selectAgent(_ id: UUID, destination: WorkspaceRoute = .agentProfile) {
        selectedAgentID = id
        if let agent = snapshot.agents.first(where: { $0.metadata.id == id }) {
            form.agent.name = agent.name; form.agent.instructions = agent.instructions
            form.agent.shape = agent.avatarShape; form.agent.color = agent.avatarColor
            form.agent.modelID = agent.modelId
            form.agent.toolIDs = snapshot.configurations?.filter { $0.agentId == id }.max(by: { $0.revision < $1.revision })?.toolIds ?? []
        }
        navigate(destination)
    }
    func perform(_ action: WorkspaceAction, next: WorkspaceRoute? = nil) async {
        guard !busy else { return }
        if mode == .live, action == .send, let id = selectedConversationID, liveResponses[id] != nil {
            error = "Дождитесь ответа или остановите его перед новым сообщением."
            return
        }
        error = nil; notice = nil; invalidField = nil
        guard validate(action) else { return }
        busy = true
        defer { busy = false }
        let generation = sessionGeneration
        let submittedConversationID = selectedConversationID
        let submittedComposer = form.composer
        var input = form.requestInput(for: action)
        if action == .send {
            input.messageContext = currentMessageContext
            #if os(macOS)
            input.messageContext.agentActivity = desktopContent.context(in: selectedConversationID, snapshot: snapshot)
            #endif
        }
        do {
            var request = WorkspaceRequest(action: action, form: input, selectedAgentID: selectedAgentID,
                selectedConversationID: selectedConversationID, selectedRecordID: selectedRecordID)
            if mode == .live, action == .send, let id = submittedConversationID {
                if let pending = pendingSendCommands[id], pending.1 == input.composer.draft { request.commandID = pending.0 }
                else { pendingSendCommands[id] = (request.commandID, input.composer.draft) }
            }
            let result = try await service.execute(request, snapshot: snapshot)
            guard sessionGeneration == generation else { return }
            snapshot = result
            if [.signIn, .verify, .oauth].contains(action) { await enterWorkspace(); return }
            if action == .register {
                #if os(iOS)
                authenticationRoute = nil
                #endif
                navigate(.verifyEmail); return
            }
            if action == .recover { notice = "Если адрес зарегистрирован, письмо с кодом восстановления отправлено."; return }
            if action == .resetPassword {
                form.account.password = ""; form.account.code = ""
                navigate(.signIn); notice = "Пароль изменён. Войдите с новым паролем."; return
            }
            if action == .resendVerification { notice = "Код подтверждения отправлен."; return }
            if action == .saveModelKey {
                form.model.secret = ""
                if mode == .live { notice = "Ключ сохранён на этом устройстве." }
            }
            if action == .createConversation { selectedConversationID = snapshot.conversations.last?.metadata.id }
            if action == .createAgent { selectedAgentID = snapshot.agents.last?.metadata.id }
            if action == .send {
                if submittedConversationID == selectedConversationID { form.composer = WorkspaceComposerForm() }
                if let submittedConversationID { conversationDrafts[submittedConversationID] = nil }
            }
            if action == .send, let sent = snapshot.messages.last, sent.role == .user {
                pendingSendCommands[sent.conversationId] = nil
                chatInteractions.messages[sent.metadata.id, default: WorkspaceMessageMetadata()].replyToMessageID = submittedComposer.replyToMessageID
                failedSends[sent.conversationId] = nil
                if mode != .live { touchConversation(sent.conversationId) }
                if mode == .live { enqueueLiveResponse(to: sent) }
            }
            persistChatState()
            if action == .pause { taskPaused.toggle() }
            if let next, next != route {
                if [.chats, .home, .agents, .schedules, .files].contains(next) { selectTab(next) }
                else { navigate(next) }
            }
        } catch {
            if action == .send, let submittedConversationID { failedSends[submittedConversationID] = submittedComposer }
            guard sessionGeneration == generation else { return }
            self.error = WorkspaceFailureCopy.message(error)
        }
    }
    var pinnedConversationIDs: Set<UUID> {
        Set(snapshot.conversations.filter { $0.pinned && !$0.archived }.map(\.metadata.id))
    }

    var pinnedConversations: [BlotV3.Conversation] {
        let order = chatInteractions.pinnedOrder
        return snapshot.conversations.filter { $0.pinned && !$0.archived }.sorted {
            let lhs = order.firstIndex(of: $0.metadata.id) ?? Int.max
            let rhs = order.firstIndex(of: $1.metadata.id) ?? Int.max
            return lhs == rhs ? $0.metadata.updatedAt > $1.metadata.updatedAt : lhs < rhs
        }
    }

    var currentReplyTarget: BlotV3.Message? {
        guard let id = form.composer.replyToMessageID else { return nil }
        return currentMessages.first { $0.metadata.id == id }
    }

    var currentMessageContext: WorkspaceMessageContext {
        var context = WorkspaceMessageContext()
        if let target = currentReplyTarget {
            context.quote = .init(messageID: target.metadata.id, author: messageAuthor(target), text: t(target.content))
        }
        let reacted = currentMessages.filter { chatInteractions.messages[$0.metadata.id]?.reaction != nil }.sorted {
            (chatInteractions.messages[$0.metadata.id]?.reactedAt ?? $0.metadata.createdAt) <
            (chatInteractions.messages[$1.metadata.id]?.reactedAt ?? $1.metadata.createdAt)
        }
        context.feedback = reacted.compactMap { message in
            guard let reaction = chatInteractions.messages[message.metadata.id]?.reaction else { return nil }
            return .init(messageID: message.metadata.id, text: t(message.content), reaction: reaction)
        }
        return context
    }

    func messageAuthor(_ message: BlotV3.Message) -> String {
        if message.role == .user { return accountDisplayName }
        let agentID = message.authorAgentId ?? snapshot.conversations.first { $0.metadata.id == message.conversationId }?.agentId
        return snapshot.agents.first { $0.metadata.id == agentID }?.name ?? "Blot Agent"
    }

    func beginReply(to messageID: UUID) {
        guard currentMessages.contains(where: { $0.metadata.id == messageID }) else { return }
        form.composer.replyToMessageID = messageID
        replyFocusRequest = UUID()
    }

    func toggleReaction(_ reaction: String, to messageID: UUID) {
        guard WorkspaceChatInteractions.reactions.contains(reaction), currentMessages.contains(where: { $0.metadata.id == messageID }) else { return }
        if mode == .live, let service = commands {
            let removed = chatInteractions.messages[messageID]?.reaction == reaction
            _Concurrency.Task {
                do { applyMutationSnapshot(try await service.setReaction(messageID: messageID, emoji: reaction, removed: removed)) }
                catch { self.error = "Не удалось сохранить реакцию." }
            }
            return
        }
        var metadata = chatInteractions.messages[messageID] ?? WorkspaceMessageMetadata()
        metadata.reaction = metadata.reaction == reaction ? nil : reaction
        metadata.reactedAt = metadata.reaction == nil ? nil : Date()
        chatInteractions.messages[messageID] = metadata
    }

    func toggleChatPin(_ id: UUID) {
        guard !busy, let index = snapshot.conversations.firstIndex(where: { $0.metadata.id == id }) else { return }
        if mode == .live { updateLocalConversation(id, pinned: !snapshot.conversations[index].pinned, archived: false); return }
        do {
            let pin = !snapshot.conversations[index].pinned
            snapshot.conversations[index] = try WorkspaceChatOperations.updating(snapshot.conversations[index], pinned: pin, archived: false)
            chatInteractions.pinnedOrder.removeAll { $0 == id }
            if pin { chatInteractions.pinnedOrder.append(id) }
            persistChatState()
        } catch { self.error = error.localizedDescription }
    }

    func setChatArchived(_ id: UUID, archived: Bool) {
        guard !busy, let index = snapshot.conversations.firstIndex(where: { $0.metadata.id == id }) else { return }
        if mode == .live { updateLocalConversation(id, pinned: false, archived: archived); return }
        do {
            snapshot.conversations[index] = try WorkspaceChatOperations.updating(snapshot.conversations[index], pinned: false, archived: archived)
            chatInteractions.pinnedOrder.removeAll { $0 == id }
            if archived { leaveChatIfVisible(id) }
            persistChatState()
        } catch { self.error = error.localizedDescription }
    }

    func deleteChat(_ id: UUID) {
        guard !busy else { return }
        if mode == .live {
            guard liveResponses[id] == nil else { error = "Сначала остановите ответ в этом чате."; return }
            updateLocalConversation(id, deleting: true)
            return
        }
        let wasSelected = selectedConversationID == id
        chatActivity.forgetConversation(id)
        let messages = Set(snapshot.messages.filter { $0.conversationId == id }.map(\.metadata.id))
        chatActivity.forgetReadMessages(messages)
        if wasSelected { selectedConversationID = nil; selectedAgentID = nil }
        snapshot.messages.removeAll { $0.conversationId == id }
        snapshot.conversations.removeAll { $0.metadata.id == id }
        conversationDrafts[id] = nil; failedSends[id] = nil
        chatInteractions.removeMessages(messages)
        chatInteractions.forgetConversation(id)
        #if os(iOS)
        navigation.forgetConversation(id)
        if wasSelected && route == .chat { history = []; selectTab(.chats) }
        #else
        desktopContent.forgetConversation(id)
        if wasSelected && route == .chat { history = []; selectTab(.home) }
        #endif
        pendingChatDeletionID = nil
        persistChatState(immediately: true)
    }

    private func leaveChatIfVisible(_ id: UUID) {
        #if os(iOS)
        navigation.forgetConversation(id)
        #endif
        guard route == .chat, selectedConversationID == id else { return }
        selectedConversationID = nil; selectedAgentID = nil
        history = []
        #if os(iOS)
        selectTab(.chats)
        #else
        selectTab(.home)
        #endif
    }

    var selectedFile: BlotV3.Artifact? {
        snapshot.artifacts.first { $0.metadata.id == selectedRecordID }
    }

    var isReplying: Bool {
        selectedConversationID.map { liveResponses[$0] != nil || chatActivity.isResponding(in: $0) } ?? false
    }

    func stopReply(in id: UUID? = nil) {
        guard let conversationID = id ?? selectedConversationID else { return }
        if liveResponses[conversationID] != nil, let service = commands {
            liveResponses[conversationID]?.cancel()
            _Concurrency.Task {
                do { applyMutationSnapshot(try await service.cancelResponse(in: conversationID)) }
                catch { self.error = "Не удалось сохранить остановку ответа." }
            }
            return
        }
        chatActivity.cancel(in: conversationID)
    }

    private func enqueueLiveResponse(to message: BlotV3.Message) {
        guard let service = commands, liveResponses[message.conversationId] == nil else { return }
        let generation = sessionGeneration
        liveResponses[message.conversationId] = _Concurrency.Task { [weak self] in
            guard let self else { return }
            defer { if self.sessionGeneration == generation { self.liveResponses[message.conversationId] = nil } }
            do {
                for try await response in try await service.responses(to: message) {
                    guard self.sessionGeneration == generation else { return }
                    if let index = self.snapshot.messages.firstIndex(where: { $0.metadata.id == response.metadata.id }) {
                        self.snapshot.messages[index] = response
                    } else { self.snapshot.messages.append(response) }
                }
            } catch {
                guard self.sessionGeneration == generation else { return }
                // Reload the persisted terminal state even if a canceled consumer missed the final yield.
                if let local = self.commands,
                   let saved = try? await local.currentSnapshot() { self.snapshot = saved }
                self.error = "Сообщение сохранено. Ответ не завершён. Проверьте подключение и настройки модели."
            }
        }
    }

    func retryResponse(to messageID: UUID) {
        guard mode == .live, let message = snapshot.messages.first(where: { $0.metadata.id == messageID }),
              message.role == .user, liveResponses[message.conversationId] == nil else { return }
        error = nil
        enqueueLiveResponse(to: message)
    }

    func deliveryTitle(_ delivery: BlotV3.DeliveryState) -> String {
        switch delivery {
        case .saved: t("Saved locally")
        case .waiting_connection: t("Waiting for connection")
        case .delivered: t("Delivered")
        case .accepted: t("Accepted")
        case .running: t("Generating")
        case .completed: t("Completed")
        case .failed: t("Failed")
        case .canceled: t("Canceled")
        case .interrupted: t("Interrupted")
        }
    }

    func retryFailedSend() async {
        guard let id = selectedConversationID, let failed = failedSends[id], !busy else { return }
        let current = form.composer
        form.composer = failed
        await perform(.send)
        if selectedConversationID == id, (!current.draft.isEmpty || !current.attachments.isEmpty),
           current.draft != failed.draft || current.attachments != failed.attachments { form.composer = current }
    }

    var accountDisplayName: String {
        #if os(iOS)
        profileName
        #else
        let name = [form.account.name, form.account.lastName].filter { !$0.isEmpty }.joined(separator: " ")
        return name.isEmpty ? t("You") : name
        #endif
    }

    func isAgentOnline(_ agentID: UUID?, in conversationID: UUID?) -> Bool {
        if let agentID {
            return snapshot.conversations.contains { $0.agentId == agentID && chatActivity.onlineConversationIDs.contains($0.metadata.id) }
        }
        return conversationID.map { chatActivity.onlineConversationIDs.contains($0) } ?? false
    }

    func updateChatVisibility(_ id: UUID?, atLatest: Bool) {
        let visible = route == .chat && settingsRoute == nil ? id : nil
        readingConversationID = visible; readingLatest = visible != nil && atLatest
        if let visible, atLatest { markChatRead(visible) }
    }
    func clearChatVisibility(_ id: UUID?) {
        if readingConversationID == id { readingConversationID = nil; readingLatest = false }
    }
    func markChatRead(_ id: UUID) {
        if mode == .live, let service = commands {
            let messages = WorkspaceMessageOrder.ordered(snapshot.messages.filter { $0.conversationId == id })
            let read = (snapshot.readPositions ?? []).first { $0.conversationId == id && $0.participantId == snapshot.ownerID }
            guard let latest = messages.last, !pendingReadConversations.contains(id),
                  WorkspaceMessageOrder.isAfter(latest, legacyPosition: messages.count, read: read) else { return }
            pendingReadConversations.insert(id)
            _Concurrency.Task {
                defer { pendingReadConversations.remove(id) }
                do { applyMutationSnapshot(try await service.markRead(conversationID: id, messageID: latest.metadata.id)) }
                catch { self.error = "Не удалось сохранить позицию прочтения." }
            }
            return
        }
        guard chatInteractions.unreadCount(in: id) > 0 else { return }
        chatInteractions.markRead(id)
    }

    private func applyMutationSnapshot(_ result: WorkspaceSnapshot) {
        guard commands != nil, let ownerID = snapshot.ownerID, result.ownerID == ownerID, result != snapshot else { return }
        snapshot = result
    }

    private func refreshLocalChatState() {
        guard let ownerID = snapshot.ownerID else { return }
        var interactions = chatInteractions
        interactions.messages = Dictionary(uniqueKeysWithValues: snapshot.messages.map {
            ($0.metadata.id, WorkspaceMessageMetadata(replyToMessageID: $0.replyToMessageId))
        })
        for reaction in (snapshot.reactions ?? []).filter({ $0.participantId == ownerID && !$0.removed }).sorted(by: { $0.metadata.updatedAt < $1.metadata.updatedAt }) {
            interactions.messages[reaction.messageId, default: .init()].reaction = reaction.emoji
            interactions.messages[reaction.messageId, default: .init()].reactedAt = reaction.metadata.updatedAt
        }
        interactions.unreadMessageIDs = [:]
        for conversation in snapshot.conversations {
            let read = (snapshot.readPositions ?? []).first { $0.conversationId == conversation.metadata.id && $0.participantId == ownerID }
            let messages = WorkspaceMessageOrder.ordered(snapshot.messages.filter { $0.conversationId == conversation.metadata.id })
            let unread = Set(messages.enumerated().filter { WorkspaceMessageOrder.isAfter($0.element, legacyPosition: $0.offset + 1, read: read) && $0.element.role == .assistant && $0.element.delivery != .running }.map { $0.element.metadata.id })
            if !unread.isEmpty { interactions.unreadMessageIDs?[conversation.metadata.id] = unread }
        }
        if interactions != chatInteractions { chatInteractions = interactions }
        if let id = readingConversationID, readingLatest { markChatRead(id) }
    }

    func rememberMessage(_ id: UUID) {
        guard mode == .live, let message = snapshot.messages.first(where: { $0.metadata.id == id }) else { return }
        selectedRecordID = nil
        form.memory = WorkspaceMemoryForm(content: message.content, sourceID: id)
        _Concurrency.Task { await perform(.saveMemory) }
    }

    func localFileURL(_ id: UUID) async throws -> URL {
        guard let service = commands else { throw WorkspaceServiceError.unavailable }
        return try await service.fileURL(id)
    }

    func createGroup(title: String, agentIDs: [UUID]) async -> Bool {
        guard !busy, let service = commands else { return false }
        busy = true
        defer { busy = false }
        do {
            applyMutationSnapshot(try await service.createGroup(title: title, agentIDs: agentIDs))
            if let group = snapshot.conversations.last { openConversation(group.metadata.id) }
            return true
        } catch { self.error = "Не удалось создать группу."; return false }
    }

    func searchLocalMessages(_ query: String) async throws -> [BlotV3.Message] {
        guard let service = commands else { throw WorkspaceServiceError.unavailable }
        return try await service.searchMessages(query)
    }

    var unresolvedConflicts: [BlotV3.ConflictingRevision] { (snapshot.conflicts ?? []).filter { !$0.resolved } }

    func resolveConflict(_ selectedID: UUID, displayedIDs: Set<UUID>) async -> Bool {
        guard !busy, let service = commands else { return false }
        busy = true
        defer { busy = false }
        do { applyMutationSnapshot(try await service.resolveConflict(selectedID, displayedIDs: displayedIDs)); return true }
        catch { self.error = "Не удалось согласовать версии. Обновите список и повторите выбор."; return false }
    }



    func enqueueDueSchedules() async {
        guard mode == .live, let service = commands else { return }
        do { applyMutationSnapshot(try await service.enqueueDueSchedules()) }
        catch { self.error = "Не удалось проверить запуски расписаний." }
    }

    func runScheduleManually(_ id: UUID) {
        guard !busy, let service = commands else { return }
        busy = true
        _Concurrency.Task {
            defer { busy = false }
            do {
                applyMutationSnapshot(try await service.runScheduleManually(id))
                notice = "Задача поставлена в очередь на выбранном устройстве."
            } catch { self.error = "Не удалось запустить расписание." }
        }
    }

    func localFileText(_ id: UUID) async throws -> String {
        guard let service = commands else { throw WorkspaceServiceError.unavailable }
        return try await service.fileText(id)
    }

    func exportMessage(_ id: UUID, format: WorkspaceExportFormat) {
        guard !busy, mode == .live, let service = commands,
              let message = snapshot.messages.first(where: { $0.metadata.id == id }) else { return }
        busy = true
        _Concurrency.Task {
            defer { busy = false }
            do {
                applyMutationSnapshot(try await service.export(message, format: format))
                selectedRecordID = snapshot.artifacts.last?.metadata.id
                navigate(.file)
            } catch { self.error = "Не удалось создать файл." }
        }
    }

    func deleteMemory(_ id: UUID) {
        guard mode == .live, let service = commands,
              let memory = snapshot.memories.first(where: { $0.metadata.id == id }) else { return }
        _Concurrency.Task {
            do { applyMutationSnapshot(try await service.deleteMemory(memory)) }
            catch { self.error = "Не удалось удалить память." }
        }
    }
    func markChatUnread(_ id: UUID) {
        leaveChatIfVisible(id)
        chatInteractions.markUnread(id)
    }
    func toggleChatMute(_ id: UUID) { chatInteractions.toggleMute(id) }

    func editChatAgent(_ agentID: UUID) {
        #if os(iOS)
        selectedAgentID = agentID
        if let agent = snapshot.agents.first(where: { $0.metadata.id == agentID }) {
            form.agent = WorkspaceAgentForm(name: agent.name, instructions: agent.instructions, shape: agent.avatarShape, color: agent.avatarColor)
            agentAppearanceVisible = true
        }
        #else
        selectAgent(agentID, destination: .editAgent)
        #endif
    }

    func beginChatRename(_ id: UUID) {
        guard let chat = snapshot.conversations.first(where: { $0.metadata.id == id }) else { return }
        chatTitleDraft = chat.title; pendingChatRenameID = id
    }
    func renameChat(_ id: UUID) {
        let title = chatTitleDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty, let index = snapshot.conversations.firstIndex(where: { $0.metadata.id == id }) else { return }
        if mode == .live { updateLocalConversation(id, title: title); return }
        do {
            snapshot.conversations[index] = try WorkspaceChatOperations.updating(snapshot.conversations[index], title: title)
            pendingChatRenameID = nil
            persistChatState()
        } catch { self.error = error.localizedDescription }
    }

    private func updateLocalConversation(_ id: UUID, title: String? = nil, pinned: Bool? = nil,
                                         archived: Bool? = nil, deleting: Bool = false) {
        guard !busy, let service = commands,
              let chat = snapshot.conversations.first(where: { $0.metadata.id == id }) else { return }
        busy = true
        _Concurrency.Task {
            defer { busy = false }
            do {
                applyMutationSnapshot(try await service.updateConversation(chat, title: title, pinned: pinned, archived: archived, deleting: deleting))
                pendingChatRenameID = nil; pendingChatDeletionID = nil
                if deleting || archived == true { leaveChatIfVisible(id) }
            } catch { self.error = "Изменение не сохранено. Обновите чат и повторите действие." }
        }
    }
    func newChat(with agentID: UUID?) async {
        #if os(iOS)
        await startNewChat(with: agentID)
        #else
        guard !busy else { return }
        selectedAgentID = agentID
        await perform(.createConversation)
        if error == nil { selectTab(.chat) }
        #endif
    }

    func signOut() {
        guard !busy else { return }
        busy = true
        sessionGeneration = UUID()
        observation?.cancel(); observation = nil
        let workers = Array(liveResponses.values)
        for worker in workers { worker.cancel() }
        liveResponses = [:]
        chatActivity.cancelAll()
        snapshot = WorkspaceSnapshot(); selectedConversationID = nil; selectedAgentID = nil; selectedRecordID = nil
        conversationDrafts = [:]; failedSends = [:]; pendingSendCommands = [:]
        pendingChatDeletionID = nil; pendingChatRenameID = nil
        chatInteractions = WorkspaceChatInteractions(); settingsRoute = nil
        form = WorkspaceForm()
        #if os(iOS)
        notifications.clear(); authenticationRoute = nil; navigation.reset()
        profile = PhoneProfileRecord()
        #else
        desktopContent.reset()
        #endif
        selectTab(.welcome)
        _Concurrency.Task {
            defer { busy = false }
            for worker in workers { await worker.value }
            do { try await (service as? any WorkspaceAccountService)?.signOut() }
            catch { self.error = WorkspaceFailureCopy.message(error) }
        }
    }

    func persistChatState(immediately: Bool = false) {
        guard mode == .live, snapshot.ownerID != nil else { return }
        guard !restoringPresentation, let commands else { return }
        var drafts = conversationDrafts
        if let id = selectedConversationID { drafts[id] = form.composer }
        let state = WorkspacePresentationState(drafts: drafts, interactions: chatInteractions, personalization: form.personalization,
            firstName: form.account.name, lastName: form.account.lastName, email: form.account.email)
        guard let data = try? JSONEncoder().encode(state) else { return }
        _Concurrency.Task { try? await commands.savePresentationState(data) }
    }

    private func touchConversation(_ id: UUID) {
        guard let index = snapshot.conversations.firstIndex(where: { $0.metadata.id == id }) else { return }
        do {
            let conversation = snapshot.conversations[index]
            let old = conversation.metadata
            let metadata = try BlotV3.RecordMetadata(id: old.id, ownerId: old.ownerId, workspaceId: old.workspaceId,
                version: old.version + 1, createdAt: old.createdAt, updatedAt: Date())
            let userMessages = snapshot.messages.filter { $0.conversationId == id && $0.role == .user }
            let agentName = snapshot.agents.first { $0.metadata.id == conversation.agentId }?.name
            let isDefaultTitle = conversation.title == agentName || ["Chat with AI", t("Chat with AI")].contains(conversation.title)
            let firstLine = userMessages.first?.content.components(separatedBy: .newlines).first ?? conversation.title
            let title = userMessages.count == 1 && isDefaultTitle ? String(firstLine.prefix(60)) : conversation.title
            snapshot.conversations[index] = try .init(metadata: metadata, agentId: conversation.agentId,
                title: title, mobileOwned: conversation.mobileOwned, pinned: conversation.pinned, archived: conversation.archived)
        } catch { self.error = error.localizedDescription }
    }


    #if os(iOS)
    func dismissAuthentication() {
        authenticationRoute = nil
        error = nil
        if route.isAuthentication && route != .welcome { selectTab(.welcome) }
    }
    func beginAgentCreation() {
        error = nil; invalidField = nil; notice = nil
        form.agent = WorkspaceAgentForm(shape: "cloud", color: "orange")
        agentCreationVisible = true
    }
    func createAgentAndStartChat() async {
        let previousCount = snapshot.agents.count
        await perform(.createAgent)
        guard error == nil, snapshot.agents.count > previousCount, let id = selectedAgentID else { return }
        agentCreationVisible = false
        preferredAgentID = id
        selectTab(.chats)
        await startNewChat(with: id)
    }
    var profileName: String {
        let nickname = profile.nickname.trimmingCharacters(in: .whitespacesAndNewlines)
        if !nickname.isEmpty { return nickname }
        let name = [form.account.name, form.account.lastName].filter { !$0.isEmpty }.joined(separator: " ")
        return name.isEmpty ? t("Your profile") : name
    }

    func startNewChat() async {
        if prefersGeneralChat { await startNewChat(with: nil); return }
        let id = preferredAgentID.flatMap { preferred in snapshot.agents.first { $0.metadata.id == preferred }?.metadata.id }
        await startNewChat(with: id ?? snapshot.agents.first?.metadata.id)
    }

    func startNewChat(with agentID: UUID?) async {
        guard !busy else { return }
        selectedAgentID = agentID
        preferredAgentID = agentID
        prefersGeneralChat = agentID == nil
        await perform(.createConversation)
        guard error == nil else { return }
        if route != .chat { navigate(.chat) }
        persistWorkspace()
    }

    func chooseChatAgent(_ agentID: UUID?) async {
        guard !busy else { return }
        if currentMessages.isEmpty, let index = snapshot.conversations.firstIndex(where: { $0.metadata.id == selectedConversationID }) {
            do {
                let conversation = snapshot.conversations[index]
                snapshot.conversations[index] = try .init(metadata: conversation.metadata, agentId: agentID,
                    title: snapshot.agents.first { $0.metadata.id == agentID }?.name ?? t("Chat with AI"),
                    mobileOwned: agentID == nil, pinned: conversation.pinned, archived: conversation.archived)
                selectedAgentID = agentID; preferredAgentID = agentID
                prefersGeneralChat = agentID == nil
                agentPickerVisible = false
                persistWorkspace()
            } catch { self.error = error.localizedDescription }
        } else {
            await startNewChat(with: agentID)
            if error == nil { agentPickerVisible = false }
        }
    }

    func prepareSchedule() {
        guard route != .createSchedule else { return }
        form.schedule = WorkspaceScheduleForm()
        form.schedule.agentID = currentConversation?.agentId ?? selectedAgentID
        form.schedule.deviceID = snapshot.devices.first { $0.kind == .desktop }?.metadata.id
        form.schedule.goal = currentMessages.last { $0.role == .user }?.content ?? ""
        form.schedule.name = currentConversation?.title ?? ""
    }

    func saveSchedule() async {
        let count = snapshot.schedules.count
        await perform(.createSchedule)
        guard error == nil, snapshot.schedules.count > count else { return }
        if history.last == .createSchedule { _ = history.popLast() }
        if history.last != .schedules && rootRoute != .schedules { history.append(.schedules) }
        route = .schedules
    }

    func deleteLocalAccount() {
        error = "Удаление аккаунта пока недоступно. Локальная история сохранена."
    }

    func persistWorkspace(immediately: Bool = false) { persistChatState(immediately: immediately) }
    #endif
    private func validate(_ action: WorkspaceAction) -> Bool {
        func fail(_ text: String, field: String) -> Bool { invalidField = field; error = t(text); return false }
        switch action {
        case .signIn, .register, .recover, .resetPassword:
            let parts = form.account.email.split(separator: "@")
            guard parts.count == 2, parts[1].contains("."), !form.account.email.contains(" ") else { return fail("Enter a valid email address.", field: "Email") }
            if action != .recover && form.account.password.count < 8 { return fail("Use at least 8 characters for your password.", field: "Password") }
            if action == .register && form.account.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return fail("Enter your name.", field: "Your name") }
            if action == .resetPassword && (form.account.code.count != 6 || !form.account.code.allSatisfy(\.isNumber)) {
                return fail("Enter the 6-digit code.", field: "Verification code")
            }
        case .verify:
            guard form.account.code.count == 6, form.account.code.allSatisfy(\.isNumber) else { return fail("Enter the 6-digit code.", field: "Verification code") }
        case .createAgent, .saveAgent:
            guard !form.agent.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  !form.agent.instructions.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return fail("Enter a name and instructions.", field: "Name") }
        case .createSchedule:
            guard !form.schedule.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  !form.schedule.goal.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return fail("Enter a name and a task.", field: "Name") }
        case .saveModelKey:
            guard !form.model.secret.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return fail("Enter an API key.", field: "API key") }
        case .addMcp:
            guard !form.mcp.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return fail("Enter a server name.", field: "Server name") }
            if form.mcp.transport == "STREAMABLE_HTTP" {
                guard let url = URL(string: form.mcp.endpoint), ["https", "http"].contains(url.scheme), url.host != nil else { return fail("Enter a valid server URL.", field: "Server URL") }
            }
        case .saveMemory:
            guard !form.memory.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return fail("Enter memory text.", field: "Memory text") }
        case .send:
            guard !form.composer.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !form.composer.attachments.isEmpty else { return fail("Write a message first.", field: "Message") }
        default: break
        }
        return true
    }
}
