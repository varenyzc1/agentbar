import Foundation
import Network

public enum NetworkProxyMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case system
    case manual

    public var id: String { rawValue }
}

public enum NetworkProxyError: LocalizedError, Equatable {
    case invalidAddress
    case credentialsNotSupported

    public var errorDescription: String? {
        switch self {
        case .invalidAddress:
            return "Enter an HTTP, HTTPS or SOCKS5 proxy address with a valid host and port."
        case .credentialsNotSupported:
            return "Proxy addresses with usernames or passwords are not supported."
        }
    }
}

public struct NetworkProxySettings: Codable, Equatable, Sendable {
    public var mode: NetworkProxyMode
    public var address: String

    public init(mode: NetworkProxyMode = .system, address: String = "") {
        self.mode = mode
        self.address = address
    }

    public func validate() throws {
        // Reject embedded secrets even in an inactive address: settings are saved as JSON.
        if !address.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            _ = try endpoint()
        } else if mode == .manual {
            throw NetworkProxyError.invalidAddress
        }
    }

    public func apply(to configuration: URLSessionConfiguration) throws {
        guard mode == .manual else { return } // Leave both proxy properties untouched for system routing.
        let proxy = try endpoint()
        let endpoint = NWEndpoint.hostPort(host: .init(proxy.host), port: .init(rawValue: proxy.port)!)
        var policy: ProxyConfiguration
        switch proxy.scheme {
        case "socks5":
            policy = ProxyConfiguration(socksv5Proxy: endpoint)
        case "https":
            policy = ProxyConfiguration(httpCONNECTProxy: endpoint, tlsOptions: NWProtocolTLS.Options())
        default:
            policy = ProxyConfiguration(httpCONNECTProxy: endpoint)
        }
        policy.allowFailover = false
        configuration.proxyConfigurations = [policy]
    }

    private func endpoint() throws -> (scheme: String, host: String, port: UInt16) {
        let trimmed = address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.contains(where: { $0.isWhitespace }) else {
            throw NetworkProxyError.invalidAddress
        }
        let value = trimmed.contains("://") ? trimmed : "http://\(trimmed)"
        guard let components = URLComponents(string: value) else { throw NetworkProxyError.invalidAddress }
        guard components.user == nil, components.password == nil else {
            throw NetworkProxyError.credentialsNotSupported
        }
        guard let scheme = components.scheme?.lowercased(), ["http", "https", "socks5"].contains(scheme),
              let host = components.host, !host.isEmpty,
              components.path.isEmpty || components.path == "/",
              components.query == nil, components.fragment == nil,
              let port = components.port, (1...65535).contains(port) else {
            throw NetworkProxyError.invalidAddress
        }
        // URLComponents preserves brackets around IPv6 hosts; Network expects the literal address.
        return (scheme, host.trimmingCharacters(in: CharacterSet(charactersIn: "[]")), UInt16(port))
    }
}
