import Foundation
import Security

/// Adds selected public CA roots only for the configured provider hosts; hostname validation stays enabled.
private final class ProviderTrustPolicy: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    private let certificates: [SecCertificate]
    private let hosts: Set<String>
    init(certificates: [SecCertificate], hosts: Set<String>) { self.certificates = certificates; self.hosts = hosts }
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void) { completionHandler(nil) }
    func urlSession(_ session: URLSession, task: URLSessionTask, didReceive challenge: URLAuthenticationChallenge,
                    completionHandler: @escaping @Sendable (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              hosts.contains(challenge.protectionSpace.host), !certificates.isEmpty,
              let trust = challenge.protectionSpace.serverTrust else { completionHandler(.performDefaultHandling, nil); return }
        let policy = SecPolicyCreateSSL(true, challenge.protectionSpace.host as CFString)
        guard SecTrustSetPolicies(trust, policy) == errSecSuccess,
              SecTrustSetAnchorCertificates(trust, certificates as CFArray) == errSecSuccess,
              SecTrustSetAnchorCertificatesOnly(trust, false) == errSecSuccess,
              SecTrustEvaluateWithError(trust, nil) else { completionHandler(.cancelAuthenticationChallenge, nil); return }
        completionHandler(.useCredential, URLCredential(trust: trust))
    }
}

enum ProviderTrustSession {
    static func make(certificatePEM: Data?, hosts: Set<String>) throws -> URLSession {
        var certificates: [SecCertificate] = []
        if let certificatePEM {
            let text = String(decoding: certificatePEM, as: UTF8.self)
            let expression = try NSRegularExpression(pattern: "-----BEGIN CERTIFICATE-----([A-Za-z0-9+/=\\r\\n\\t ]+)-----END CERTIFICATE-----")
            for match in expression.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
                guard let range = Range(match.range(at: 1), in: text),
                      let bytes = Data(base64Encoded: String(text[range]).filter { !$0.isWhitespace }),
                      let certificate = SecCertificateCreateWithData(nil, bytes as CFData) else { throw ChatModelError.invalidConfiguration }
                certificates.append(certificate)
            }
            guard (1...4).contains(certificates.count) else { throw ChatModelError.invalidConfiguration }
        }
        let config = URLSessionConfiguration.ephemeral
        config.httpCookieStorage = nil; config.urlCache = nil
        config.tlsMinimumSupportedProtocolVersion = .TLSv12
        config.timeoutIntervalForRequest = 120; config.timeoutIntervalForResource = 600
        return URLSession(configuration: config, delegate: ProviderTrustPolicy(certificates: certificates, hosts: hosts), delegateQueue: nil)
    }
}
