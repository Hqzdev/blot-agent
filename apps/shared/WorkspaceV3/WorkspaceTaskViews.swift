import BlotDesign
import BlotDomain
import SwiftUI

struct WorkspaceTaskView: View {
    let route: WorkspaceRoute
    @Environment(WorkspaceStore.self) private var store
    var body: some View {
        switch route {
        case .home: home
        case .chats: chats
        case .search: search
        case .newChat: newChat
        case .running: running
        case .approval: approval
        case .result: result
        case .file: document
        case .review: review
        case .blocked: blocked
        case .offline: offline
        case .browser: browser
        default: conversation
        }
    }
    private var home: some View {
        VStack(spacing: 30) {
            Spacer(minLength: 30)
            WorkspaceAvatar(size: 100)
            Text(store.t("What are we doing today?")).font(.system(size: 34)).multilineTextAlignment(.center)
            Text(store.t("Give Blot a task — it assembles the team and delivers the result."))
                .foregroundStyle(WorkspaceStyle.secondary).multilineTextAlignment(.center)
            WorkspaceComposer().padding(.top, 10)
            Text(store.t("Ask first · Access to Blot Workspace folder")).font(.caption).foregroundStyle(WorkspaceStyle.secondary)
            HStack(alignment: .top, spacing: 16) {
                suggestion("Research", detail: "Compare services and summarize", symbol: "magnifyingglass")
                suggestion("Create", detail: "Draft a mockup or document", symbol: "rectangle.split.2x1")
                suggestion("Build", detail: "Change the project and check the code", symbol: "chevron.left.forwardslash.chevron.right")
            }.padding(.top, 12)
            WorkspaceFeedback()
            Spacer(minLength: 50)
        }.frame(maxWidth: 820).frame(maxWidth: .infinity)
    }
    private func suggestion(_ title: String, detail: String, symbol: String) -> some View {
        Button { store.form.composer.draft = store.t(detail) } label: {
            VStack(alignment: .leading, spacing: 12) {
                BlotIcon(symbol: symbol).font(.title2)
                Text(store.t(title)).font(.headline)
                Text(store.t(detail)).foregroundStyle(WorkspaceStyle.secondary).fixedSize(horizontal: false, vertical: true)
            }.frame(maxWidth: .infinity, minHeight: 100, alignment: .topLeading).padding(18)
                .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(BlotColor.edge))
        }.buttonStyle(WorkspaceRowButtonStyle())
    }
    private var chats: some View {
        VStack(spacing: 28) {
            if store.snapshot.conversations.isEmpty { WorkspaceDataState(state: .empty) }
            ForEach(Array(store.snapshot.conversations.enumerated()), id: \.element.metadata.id) { index, chat in
                Button { store.openConversation(chat.metadata.id) } label: {
                    HStack(alignment: .top, spacing: 16) {
                        if index < store.snapshot.agents.count { WorkspaceAvatarView(agent: store.snapshot.agents[index], size: 48) }
                        VStack(alignment: .leading, spacing: 8) {
                            Text(chat.title).font(.title3.weight(.medium))
                            Text(store.t(["Plan ready. Needs your approval.", "Three hero screen options ready", "Found 8 services. Comparison in file.", "Weekly menu and shopping list ready", "Checks passed. 6 files changed."][min(index, 4)]))
                                .foregroundStyle(WorkspaceStyle.secondary).lineLimit(2)
                        }
                        Spacer(minLength: 4)
                        Text(index < 2 ? "9:38" : store.t("Yesterday")).font(.caption).foregroundStyle(WorkspaceStyle.secondary).fixedSize()
                    }.frame(minHeight: 70).contentShape(Rectangle())
                }.buttonStyle(WorkspaceRowButtonStyle())
            }
        }
    }
    private var search: some View {
        @Bindable var store = store
        return VStack(alignment: .leading, spacing: 22) {
            HStack { BlotIcon(symbol: "magnifyingglass"); TextField(store.t("Search chats, files and agents"), text: $store.form.search.query).textFieldStyle(.plain) }
                .padding(14)
                #if os(iOS)
                .workspaceInputSurface(cornerRadius: 28)
                #else
                .background(WorkspaceStyle.surface, in: Capsule())
                #endif
            HStack { ForEach(["All", "Chats", "Files", "Agents"], id: \.self) { filter in
                Button(store.t(filter)) { store.notice = filter }.buttonStyle(WorkspaceButtonStyle(.secondary))
            } }
            ForEach(store.snapshot.conversations.filter { store.form.search.query.isEmpty || $0.title.localizedCaseInsensitiveContains(store.form.search.query) }, id: \.metadata.id) { c in
                WorkspaceLink(title: c.title, route: .chat, symbol: "bubble.left.and.bubble.right")
            }
            ForEach(store.snapshot.agents.filter { store.form.search.query.isEmpty || $0.name.localizedCaseInsensitiveContains(store.form.search.query) }, id: \.metadata.id) { a in
                Button { store.selectAgent(a.metadata.id) } label: { HStack { WorkspaceAvatarView(agent: a, size: 32); Text(a.name); Spacer() } }.buttonStyle(WorkspaceRowButtonStyle())
            }
            ForEach(store.snapshot.artifacts.filter { store.form.search.query.isEmpty || $0.name.localizedCaseInsensitiveContains(store.form.search.query) }, id: \.metadata.id) { a in WorkspaceLink(title: a.name, route: .file, symbol: "doc") }
        }
    }
    private var newChat: some View {
        VStack(alignment: .leading, spacing: 25) {
            WorkspaceHeading(title: "What are we doing?", subtitle: "Pick who to talk to. You can add the team at any time.")
            ForEach(store.snapshot.agents.prefix(4), id: \.metadata.id) { agent in
                Button { _Concurrency.Task { await store.openAgentChat(agent.metadata.id) } } label: {
                    HStack(spacing: 16) {
                        WorkspaceAvatarView(agent: agent)
                        VStack(alignment: .leading, spacing: 8) { Text(agent.name).font(.headline); Text(store.t(agent.instructions)).font(.callout).foregroundStyle(WorkspaceStyle.secondary) }
                        Spacer(); BlotIcon(symbol: "chevron.right")
                    }.frame(minHeight: 64).contentShape(Rectangle())
                }.buttonStyle(WorkspaceRowButtonStyle())
            }
            WorkspaceCard { Button(store.t("Just chat with AI")) { _Concurrency.Task { await store.openAgentChat(nil) } }.buttonStyle(WorkspaceRowButtonStyle())
                Text(store.t("No computer or tools. GigaChat · model can be changed")).font(.caption).foregroundStyle(WorkspaceStyle.secondary) }
        }
    }
    private var conversation: some View {
        VStack(alignment: .leading, spacing: 24) {
            ForEach(store.currentMessages, id: \.metadata.id) { message in
                HStack {
                    if message.role == .user { Spacer(minLength: 32) }
                    Text(store.t(message.content)).padding(message.role == .user ? 20 : 0)
                        .background(message.role == .user ? WorkspaceStyle.surface : .clear, in: RoundedRectangle(cornerRadius: 24))
                        .textSelection(.enabled)
                    if message.role != .user { Spacer(minLength: 16) }
                }
            }
            if store.isPreview && !store.currentMessages.isEmpty { WorkspaceTaskPlan() }
            else if store.currentMessages.isEmpty { WorkspaceDataState(state: .empty) }
            Spacer(minLength: 24)
            WorkspaceFeedback()
            #if os(macOS)
            WorkspaceComposer()
            #endif
        }.frame(maxWidth: 780).frame(maxWidth: .infinity)
    }
    private var running: some View {
        #if os(macOS)
        HStack(alignment: .top, spacing: 28) {
            runningOverview
            WorkspaceCard { Text(store.t("Plan")).font(.title2); steps; Spacer(minLength: 100); Text(store.t("Blot Workspace · This computer")).font(.caption).foregroundStyle(WorkspaceStyle.secondary) }.frame(width: 260)
        }
        #else
        runningOverview
        #endif
    }
    private var runningOverview: some View {
        VStack(alignment: .leading, spacing: 26) {
            #if os(macOS)
            WorkspaceHeading(title: "Team at work", subtitle: "Sources are being checked and merged into one report.")
            #endif
            VStack(alignment: .leading, spacing: 18) {
                BlotLabel(store.t(store.taskPaused ? "Paused" : "Comparing services"), symbol: store.taskPaused ? "pause" : "arrow.clockwise").font(.title3)
                Text(store.t("6 of 8 checked · about 2 min")).font(.caption).opacity(0.7)
                ProgressView(value: 0.75).tint(BlotColor.onInverse)
            }.padding(24).frame(maxWidth: .infinity, alignment: .leading).foregroundStyle(BlotColor.onInverse)
                .background(BlotColor.inverse, in: RoundedRectangle(cornerRadius: 20))
            Text(store.t("TEAM AT WORK")).font(.caption.monospaced()).foregroundStyle(WorkspaceStyle.secondary)
            ForEach(store.snapshot.agents.prefix(3), id: \.metadata.id) { agent in
                HStack(spacing: 16) { WorkspaceAvatarView(agent: agent, size: 38); VStack(alignment: .leading, spacing: 5) { Text(agent.name); Text(store.t(agent.instructions)).font(.caption).foregroundStyle(WorkspaceStyle.secondary) }; Spacer(); Text(store.t("Working")).font(.caption) }
            }
            #if os(iOS)
            WorkspaceCard { Text(store.t("Progress")).font(.title2); steps }
            #else
            WorkspaceCard { Text(store.t("Recent activity")).font(.caption.monospaced())
                Text("09:38 · " + store.t("Pricing and limits collected"))
                Text("09:37 · " + store.t("Checking integrations")) }
            #endif
            HStack { WorkspaceV3ActionButton(title: store.taskPaused ? "Resume" : "Pause", action: .pause, kind: .secondary)
                WorkspaceV3ActionButton(title: "Stop task", action: .stop, next: .chat, kind: .destructive) }
            if store.isPreview { WorkspaceLink(title: "Review prepared action", route: .approval); WorkspaceLink(title: "View browser", route: .browser) }
            WorkspaceFeedback()
            #if os(macOS)
            WorkspaceComposer()
            #endif
        }
    }
    private var steps: some View {
        VStack(alignment: .leading, spacing: 18) {
            ForEach(Array(["Comparison criteria set", "Pricing and limits collected", "Checking integrations", "Drafting team email"].enumerated()), id: \.offset) { i, s in
                BlotLabel(store.t(s), symbol: i < 2 ? "checkmark" : i == 2 ? "arrow.clockwise" : "circle").foregroundStyle(WorkspaceStyle.secondary)
            }
        }.padding(.top, 16)
    }
    private var approval: some View {
        VStack(alignment: .leading, spacing: 24) {
            WorkspaceHeading(title: "Email ready", subtitle: "Review it before sending.")
            WorkspaceCard {
                VStack(alignment: .leading, spacing: 16) {
                    BlotLabel(store.t("Send email"), symbol: "paperplane").font(.title2.weight(.medium))
                    Text("To: team@blot.app\nFrom: preview@blot.local").foregroundStyle(WorkspaceStyle.secondary)
                    VStack(alignment: .leading, spacing: 18) {
                        Text(store.t("Email platform: MailerLite")).font(.headline)
                        Text(store.t("Team, I compared 8 services.\n\nI suggest MailerLite: the automations and integrations we need are on the base plan. Comparison table attached."))
                    }.padding(20).frame(maxWidth: .infinity, alignment: .leading).background(WorkspaceStyle.canvas, in: RoundedRectangle(cornerRadius: 22))
                    BlotLabel("email-platforms.pdf · 248 KB", symbol: "doc").foregroundStyle(WorkspaceStyle.secondary)
                }
            }
            WorkspaceV3ActionButton(title: "Yes", action: .approve, next: .result)
            WorkspaceV3ActionButton(title: "No", action: .deny, next: .chat, kind: .quiet)
            WorkspaceV3ActionButton(title: "Yes, don’t ask again", action: .grantRule, next: .permissionRules, kind: .quiet)
            Text(store.t("Sends from your Gmail, can’t be unsent.\nMacBook Pro · requested by Blot CEO · expires in 10 min"))
                .font(.footnote).foregroundStyle(WorkspaceStyle.secondary).multilineTextAlignment(.center).frame(maxWidth: .infinity)
            WorkspaceFeedback()
        }.frame(maxWidth: 820).frame(maxWidth: .infinity)
    }
    private var result: some View {
        #if os(macOS)
        HStack(alignment: .top, spacing: 28) {
            resultSummary.frame(width: 300)
            WorkspaceCard {
                VStack(alignment: .leading, spacing: 24) {
                    Text(store.t("Choosing an email service")).font(.largeTitle)
                    Text(store.t("Comparison ready")).foregroundStyle(WorkspaceStyle.secondary)
                    WorkspaceCard { Text("MailerLite").font(.headline); Text(store.t("Compared 8 services. I recommend MailerLite: it covers the features we need and is the easiest to set up.")) }
                    Grid(alignment: .leading, horizontalSpacing: 30, verticalSpacing: 22) {
                        GridRow { Text(store.t("Service")).bold(); Text(store.t("Automation")).bold(); Text(store.t("Notes")).bold() }
                        Divider()
                        ForEach(["MailerLite", "Brevo", "Mailchimp", "Customer.io"], id: \.self) { name in
                            GridRow { Text(name); Text(store.t("Available")); Text(store.t("See sources in report")) }
                        }
                    }
                    Text(store.t("8 services · 12 sources · 4.8 KB")).font(.caption).foregroundStyle(WorkspaceStyle.secondary)
                }.padding(10)
            }
        }
        #else
        resultSummary
        #endif
    }
    private var resultSummary: some View {
        VStack(alignment: .leading, spacing: 24) {
            WorkspaceCard {
                VStack(alignment: .leading, spacing: 18) {
                    Text(store.t("Comparison ready")).font(.title2.weight(.medium))
                    Text(store.t("Compared 8 services. I recommend MailerLite: it covers the features we need and is the easiest to set up."))
                    Text(store.t("The team email went out after your approval. Full table, limits and sources are in the file."))
                }
            }
            WorkspaceCard { WorkspaceLink(title: "email-platforms.md", route: .file, symbol: "arrow.down.to.line")
                Text(store.t("8 services · 12 sources · 4.8 KB")).font(.caption).foregroundStyle(WorkspaceStyle.secondary) }
            WorkspaceCard { Text(store.t("What’s next?")).font(.title2)
                WorkspaceLink(title: "Prepare a test send", route: .chat)
                WorkspaceLink(title: "Show alternatives", route: .chat)
                WorkspaceLink(title: "Change criteria", route: .chat) }
            #if os(macOS)
            WorkspaceComposer()
            #endif
        }
    }
    private var document: some View {
        VStack(alignment: .leading, spacing: 22) {
            BlotLabel("Meal planner · 3.1 KB", symbol: "doc").font(.caption).foregroundStyle(WorkspaceStyle.secondary)
            WorkspaceCard {
                VStack(alignment: .leading, spacing: 22) {
                    Text(store.t("PLAN FOR NOV 2–6")).font(.caption.monospaced()).foregroundStyle(WorkspaceStyle.secondary)
                    Text(store.t("A week without “what’s for dinner?”")).font(.largeTitle)
                    Text(store.t("For one · 5 days · 90 min on Sunday")).foregroundStyle(WorkspaceStyle.secondary)
                    Text(store.t("Dinners")).font(.title2)
                    ForEach(["Chicken curry with rice", "Salmon with vegetables", "Chicken noodles", "Curry with rice", "Salmon and fresh salad"], id: \.self) { Text(store.t($0)) }
                    Text(store.t("Shopping list")).font(.title2)
                    Text(store.t("Chicken · 800 g\nRice · 400 g\nSalmon · 2 portions\nBroccoli, carrots, cucumbers"))
                }
            }
            WorkspaceV3ActionButton(title: "Save to Files", action: .saveFile)
            WorkspaceFeedback()
        }
    }
    private var review: some View {
        VStack(alignment: .leading, spacing: 24) {
            WorkspaceHeading(title: "Changes ready", subtitle: "Hero and mobile layout updated.")
            HStack(alignment: .top, spacing: 22) {
                VStack(alignment: .leading, spacing: 18) { Text("index.tsx"); Text("page.tsx"); Text("globals.css"); Text("README.md") }.font(.system(.callout, design: .monospaced)).frame(width: 130, alignment: .leading)
                VStack(alignment: .leading, spacing: 0) {
                    Text("export function Hero() {\n  return (").padding(12)
                    Text("− <section className=\"hero old\">").padding(12).frame(maxWidth: .infinity, alignment: .leading).background(Color.red.opacity(0.09))
                    Text("+ <section className=\"hero responsive\">").padding(12).frame(maxWidth: .infinity, alignment: .leading).background(Color.green.opacity(0.09))
                    Text("    <BlotAvatar />\n    <h1>Your AI team</h1>\n  );\n}").padding(12)
                }.font(.system(.callout, design: .monospaced)).textSelection(.enabled)
            }.padding(16).overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(BlotColor.edge))
            WorkspaceCard {
                BlotLabel(store.t("6 files changed"), symbol: "checkmark")
                BlotLabel(store.t("Tests and build passed"), symbol: "checkmark")
                Text(store.t("Applying moves the checked changes into the project.")).foregroundStyle(WorkspaceStyle.secondary)
            }
            WorkspaceV3ActionButton(title: "Apply changes", action: .applyChanges)
            WorkspaceFeedback()
        }
    }
    private var blocked: some View {
        VStack(alignment: .leading, spacing: 24) {
            WorkspaceHeading(title: "Task blocked", subtitle: "A computer cannot give work to another computer.")
            WorkspaceCard {
                BlotLabel(store.t("This computer can only run its own tasks."), symbol: "exclamationmark.shield").font(.headline)
                Text(store.t("Use the phone to choose another computer. Running work stays on its original executor.")).foregroundStyle(WorkspaceStyle.secondary)
                WorkspaceLink(title: "Open on this computer", route: .chat)
            }
            WorkspaceComposer()
        }
    }
    private var offline: some View {
        VStack(alignment: .leading, spacing: 24) {
            BlotLabel(store.t("MacBook Pro · offline"), symbol: "laptopcomputer").foregroundStyle(WorkspaceStyle.secondary)
            WorkspaceDataState(state: .offline)
            WorkspaceLink(title: "Use another computer", route: .devices)
            WorkspaceLink(title: "Chat without tools", route: .newChat)
            Text(store.t("History and files are available. New actions start when the computer is back online.")).font(.footnote).foregroundStyle(WorkspaceStyle.secondary)
            #if os(macOS)
            WorkspaceComposer()
            #endif
        }
    }
    private var browser: some View {
        VStack(alignment: .leading, spacing: 20) {
            WorkspaceHeading(title: "Researcher is browsing", subtitle: "Needs you on MacBook Pro")
            if store.isPreview {
                VStack(alignment: .leading, spacing: 18) {
                    BlotLabel("mailerlite.com/pricing · preview", symbol: "globe").font(.caption)
                    HStack { Capsule().frame(width: 72, height: 8); Capsule().frame(width: 45, height: 8).opacity(0.2); Capsule().frame(width: 32, height: 8).opacity(0.2) }
                    Rectangle().frame(height: 12).padding(.trailing, 90)
                    HStack { ForEach(0..<3) { _ in WorkspaceCard(padding: 14) { RoundedRectangle(cornerRadius: 3).frame(height: 8); RoundedRectangle(cornerRadius: 3).frame(height: 6).opacity(0.2) } } }
                    WorkspaceCard { Text(store.t("Verify you are human")); BlotLabel(store.t("I’m not a robot"), symbol: "square") }
                }.padding(18).overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(BlotColor.edge))
            }
            WorkspaceCard { Text(store.t("Needs you on MacBook Pro")).font(.headline)
                Text(store.t("The site asks to verify you’re human. Complete the check on your computer, then Blot continues.")).foregroundStyle(WorkspaceStyle.secondary) }
            BlotLabel(store.t("Opened pricing page"), symbol: "checkmark")
            BlotLabel(store.t("Read plan limits"), symbol: "checkmark")
            BlotLabel(store.t("Paused: human check"), symbol: "pause")
            WorkspaceV3ActionButton(title: "Stop task", action: .stop, next: .chat, kind: .destructive)
            WorkspaceFeedback()
            #if os(macOS)
            WorkspaceComposer()
            #endif
        }
    }
}
