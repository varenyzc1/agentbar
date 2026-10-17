import Foundation

public protocol ClaudeQuotaHTTPTransport: Sendable {
    func data(for request: URLRequest, proxy: NetworkProxySettings, bodyLimit: Int) async throws -> (Data, HTTPURLResponse)
}

public enum ClaudeQuotaClientError: LocalizedError, Equatable {
    case invalidResponse
    case noQuotaWindows
    case tokenExpired
    case forbidden
    case rateLimited(retryAfter: Date?)
    case httpStatus(Int)
    case responseTooLarge
    case network

    public var errorDescription: String? {
        switch self {
        case .invalidResponse: return "Invalid Claude quota response."
        case .noQuotaWindows: return "This Claude account did not return subscription quota windows."
        case .tokenExpired: return "Claude login expired. Open Claude Code or run claude auth login."
        case .forbidden: return "Claude quota access denied. Sign in to Claude Code with subscription usage access."
        case .rateLimited: return "Claude quota refresh was rate limited. Waiting before retrying."
        case let .httpStatus(status): return "Claude quota request failed (HTTP \(status))."
        case .responseTooLarge: return "Claude quota response was too large."
        case .network: return "Could not connect to Claude. Check the network and proxy settings."
        }
    }
}

public struct ClaudeQuotaClient: Sendable {
    public static let endpoint = URL(string: "https://api.anthropic.com/api/oauth/usage")!
    public static let requestTimeout: TimeInterval = 8
    public static let bodyLimit = 256 * 1024
    private let transport: any ClaudeQuotaHTTPTransport
    private let now: @Sendable () -> Date

    public init(
        transport: any ClaudeQuotaHTTPTransport = URLSessionClaudeQuotaTransport(),
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.transport = transport
        self.now = now
    }

    public func fetch(credentials: ClaudeCredentials, proxy: NetworkProxySettings = .init()) async throws -> ClaudeQuotaSnapshot {
        try proxy.validate()
        var request = URLRequest(url: Self.endpoint)
        request.httpMethod = "GET"
        request.timeoutInterval = Self.requestTimeout
        request.setValue("Bearer \(credentials.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("AgentBar/menubar", forHTTPHeaderField: "User-Agent")
        let (data, response): (Data, HTTPURLResponse)
        do {
            (data, response) = try await transport.data(for: request, proxy: proxy, bodyLimit: Self.bodyLimit)
        } catch let error as ClaudeQuotaClientError {
            throw error
        } catch let error as NetworkProxyError {
            throw error
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            // Transport errors can contain URLs or credential-bearing proxy details.
            throw ClaudeQuotaClientError.network
        }
        switch response.statusCode {
        case 200:
            return try ClaudeQuotaParser.parse(data, now: now(), plan: credentials.plan)
        case 401: throw ClaudeQuotaClientError.tokenExpired
        case 403: throw ClaudeQuotaClientError.forbidden
        case 429:
            throw ClaudeQuotaClientError.rateLimited(retryAfter: Self.retryAfter(response.value(forHTTPHeaderField: "Retry-After"), now: now()))
        default: throw ClaudeQuotaClientError.httpStatus(response.statusCode)
        }
    }

    static func retryAfter(_ value: String?, now: Date) -> Date? {
        guard let value else { return nil }
        if let seconds = Double(value), seconds.isFinite, seconds >= 0 {
            return now.addingTimeInterval(seconds)
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss z"
        return formatter.date(from: value)
    }
}

public struct URLSessionClaudeQuotaTransport: ClaudeQuotaHTTPTransport {
    public init() {}

    public func data(for request: URLRequest, proxy: NetworkProxySettings, bodyLimit: Int) async throws -> (Data, HTTPURLResponse) {
        let session = URLSession(configuration: try Self.makeConfiguration(proxy: proxy), delegate: ClaudeQuotaRedirectGuard(), delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        let (bytes, response) = try await session.bytes(for: request)
        guard let response = response as? HTTPURLResponse else { throw ClaudeQuotaClientError.invalidResponse }
        var data = Data()
        for try await byte in bytes {
            guard data.count < bodyLimit else { throw ClaudeQuotaClientError.responseTooLarge }
            data.append(byte)
        }
        return (data, response)
    }

    public static func makeConfiguration(proxy: NetworkProxySettings = .init()) throws -> URLSessionConfiguration {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = ClaudeQuotaClient.requestTimeout
        configuration.timeoutIntervalForResource = ClaudeQuotaClient.requestTimeout
        configuration.waitsForConnectivity = false
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        try proxy.apply(to: configuration)
        return configuration
    }
}

/// The fixed OAuth endpoint must never forward credentials through a redirect.
final class ClaudeQuotaRedirectGuard: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(
        _ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void
    ) {
        completionHandler(nil)
    }
}
