import BlotDesign
import Foundation

/// Bonjour находит текущий порт установки; доверие серверу затем проверяет TLS pin.
@MainActor
final class MacDiscovery: NSObject, @preconcurrency NetServiceBrowserDelegate, @preconcurrency NetServiceDelegate {
    private let browser = NetServiceBrowser()
    private var services: [NetService] = []
    private var expectedInstallation = ""
    private var completion: CheckedContinuation<URL?, Never>?
    private var timeout: Task<Void, Never>?

    func find(installationId: String) async -> URL? {
        expectedInstallation = installationId
        return await withCheckedContinuation { continuation in
            completion = continuation
            browser.delegate = self
            browser.searchForServices(ofType: "_blot._tcp.", inDomain: "local.")
            timeout = Task { [weak self] in
                do { try await Task.sleep(for: .seconds(5)); self?.finish(nil) } catch { }
            }
        }
    }

    func cancel() { finish(nil) }

    func netServiceBrowser(_ browser: NetServiceBrowser, didFind service: NetService, moreComing: Bool) {
        guard completion != nil, services.count < 16,
              service.name.hasPrefix("Blot " + expectedInstallation.prefix(8)) else { return }
        services.append(service)
        service.delegate = self
        service.resolve(withTimeout: 3)
    }

    func netServiceDidResolveAddress(_ service: NetService) {
        guard let data = service.txtRecordData() else { return }
        let record = NetService.dictionary(fromTXTRecord: data)
        guard let id = record["installationId"], String(data: id, encoding: .utf8) == expectedInstallation,
              let host = service.hostName, service.port > 0 else { return }
        var address = URLComponents()
        address.scheme = "https"; address.host = host; address.port = service.port; address.path = "/"
        if let url = address.url { finish(url) }
    }

    func netServiceBrowser(_ browser: NetServiceBrowser, didNotSearch errorDict: [String: NSNumber]) { finish(nil) }

    private func finish(_ value: URL?) {
        guard let completion else { return }
        self.completion = nil
        timeout?.cancel(); timeout = nil
        browser.stop(); browser.delegate = nil
        for service in services { service.stop(); service.delegate = nil }
        services = []
        completion.resume(returning: value)
    }
}
