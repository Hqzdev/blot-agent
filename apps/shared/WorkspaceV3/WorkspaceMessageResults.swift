import BlotDesign
import BlotDomain
import BlotWorkspace
import SwiftUI

struct WorkspaceMessageResults: View {
    let message: BlotV3.Message
    var artifactIDs: [UUID]? = nil
    @Environment(WorkspaceStore.self) private var store
    private var files: [BlotV3.Artifact] { (artifactIDs ?? message.artifactIds).compactMap { store.chatContent.artifacts[$0] } }
    private var websites: [WorkspaceResultLink.Website] { message.delivery == .completed ? WorkspaceResultLink.websites(in: message.content) : [] }
    var body: some View {
        if !files.isEmpty || !websites.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                let images = files.filter { $0.mediaType.hasPrefix("image/") }
                if !images.isEmpty {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 120, maximum: 220), spacing: 8)], spacing: 8) {
                        ForEach(images, id: \.metadata.id) { file in WorkspaceResultImage(file: file) }
                    }
                }
                ForEach(files.filter { !$0.mediaType.hasPrefix("image/") }, id: \.metadata.id) { file in WorkspaceDocumentCard(file: file) }
                ForEach(websites) { website in WorkspaceWebsiteCard(website: website) }
            }.padding(.top, 6).frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct WorkspaceWebsiteCard: View {
    let website: WorkspaceResultLink.Website
    @Environment(WorkspaceStore.self) private var store
    private var ru: Bool { store.language == "ru" }
    var body: some View {
        HStack(spacing: 12) {
            Button { store.openBrowserURL(website.url) } label: {
                HStack(spacing: 12) {
                    BlotIcon(symbol: "globe", size: 25).foregroundStyle(.cyan).frame(width: 48, height: 48)
                        .background(WorkspaceStyle.ink.opacity(0.045), in: RoundedRectangle(cornerRadius: 14))
                    VStack(alignment: .leading, spacing: 5) {
                        Text(website.title).font(.body.weight(.medium)).lineLimit(2)
                        Text(website.url.host ?? (ru ? "Веб-страница" : "Website")).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }.frame(minHeight: 50).contentShape(Rectangle())
            }.buttonStyle(.plain)
            WorkspaceFileActionsMenu {
                #if os(macOS)
                Button(ru ? "Открыть в Ori" : "Open in Ori") { store.openBrowserURL(website.url) }
                Link(ru ? "В системном браузере" : "In default browser", destination: website.url)
                #else
                Button(ru ? "Открыть ссылку" : "Open link") { store.openBrowserURL(website.url) }
                #endif
                Button(ru ? "Копировать ссылку" : "Copy link") { WorkspaceClipboard.copy(website.url.absoluteString) }
            } label: { BlotLabel(ru ? "Открыть" : "Open in", symbol: "chevron.down").font(.callout).padding(8) }
            .fixedSize()
        }.padding(12).background(WorkspaceStyle.canvas, in: RoundedRectangle(cornerRadius: 18))
            .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(WorkspaceStyle.ink.opacity(0.1)))
            .accessibilityElement(children: .contain).accessibilityLabel(ru ? "Веб-предпросмотр" : "Web preview")
    }
}
