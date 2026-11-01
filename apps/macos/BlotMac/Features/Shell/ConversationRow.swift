import AppKit
import BlotDesign
import SwiftUI

struct ConversationRow: View {
    @Environment(AppState.self) private var app
    let item: SidebarConversation
    let selected: Bool
    var indented = false
    let open: () -> Void
    @State private var hovered = false
    @State private var renaming = false
    @State private var title = ""
    @State private var copyFailed = false
    @FocusState private var focused: Control?

    private enum Control: Hashable { case open, pin, archive }
    private var archived: Bool { app.shell.archived.contains(item.id) }
    private var pinned: Bool { app.shell.pins.contains(item.id) }
    private var unread: Bool { app.shell.unread.contains(item.id) }
    private var actionsVisible: Bool { hovered || focused != nil }

    var body: some View {
        HStack(spacing: 0) {
            Button(action: open) {
                HStack(spacing: 6) {
                    Text(item.title).font(KFont.label(unread ? .semibold : selected ? .medium : .regular))
                        .foregroundStyle(K.text)
                        .lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
                    if item.running {
                        KIcon("activity", size: 12, color: K.success).accessibilityHidden(true)
                            .help("Running")
                    } else if unread {
                        StatusDot(color: K.focus, size: 6).accessibilityHidden(true)
                    }
                }
                .padding(.leading, indented ? 34 : 10).padding(.trailing, 6)
                .frame(height: K.sidebarRowHeight).contentShape(Rectangle())
            }
            .focused($focused, equals: .open)
            .buttonStyle(KIconButtonStyle()).overlay { focusOutline(for: .open) }
            .accessibilityAddTraits(selected ? .isSelected : [])
            .accessibilityValue([item.running ? "Running" : nil, unread ? "Unread" : nil].compactMap { $0 }.joined(separator: ", "))
            .help(item.title)

            if actionsVisible {
                if !archived {
                    action(pinned ? "pin.slash" : "pin", title: pinned ? "Unpin" : "Pin", control: .pin) {
                        app.shell.togglePin(item.id)
                    }
                }
                action(archived ? "arrow.uturn.backward" : "archivebox",
                       title: archived ? "Restore from archive" : "Archive", control: .archive) {
                    toggleArchive()
                }
            }
        }
        .padding(.trailing, 4)
        .background(RoundedRectangle(cornerRadius: K.rSm, style: .continuous)
            .fill(selected ? K.selected : hovered || focused != nil ? K.hover : .clear))
        .contentShape(Rectangle())
        .onHover { hovered = $0 }
        .contextMenu {
            Button { title = item.title; renaming = true } label: { Label("Rename", systemImage: "pencil") }.disabled(item.kind != .chat)
            if !archived {
                Button { app.shell.togglePin(item.id) } label: {
                    Label(pinned ? "Unpin" : "Pin", systemImage: pinned ? "pin.slash" : "pin")
                }
            }
            Button {
                if unread { app.shell.markRead(item.id) } else { app.shell.markUnread(item.id) }
            } label: { Label(unread ? "Mark as read" : "Mark as unread", systemImage: "eye") }
            Divider()
            Menu {
                Button("Title") { copy(item.title) }
                Button("Conversation ID") { copy(item.id) }
            } label: { Label("Copy", systemImage: "doc.on.doc") }
            Divider()
            Button { toggleArchive() } label: {
                Label(archived ? "Restore from archive" : "Archive",
                      systemImage: archived ? "arrow.uturn.backward" : "archivebox")
            }
        }
        .alert("Rename conversation", isPresented: $renaming) {
            TextField("Title", text: $title)
            Button("Cancel", role: .cancel) {}
            Button("Save") { app.renameConversation(item, to: title) }
                .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .alert("Could not copy", isPresented: $copyFailed) { Button("OK", role: .cancel) {} }
    }

    private func action(_ icon: String, title: String, control: Control,
                        perform: @escaping () -> Void) -> some View {
        Button(action: perform) {
            KIcon(icon, size: 15, color: K.text2).frame(width: 26, height: K.sidebarRowHeight)
                .contentShape(Rectangle()).kHover(radius: K.rSm)
        }
        .buttonStyle(KIconButtonStyle()).focused($focused, equals: control)
        .overlay { focusOutline(for: control) }
        .accessibilityLabel(title + " “" + item.title + "”").help(title)
    }

    private func focusOutline(for control: Control) -> some View {
        RoundedRectangle(cornerRadius: K.rSm, style: .continuous)
            .strokeBorder(focused == control ? K.focus : .clear, lineWidth: 2)
            .allowsHitTesting(false)
    }

    private func toggleArchive() {
        if archived { app.shell.restore(item.id) } else { app.shell.archive(item.id) }
    }

    private func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        copyFailed = !NSPasteboard.general.setString(text, forType: .string)
    }
}
