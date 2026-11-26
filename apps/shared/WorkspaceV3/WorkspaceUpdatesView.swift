import BlotDesign
import BlotWorkspace
import SwiftUI

@MainActor protocol WorkspaceReleaseProviding { func releaseService() -> WorkspaceReleaseService }
extension WorkspaceAccountApplicationService: WorkspaceReleaseProviding {}

struct WorkspaceUpdatesView: View {
    @Environment(WorkspaceStore.self) private var store
    @AppStorage("blot.updates.channel") private var channel = "stable"
    @State private var release: WorkspaceRelease?
    @State private var checked: Date?
    @State private var working = false
    @State private var failure: String?
    private var ru: Bool { store.language == "ru" }
    private var installed: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "" }
    private var build: Int { Int(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0") ?? 0 }
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            BlotLabel("Ori " + installed + " (" + String(build) + ")", symbol: "arrow.down.circle").font(.title2)
            WorkspaceChoice(title: ru ? "Канал обновлений" : "Release channel", selection: $channel, options: [.init("stable", "Stable"), .init("beta", "Beta")])
                .onChange(of: channel) { _, _ in release = nil; checked = nil }
            Button(ru ? "Проверить обновления" : "Check for updates") { check() }.disabled(working || store.releaseCommands == nil)
            if let checked { Text(checked, format: .dateTime.day().month().hour().minute()).font(.caption).foregroundStyle(.secondary) }
            if let release {
                if release.isNewer(version: installed, build: build) {
                    Text((ru ? "Доступна версия " : "Available version ") + release.version).font(.headline)
                    Text(release.notes).textSelection(.enabled)
                    Text((ru ? "Минимальная ОС: " : "Minimum OS: ") + release.minimumOS).font(.caption)
                    Link(ru ? "Открыть страницу загрузки" : "Open download page", destination: release.downloadURL)
                } else { Text(ru ? "Установлена актуальная версия этого канала." : "The installed version is up to date for this channel.") }
            } else if checked != nil { Text(ru ? "В этом канале пока нет опубликованного выпуска." : "No release has been published in this channel yet.").foregroundStyle(.secondary) }
            if working { ProgressView() }
            if let failure { Text(failure).foregroundStyle(.red) }
        }
    }
    private func check() {
        guard !working, let commands = store.releaseCommands else { return }; working = true; failure = nil
        _Concurrency.Task {
            defer { working = false }
            do {
                #if os(macOS)
                let platform = "macos"
                #else
                let platform = "ios"
                #endif
                release = try await commands.releaseService().latest(platform: platform, channel: channel); checked = Date()
            } catch { checked = nil; failure = ru ? "Не удалось проверить выпуски. Проверьте соединение с сервером обновлений." : "Could not check releases. Check the update service connection." }
        }
    }
}
