import AppKit
import BlotAppleIntegrations
import BlotDesign
import BlotDomain
import BlotWorkspace
import SwiftUI

@MainActor
enum VerifyMacChatInterface {
    static func render(to directory: URL) async throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let base = WorkspaceStore(mode: .preview, route: .chat)
        guard let chat = base.snapshot.conversations.first, let agent = base.snapshot.agents.first else { throw CocoaError(.coderInvalidValue) }
        var snapshot = base.snapshot
        snapshot.messages = []; snapshot.cards = []; snapshot.tasks = []; snapshot.preparedActions = []
        snapshot.ownerID = chat.metadata.ownerId; snapshot.localDeviceID = ConversationCardSamples.device
        func metadata(_ id: UUID, _ offset: TimeInterval = 0) throws -> BlotV3.RecordMetadata {
            let date = Date(timeIntervalSince1970: 1_794_909_600).addingTimeInterval(offset)
            return try .init(id: id, ownerId: chat.metadata.ownerId, workspaceId: chat.metadata.workspaceId, version: 1, createdAt: date, updatedAt: date)
        }
        let user = try BlotV3.Message(metadata: metadata(UUID()), conversationId: chat.metadata.id, role: .user,
            content: "What are the main takeaways from today’s design sync?", delivery: .completed, commandId: UUID(), artifactIds: [])
        let assistant = try BlotV3.Message(metadata: metadata(UUID(), 20), conversationId: chat.metadata.id, role: .assistant,
            content: "The team reviewed the onboarding flow and agreed on three changes.\n\nI’ll update the screens, check the narrow layout, and share the results with @" + agent.name + ".",
            delivery: .completed, commandId: user.commandId, artifactIds: [], authorAgentId: agent.metadata.id, replyToMessageId: user.metadata.id)
        let explicit = try BlotV3.Message(metadata: metadata(UUID(), 40), conversationId: chat.metadata.id, role: .user,
            content: "Please start with the first one.", delivery: .completed, commandId: UUID(), artifactIds: [], replyToMessageId: assistant.metadata.id)
        precondition(MacChatMessageContext.quoteID(assistant) == nil, "Technical reply linkage must not render as a quote")
        precondition(MacChatMessageContext.quoteID(explicit) == assistant.metadata.id, "An explicit user Reply must retain its target")
        precondition(!MacChatMessageContext.startsDate(assistant, after: user))
        precondition(MacChatMessageContext.startsDate(user, after: nil))
        let states: [(BlotV3.TaskState?, Bool, Bool, MacChatAgentActivity)] = [
            (nil, false, false, .idle), (.running, false, false, .working), (.waiting_user, false, false, .waiting),
            (.failed, false, false, .blocked), (.planning, false, false, .thinking), (.completed, false, false, .done),
            (.running, true, true, .waiting), (nil, false, true, .thinking)]
        for value in states { precondition(MacChatAgentActivity.resolve(task: value.0, needsInput: value.1, generating: value.2) == value.3) }
        snapshot.messages = [user, assistant, explicit]
        verifyPanelSizing()
        try verifyMessageColors(agent: agent)
        var manifest: [[String: String]] = []
        let sizes: [(String, CGFloat, CGFloat)] = [("wide", 1180, 760), ("compact", 960, 640), ("narrow", 760, 640)]
        for size in sizes {
            for dark in [false, true] {
                try await frame(snapshot: snapshot, chat: chat, agent: agent, dark: dark, width: size.1, height: size.2,
                    filename: "chat-" + size.0 + (dark ? "-dark.png" : "-light.png"), directory: directory, manifest: &manifest)
            }
        }
        if snapshot.agents.count >= 3 {
            let designer = snapshot.agents[1], researcher = snapshot.agents[2]
            let group = try BlotV3.Conversation(metadata: metadata(UUID()), agentId: agent.metadata.id, title: "Design review", mobileOwned: false, pinned: false, archived: false, kind: .group)
            var grouped = snapshot
            grouped.conversations.append(group)
            grouped.participants = try [designer, researcher].map {
                try .init(metadata: metadata(UUID()), conversationId: group.metadata.id, participantId: $0.metadata.id, kind: .agent, removed: false)
            }
            let request = try BlotV3.Message(metadata: metadata(UUID()), conversationId: group.metadata.id, role: .user,
                content: "Please review the onboarding screens together.", delivery: .completed, commandId: UUID(), artifactIds: [])
            let first = try BlotV3.Message(metadata: metadata(UUID(), 20), conversationId: group.metadata.id, role: .assistant,
                content: "@" + researcher.name + ", can you check the source material? I’ll update the layout.", delivery: .completed,
                commandId: request.commandId, artifactIds: [], authorAgentId: designer.metadata.id, replyToMessageId: request.metadata.id)
            let second = try BlotV3.Message(metadata: metadata(UUID(), 40), conversationId: group.metadata.id, role: .assistant,
                content: "On it, @" + designer.name + ". I’ll compare the current screens and report any differences.", delivery: .completed,
                commandId: request.commandId, artifactIds: [], authorAgentId: researcher.metadata.id, replyToMessageId: request.metadata.id)
            grouped.messages = [request, first, second]
            for dark in [false, true] {
                try await frame(snapshot: grouped, chat: group, agent: agent, dark: dark, width: 1180, height: 760,
                    filename: "chat-group" + (dark ? "-dark.png" : "-light.png"), directory: directory, manifest: &manifest)
            }
        }
        for (index, sample) in try ConversationCardSamples.samples().enumerated() {
            var sampleSnapshot = snapshot
            let original = try ConversationCardSamples.card(sample, index: index)
            let message = try BlotV3.Message(metadata: metadata(original.messageId, 30), conversationId: chat.metadata.id, role: .assistant,
                content: sample.content.fallback, delivery: .completed, commandId: original.operationId, artifactIds: [], authorAgentId: agent.metadata.id)
            sampleSnapshot.messages = [user, message]
            sampleSnapshot.cards = [original]
            for dark in [false, true] {
                try await frame(snapshot: sampleSnapshot, chat: chat, agent: agent, dark: dark, width: 1180, height: 760,
                    filename: sample.reference + (dark ? "-shell-dark.png" : "-shell-light.png"), directory: directory, manifest: &manifest)
            }
        }
        var continued = snapshot
        let followup = try BlotV3.Message(metadata: metadata(UUID(), 25), conversationId: chat.metadata.id, role: .assistant,
            content: "The changes are ready. I’ll continue with the remaining screens.", delivery: .completed,
            commandId: user.commandId, artifactIds: [], authorAgentId: agent.metadata.id, replyToMessageId: user.metadata.id)
        continued.messages = [user, assistant, followup]
        precondition(WorkspaceMessageSeries.authorIDs(in: continued.messages) == [assistant.metadata.id], "Consecutive messages keep only the first avatar")
        try await frame(snapshot: continued, chat: chat, agent: agent, dark: false, width: 1180, height: 760,
            filename: "chat-series-light.png", directory: directory, manifest: &manifest)
        for color in ["orange", "purple", "teal", "#FFFFFF"] {
            var colored = snapshot
            let profile = try copy(agent, color: color)
            colored.agents = colored.agents.map { $0.metadata.id == profile.metadata.id ? profile : $0 }
            try await frame(snapshot: colored, chat: chat, agent: profile, dark: false, width: 1180, height: 760,
                filename: "chat-accent-" + color.replacingOccurrences(of: "#", with: "hex-") + ".png", directory: directory, manifest: &manifest)
        }
        for widths in [(240.0, 400.0), (380.0, 500.0)] {
            try await frame(snapshot: snapshot, chat: chat, agent: agent, dark: false, width: 1440, height: 760,
                filename: "chat-panels-" + String(Int(widths.0)) + "-" + String(Int(widths.1)) + ".png", directory: directory,
                manifest: &manifest, panelWidths: widths)
        }
        try await frame(snapshot: snapshot, chat: chat, agent: agent, dark: false, width: 1180, height: 760,
            filename: "chat-thinking-light.png", directory: directory, manifest: &manifest, thinking: true)
        try JSONSerialization.data(withJSONObject: manifest, options: [.prettyPrinted, .sortedKeys]).write(to: directory.appendingPathComponent("manifest.json"))
        print("PASS: native chat, computer-panel toggle and resizing; \(manifest.count) complete native chat frames.")
    }
    private static func frame(snapshot: WorkspaceSnapshot, chat: BlotV3.Conversation, agent: BlotV3.AgentProfile,
                              dark: Bool, width: CGFloat, height: CGFloat, filename: String, directory: URL, manifest: inout [[String: String]],
                              panelWidths: (Double, Double)? = nil, thinking: Bool = false) async throws {
        let store = WorkspaceStore(mode: .preview, route: .chat, previewSnapshot: snapshot)
        store.language = "en"; store.selectedConversationID = chat.metadata.id; store.selectedAgentID = agent.metadata.id
        let suite = "Blot.GrokGlass.Validation"
        guard let defaults = UserDefaults(suiteName: suite) else { throw CocoaError(.coderInvalidValue) }
        defaults.removePersistentDomain(forName: suite)
        defer { defaults.removePersistentDomain(forName: suite); store.chatActivity.cancelAll() }
        if let widths = panelWidths {
            defaults.set(widths.0, forKey: MacTeamPreferenceKey.sidebarWidth)
            defaults.set(widths.1, forKey: MacBrowserSplitLayout.widthPreferenceKey)
            precondition(defaults.double(forKey: MacTeamPreferenceKey.sidebarWidth) == widths.0)
            precondition(defaults.double(forKey: MacBrowserSplitLayout.widthPreferenceKey) == widths.1)
        }
        if thinking, let message = snapshot.messages.last(where: { $0.role == .user }) {
            store.chatActivity.enqueue(message: message, replies: ["Verification response"], onRead: {}, complete: { _, _ in })
            try await _Concurrency.Task.sleep(for: .milliseconds(1400))
        }
        let root = MacLiveTeamWorkspace().environment(store).blotTheme(dark ? .dark : .light)
            .defaultAppStorage(defaults)
            .environment(\.colorScheme, dark ? .dark : .light)
            .kMotionRoot(reduceMotion: !thinking && panelWidths == nil)
            .environment(\.scenePhase, .active)
        let host = NSHostingView(rootView: root)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: width, height: height), styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; window.contentView = host; host.frame = NSRect(x: 0, y: 0, width: width, height: height)
        window.orderFrontRegardless()
        try await _Concurrency.Task.sleep(for: .milliseconds(180))
        if let widths = panelWidths {
            if widths.0 == 240 {
                try await drag(window, from: CGPoint(x: widths.0, y: 380), to: CGPoint(x: widths.0 + 64, y: 380))
                let sidebar = defaults.double(forKey: MacTeamPreferenceKey.sidebarWidth)
                precondition(abs(sidebar - widths.0 - 64) < 2, "Dragging the chat-list divider must update its stored width")
            }
            try await click(window, at: CGPoint(x: width - 33, y: height - 28))
            try await _Concurrency.Task.sleep(for: .milliseconds(450))
            precondition(store.browser?.presented == true && store.browser?.selectedTab != nil, "The computer button must open the tools and browser panel")
            if widths.0 == 240 {
                let border = width - widths.1 - MacBrowserSplitLayout.dividerWidth / 2
                try await drag(window, from: CGPoint(x: border, y: 380), to: CGPoint(x: border - 64, y: 380))
                let browser = defaults.double(forKey: MacBrowserSplitLayout.widthPreferenceKey)
                precondition(abs(browser - widths.1 - 64) < 2, "Dragging the browser divider must update its stored width")
            }
        }
        host.layoutSubtreeIfNeeded(); host.displayIfNeeded()
        try VerifyConversationCardUI.capture(window, to: directory.appendingPathComponent(filename))
        manifest.append(["file": filename, "width": String(Int(width)), "height": String(Int(height)), "theme": dark ? "dark" : "light"])
        if panelWidths != nil {
            try await click(window, at: CGPoint(x: width - 400, y: height - 220))
            precondition(store.browser?.selectedTab?.localPage == "page:files", "Files must open inside the computer panel")
            let tab = store.browser?.selectedID
            try await click(window, at: CGPoint(x: width - 33, y: height - 28))
            try await _Concurrency.Task.sleep(for: .milliseconds(450))
            precondition(store.browser?.presented == false && store.browser?.selectedID == tab, "The corner button must close the panel and retain its active tab")
        }
        window.contentView = nil; window.close()
    }
    private static func click(_ window: NSWindow, at point: CGPoint) async throws {
        try await sendMouseEvents([(.leftMouseDown, point), (.leftMouseUp, point)], to: window)
    }

    private static func drag(_ window: NSWindow, from start: CGPoint, to end: CGPoint) async throws {
        try await sendMouseEvents([(.leftMouseDown, start),
            (.leftMouseDragged, CGPoint(x: start.x + (end.x - start.x) / 2, y: start.y)),
            (.leftMouseDragged, end), (.leftMouseUp, end)], to: window)
    }

    private static func sendMouseEvents(_ events: [(NSEvent.EventType, CGPoint)], to window: NSWindow) async throws {
        // Deliver events only to this isolated test window.
        for (index, item) in events.enumerated() {
            guard let event = NSEvent.mouseEvent(with: item.0, location: item.1, modifierFlags: [],
                timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
                context: nil, eventNumber: index, clickCount: 1, pressure: item.0 == .leftMouseUp ? 0 : 1) else { throw CocoaError(.coderInvalidValue) }
            window.sendEvent(event)
            try await _Concurrency.Task.sleep(for: .milliseconds(50))
        }
    }

    private static func copy(_ agent: BlotV3.AgentProfile, color: String) throws -> BlotV3.AgentProfile {
        try .init(metadata: agent.metadata, name: agent.name, roleId: agent.roleId, avatarShape: agent.avatarShape,
            avatarColor: color, instructions: agent.instructions, modelId: agent.modelId, accessMode: agent.accessMode)
    }

    private static func verifyMessageColors(agent: BlotV3.AgentProfile) throws {
        for scheme in [ColorScheme.light, .dark] {
            var environment = EnvironmentValues(); environment.colorScheme = scheme
            for key in ["white", "brown", "red", "blue", "pink", "orange", "green", "amber", "gray", "purple", "teal", "black", "#FFFFFF", "#18F5C3"] {
                let profile = try copy(agent, color: key)
                let color = WorkspaceChatStyle.outgoing(agent: profile, group: false, environment: environment).resolve(in: environment)
                func linear(_ component: Float) -> Double {
                    let value = Double(component)
                    return value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
                }
                let luminance = 0.2126 * linear(color.red) + 0.7152 * linear(color.green) + 0.0722 * linear(color.blue)
                precondition(1.05 / (luminance + 0.05) >= 4.49, "White message text must remain readable: " + key)
                let group = WorkspaceChatStyle.outgoing(agent: profile, group: true, environment: environment).resolve(in: environment)
                precondition(group.red < 0.1 && group.green < 0.1 && group.blue < 0.1, "Group messages retain the neutral accent")
            }
        }
    }

    private static func verifyPanelSizing() {
        let left = MacWorkspacePanelResize(bounds: 220...480)
        precondition(left.width(initial: 300, translation: 80) == 380)
        precondition(left.width(initial: 300, translation: -1000) == 220)
        let narrow = MacWorkspaceLayout(size: CGSize(width: 900, height: 640), preferredSidebarWidth: 480)
        precondition(narrow.sidebarWidth + MacWorkspaceLayout.minimumConversationWidth < 900)
        let narrowSplit = MacBrowserSplitLayout(width: 899 - narrow.sidebarBounds(computerVisible: true).upperBound)
        precondition(narrowSplit.browserWidth(500) >= MacBrowserSplitLayout.minimumBrowserWidth)
        let browser = MacBrowserSplitLayout(width: 760)
        precondition(browser.browserWidth(200) == 300 && browser.browserWidth(500) == 416)
    }

}
