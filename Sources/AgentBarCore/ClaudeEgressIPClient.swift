import Foundation
import Network

public struct ClaudeEgressIPSnapshot: Equatable, Sendable {
    public let ipAddress: String
    public let checkedAt: Date

    public init(ipAddress: String, checkedAt: Date) {
        self.ipAddress = ipAddress
        self.checkedAt = checkedAt
    }
}

public enum ClaudeEgressIPError: LocalizedError, Equatable {
    case invalidResponse
    case httpStatus(Int)
    case network

    public var errorDescription: String? {
        switch self {
        case .invalidResponse: return "Claude IP check did not return a valid IP address."
        case let .httpStatus(status): return "Claude IP check failed (HTTP \(status))."
        case .network: return "Could not check Claude's outbound IP. Check the network and proxy settings."
        }
    }
}

/// Uses the quota API's host so domain-based proxy rules apply to both requests.
/// This diagnostic is unauthenticated and never reads or sends Claude credentials.
public struct ClaudeEgressIPClient: Sendable {
    public static let endpoint = URL(string: "https://api.anthropic.com/cdn-cgi/trace")!
    public static let bodyLimit = 16 * 1024
    private let transport: any ClaudeQuotaHTTPTransport
    private let now: @Sendable () -> Date

    public init(
        transport: any ClaudeQuotaHTTPTransport = URLSessionClaudeQuotaTransport(),
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.transport = transport
        self.now = now
    }

    public func fetch(proxy: NetworkProxySettings = .init()) async throws -> ClaudeEgressIPSnapshot {
        try Task.checkCancellation()
        try proxy.validate()
        var request = URLRequest(url: Self.endpoint)
        request.httpMethod = "GET"
        request.timeoutInterval = ClaudeQuotaClient.requestTimeout
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("text/plain", forHTTPHeaderField: "Accept")
        request.setValue("no-cache, no-store", forHTTPHeaderField: "Cache-Control")
        request.setValue("AgentBar/menubar", forHTTPHeaderField: "User-Agent")
        let (data, response): (Data, HTTPURLResponse)
        do {
            (data, response) = try await transport.data(for: request, proxy: proxy, bodyLimit: Self.bodyLimit)
        } catch let error as NetworkProxyError {
            throw error
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as ClaudeQuotaClientError where error == .invalidResponse || error == .responseTooLarge {
            throw ClaudeEgressIPError.invalidResponse
        } catch {
            try Task.checkCancellation()
            // Never show a response body or a transport error containing proxy credentials.
            throw ClaudeEgressIPError.network
        }
        try Task.checkCancellation()
        guard response.statusCode == 200 else { throw ClaudeEgressIPError.httpStatus(response.statusCode) }
        guard response.url == Self.endpoint,
              data.count <= Self.bodyLimit,
              let trace = String(data: data, encoding: .utf8) else {
            throw ClaudeEgressIPError.invalidResponse
        }

        var fields: [String: String] = [:]
        for line in trace.split(whereSeparator: \.isNewline) {
            let pair = line.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            guard pair.count == 2 else { continue }
            let key = String(pair[0])
            guard key == "h" || key == "ip" else { continue }
            guard fields[key] == nil else { throw ClaudeEgressIPError.invalidResponse }
            fields[key] = String(pair[1])
        }
        guard fields["h"] == Self.endpoint.host, let ip = fields["ip"],
              !ip.contains("%"), IPv4Address(ip) != nil || IPv6Address(ip) != nil else {
            throw ClaudeEgressIPError.invalidResponse
        }
        return ClaudeEgressIPSnapshot(ipAddress: ip, checkedAt: now())
    }
}
