import BlotWorkspace
import SwiftUI
import UniformTypeIdentifiers

struct MCPConfigurationFields: View {
    @Binding var configuration: MCPConfiguration
    @Binding var arguments: String
    @Binding var environment: String
    let russian: Bool
    @State private var picking = MCPPath.executable
    @State private var importing = false
    private func text(_ ru: String, _ en: String) -> String { russian ? ru : en }
    private var transports: [WorkspaceChoiceOption<MCPConfiguration.Transport>] {
        #if os(macOS)
        [.init(.http, "Streamable HTTP"), .init(.stdio, "stdio")]
        #else
        [.init(.http, "Streamable HTTP")]
        #endif
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            WorkspaceChoice(title: text("Транспорт", "Transport"), selection: $configuration.transport, options: transports)
            if configuration.transport == .http {
                TextField("https://server.example/mcp", text: $configuration.endpoint)
                SecureField(text("Bearer-токен (если нужен)", "Bearer token (optional)"), text: $configuration.bearerToken)
                Text(text("Токен хранится в Связке ключей. Для сервера с OAuth используйте выданный им токен.", "The token stays in Keychain. For OAuth servers, supply a token issued by that server.")).font(.caption).foregroundStyle(.secondary)
            } else {
                TextField(text("Полный путь к программе", "Absolute executable path"), text: $configuration.endpoint)
                #if os(macOS)
                Button(text("Выбрать программу…", "Choose executable…")) { picking = .executable; importing = true }
                #endif
                TextField(text("Аргументы — JSON-массив", "Arguments — JSON array"), text: $arguments)
                TextField(text("Рабочая папка", "Working directory"), text: $configuration.workingDirectory)
                #if os(macOS)
                Button(text("Выбрать папку…", "Choose directory…")) { picking = .directory; importing = true }
                #endif
                SecureField(text("Переменные среды — JSON-объект", "Environment — JSON object"), text: $environment)
                Toggle(text("Я доверяю этой программе", "I trust this executable"), isOn: $configuration.trustedLocalProcess)
                Text(text("Программа получает только заданные переменные среды и доступ в рамках системной песочницы Blot. MCP сам по себе не изолирует программу.", "The executable receives only the specified environment and access allowed by Blot’s system sandbox. MCP itself does not isolate a process.")).font(.caption).foregroundStyle(.secondary)
            }
            WorkspaceCounter(title: text("Таймаут, с", "Timeout, s"), value: Binding(get: { Int(configuration.timeout) }, set: { configuration.timeout = Double($0) }), range: 5...300, step: 5)
        }
        .onChange(of: configuration.transport) { _, _ in
            configuration.endpoint = ""; configuration.arguments = []; configuration.environment = [:]; configuration.workingDirectory = ""
            configuration.bearerToken = ""; configuration.executableBookmark = nil; configuration.directoryBookmark = nil
            arguments = "[]"; environment = "{}"
        }
        #if os(macOS)
        .fileImporter(isPresented: $importing,
                      allowedContentTypes: picking == .directory ? [.folder] : [.item]) { result in
            let target = picking
            guard let url = try? result.get() else { return }
            let scoped = url.startAccessingSecurityScopedResource(); defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            guard let bookmark = try? url.bookmarkData(options: target == .directory ? [.withSecurityScope] : [.withSecurityScope, .securityScopeAllowOnlyReadAccess], includingResourceValuesForKeys: nil, relativeTo: nil) else { return }
            if target == .directory { configuration.workingDirectory = url.path; configuration.directoryBookmark = bookmark }
            else { configuration.endpoint = url.path; configuration.executableBookmark = bookmark }
        }
        #endif
    }
}

private enum MCPPath { case executable, directory }
