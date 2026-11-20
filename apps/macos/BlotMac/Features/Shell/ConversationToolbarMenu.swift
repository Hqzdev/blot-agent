import AppKit
import BlotDesign
import SwiftUI

struct ConversationToolbarMenu: View {
    @Environment(AppState.self) private var app
    @Environment(\.openWindow) private var openWindow
    let item: SidebarConversation
    @State private var renaming = false
    @State private var title = ""
    @State private var scheduling = false
    @State private var copyFailed = false

    private var pinned: Bool { app.shell.pins.contains(item.id) }
    private var archived: Bool { app.shell.archived.contains(item.id) }

    var body: some View {
        Menu {
            Button { title = item.title; renaming = true } label: { BlotLabel("Rename", symbol: "pencil", size: 16) }.disabled(item.kind != .chat)
                .keyboardShortcut("r", modifiers: [.option, .command])
            Button { app.shell.togglePin(item.id) } label: {
                BlotLabel(pinned ? "Unpin" : "Pin", symbol: pinned ? "pin.slash" : "pin", size: 16)
            }.disabled(archived).keyboardShortcut("p", modifiers: [.option, .command])
            Divider()
            Button {
                let session = app.createSideChat(for: item)
                openWindow(value: ConversationWindowRequest(id: session.id, title: session.title,
                    transcript: app.transcript(for: item), chatID: session.id))
            } label: { BlotLabel("New side chat", symbol: "bubble.left.and.bubble.right", size: 16) }
                .keyboardShortcut("s", modifiers: [.option, .command])
            Menu {
                Button("Fork entire conversation") { app.forkConversation(item) }.disabled(item.kind != .chat)
            } label: { BlotLabel("Create fork", symbol: "point.3.connected.trianglepath.dotted", size: 16) }
            Button { scheduling = true } label: { BlotLabel("Add scheduled task…", symbol: "clock", size: 16) }
            Divider()
            ShareLink(item: app.transcript(for: item)) { BlotLabel("Share", symbol: "square.and.arrow.up", size: 16) }
            Menu {
                Button("Conversation") { copy(app.transcript(for: item)) }
                Button("Title") { copy(item.title) }
                Button("Conversation ID") { copy(item.id) }
            } label: { BlotLabel("Copy", symbol: "doc.on.doc", size: 16) }
            Divider()
            Button {
                openWindow(value: ConversationWindowRequest(id: item.id, title: item.title, transcript: app.transcript(for: item)))
            } label: { BlotLabel("Open in new window", symbol: "macwindow.on.rectangle", size: 16) }
            Menu {
                Button("Chat") { app.openConversation(item) }
                if item.kind != .chat {
                    Button("Review") { app.openConversation(item); app.showShellReview() }
                    Button("Project sources") {
                        app.openConversation(item)
                        app.reviewVisible = false; app.inspectorVisible = false
                        app.shell.previewSource = nil; app.shell.rightVisible = true; app.shell.expandedSources = true
                    }
                }
            } label: { BlotLabel("Open in", symbol: "arrow.up.right", size: 16) }
            Divider()
            Button {
                if archived { app.shell.restore(item.id) } else { app.shell.archive(item.id) }
            } label: {
                BlotLabel(archived ? "Restore from archive" : "Archive", symbol: archived ? "arrow.uturn.backward" : "archivebox", size: 16)
            }.keyboardShortcut("a", modifiers: [.shift, .command])
        } label: {
            KIcon("ellipsis", size: 16, color: K.text2)
                .frame(width: K.iconButtonSize, height: K.iconButtonSize).kHover(radius: K.rSm)
        }
        .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
        .kFocusRing(radius: K.rSm).accessibilityLabel("Conversation actions").help("Conversation actions")
        .alert("Rename conversation", isPresented: $renaming) {
            TextField("Title", text: $title)
            Button("Cancel", role: .cancel) {}
            Button("Save") { app.renameConversation(item, to: title) }
                .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .alert("Could not copy", isPresented: $copyFailed) { Button("OK", role: .cancel) {} }
        .sheet(isPresented: $scheduling) {
            AutomationEditorView(initialTitle: item.title, initialInstructions: "Follow up on this conversation:\n\n" + app.transcript(for: item),
                                 initialProject: item.project)
        }
    }

    private func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        copyFailed = !NSPasteboard.general.setString(text, forType: .string)
    }
}
