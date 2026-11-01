import AppKit
import BlotDesign
import SwiftUI

struct ProfileSheetView: View {
    @Environment(AppState.self) private var app
    @Environment(\.dismiss) private var dismiss
    let sheet: ProfileSheet
    @State private var invitation = "Try Blot with me — a workspace for building with AI, reviewing changes and working with a team of agents."

    var body: some View {
        KSheet(title, width: 440) {
            switch sheet {
            case .invitation: invite
            case .guide: guide
            case .about: about
            }
        } footer: {
            KButton(title: "Done", kind: .primary) { dismiss() }.keyboardShortcut(.defaultAction)
        }
        .blotTheme(app.theme).tint(K.inverse)
    }

    private var title: String {
        switch sheet {
        case .invitation: "Invite a friend"
        case .guide: "Getting started"
        case .about: "About Blot"
        }
    }

    private var invite: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Copy a message to share Blot with a friend.").font(KFont.ui(13)).foregroundStyle(K.text2)
            KTextArea(text: $invitation, minHeight: 110)
                .accessibilityLabel("Invitation message")
            CopyButton(text: invitation, title: "Copy invitation", kind: .primary)
        }
    }

    private var guide: some View {
        VStack(alignment: .leading, spacing: 16) {
            guideSection("Start a task", "Choose a project in Code, describe what to build and send it. Blot drafts a plan for you to approve. ⌘N opens a new task.")
            guideSection("Work with a team", "Open Motes in Code and start a run. The plan assigns specialists; follow them in the conversation or the graph.")
            guideSection("Review the result", "Open Results & Git to inspect artifacts, reviews and tool operations, then accept the result and prepare a commit.")
            guideSection("Find your way", "⌘K searches tasks, files and actions. Esc closes menus, sheets and the command palette.")
        }
    }

    private var about: some View {
        VStack(alignment: .leading, spacing: 12) {
            BlotView(size: 76, behavior: .subtle)
            Text("Blot").font(KFont.pageTitle()).foregroundStyle(K.text)
            Text("Version \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")")
                .font(KFont.body()).foregroundStyle(K.text3)
            Text("A workspace for tasks, agent teams and reviewing changes.").font(KFont.body()).foregroundStyle(K.text2)
        }
    }

    private func guideSection(_ heading: String, _ text: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(heading).font(KFont.label()).foregroundStyle(K.text)
            Text(text).font(KFont.ui(13)).foregroundStyle(K.text2).lineSpacing(3).fixedSize(horizontal: false, vertical: true)
        }
    }
}
