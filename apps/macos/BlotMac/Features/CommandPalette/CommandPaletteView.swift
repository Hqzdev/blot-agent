import BlotDesign
import SwiftUI

struct CommandPaletteView: View {
    @Environment(AppState.self) private var app
    @State private var query = ""
    @State private var selectedID: String?
    @State private var preview: PaletteEntry?
    @FocusState private var searchFocused: Bool
    private var results: [PaletteEntry] { CommandPaletteIndex.entries(projects: app.projects, query: query) }

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .top) {
                K.scrim.contentShape(Rectangle()).onTapGesture { dismiss() }
                VStack(spacing: 0) {
                    header
                    if let preview {
                        filePreview(preview).frame(height: min(420, geometry.size.height - 200))
                    } else {
                        resultList.frame(maxHeight: min(420, geometry.size.height - 200))
                    }
                    HStack(spacing: 18) {
                        hint("↑↓", "navigate")
                        hint("↵", "open")
                        Spacer()
                        hint("esc", "close")
                    }
                    .padding(.horizontal, 16).frame(height: 36).kBorder(.top)
                }
                .frame(width: min(640, geometry.size.width - 48))
                .kPopover(radius: K.rXl)
                .accessibilityElement(children: .contain)
                .accessibilityAddTraits(.isModal)
                .accessibilityLabel("Command palette")
                .padding(.top, max(64, min(150, geometry.size.height * 0.17)))
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .onAppear { selectedID = results.first?.id; searchFocused = true }
        .onChange(of: query) { _, _ in selectedID = results.first?.id; preview = nil }
        .onExitCommand { dismiss() }
    }
    private var header: some View {
        HStack(spacing: 10) {
            KIcon("magnifyingglass", size: 18).accessibilityHidden(true)
            TextField("Search tasks, files and actions", text: $query)
                .textFieldStyle(.plain).font(KFont.ui(15)).foregroundStyle(K.text)
                .focused($searchFocused).onSubmit { activateSelected() }
                .onKeyPress(.downArrow) { move(1); return .handled }
                .onKeyPress(.upArrow) { move(-1); return .handled }
            Button(action: dismiss) {
                Badge(text: "esc", fg: K.text3)
            }.buttonStyle(KIconButtonStyle()).kFocusRing(radius: K.rSm).accessibilityLabel("Close command palette")
        }.padding(.horizontal, 16).frame(height: 52).kBorder(.bottom)
    }
    private var resultList: some View {
        ScrollViewReader { reader in
            ScrollView {
                VStack(spacing: 1) {
                    ForEach(["Tasks", "Files", "Actions"], id: \.self) { group in
                        let entries = results.filter { $0.group == group }
                        if !entries.isEmpty {
                            SectionLabel(title: group, actionIcon: nil)
                            ForEach(entries) { entry in
                                Button { selectedID = entry.id; activate(entry) } label: {
                                    HStack(spacing: 8) {
                                        KIcon(entry.icon, size: 15, color: selectedID == entry.id ? K.text : K.text2)
                                        Text(entry.title).font(KFont.body()).foregroundStyle(K.text).lineLimit(1)
                                        Text(entry.detail).font(KFont.caption()).foregroundStyle(K.text3).lineLimit(1)
                                        Spacer(minLength: 12)
                                        if selectedID == entry.id {
                                            KIcon("arrow-right", size: 12, color: K.text3).accessibilityHidden(true)
                                        }
                                    }.padding(.horizontal, 10).padding(.vertical, 4).frame(minHeight: 34).contentShape(Rectangle())
                                        .kHover(radius: K.rMd, active: selectedID == entry.id)
                                }
                                .buttonStyle(KIconButtonStyle()).kFocusRing(radius: K.rSm).id(entry.id)
                                .accessibilityAddTraits(selectedID == entry.id ? .isSelected : [])
                            }
                        }
                    }
                    if !query.isEmpty && !results.contains(where: { $0.group != "Actions" }) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("No tasks or files match “\(query)”").font(KFont.ui(13, .medium)).foregroundStyle(K.text2)
                            Text("Check the spelling or start a new task with this text from Actions above.")
                                .font(KFont.caption()).foregroundStyle(K.text3)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading).padding(12)
                    }
                }.padding(.horizontal, 8).padding(.bottom, 8)
            }
            .onChange(of: selectedID) { _, id in if let id { reader.scrollTo(id, anchor: .center) } }
        }
    }
    private func filePreview(_ entry: PaletteEntry) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Button { preview = nil; searchFocused = true } label: {
                HStack(spacing: 4) {
                    KIcon("chevron-left", size: 14, color: K.text2)
                    Text("Back to results").font(KFont.body()).foregroundStyle(K.text2)
                }
            }.buttonStyle(KIconButtonStyle()).kFocusRing(radius: K.rSm)
            if case let .file(projectID, taskID, path) = entry.action {
                CodeBlock(title: path, icon: "file-text", text: path, maxHeight: nil, copyable: true)
                Text("The actual changes are stored in the run's artifacts.").font(KFont.ui(13)).foregroundStyle(K.text2)
                KButton(title: "Open run results", icon: "git-pull-request", kind: .primary) {
                    app.openTask(projectID: projectID, taskID: taskID); app.reviewVisible = true; dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
            Spacer(minLength: 0)
        }.padding(16).frame(maxWidth: .infinity, alignment: .leading)
    }
    private func hint(_ key: String, _ label: String) -> some View {
        HStack(spacing: 5) {
            Text(key).font(KFont.mono(11)).foregroundStyle(K.text2)
            Text(label).font(KFont.caption()).foregroundStyle(K.text3)
        }
    }
    private func move(_ offset: Int) {
        guard preview == nil, !results.isEmpty else { return }
        let index = results.firstIndex { $0.id == selectedID } ?? 0
        selectedID = results[(index + offset + results.count) % results.count].id
    }
    private func activateSelected() {
        guard preview == nil, let entry = results.first(where: { $0.id == selectedID }) else { return }
        activate(entry)
    }
    private func activate(_ entry: PaletteEntry) {
        switch entry.action {
        case .file: preview = entry
        case let .task(projectID, taskID): app.openTask(projectID: projectID, taskID: taskID)
        case let .newTask(prompt): app.openHome(draft: prompt)
        case .settings: dismiss(); app.openProfileSettings(app.settings.section)
        case .automations: navigate(.automations)
        case .skills: navigate(.skills)
        case .graph: dismiss(); app.showingSettings = false; app.openGraph()
        }
    }
    private func navigate(_ route: CodeRoute) {
        dismiss(); app.showingSettings = false; app.product = .code; app.codeRoute = route
    }
    private func dismiss() { app.paletteVisible = false }
}
