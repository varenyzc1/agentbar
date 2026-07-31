import Foundation

public protocol GrokQuotaHTTPTransport: Sendable {
    func data(for request: URLRequest, bodyLimit: Int) async throws -> (Data, HTTPURLResponse)
}

public enum GrokQuotaClientError: LocalizedError, Equatable {
    case invalidResponse
    case tokenExpired
    case forbidden
    case rateLimited
    case httpStatus(Int, String)
    case decoding(String)
    case responseTooLarge

    public var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "Invalid Grok quota response"
        case .tokenExpired:
            return "Grok login expired. Run grok login"
        case .forbidden:
            return "Grok quota access was denied"
        case .rateLimited:
            return "Grok quota refresh was rate limited"
        case let .httpStatus(status, message):
            return "Grok quota request failed (HTTP \(status)): \(message)"
        case let .decoding(message):
            return "Could not parse Grok quota response: \(message)"
        case .responseTooLarge:
            return "Grok quota response was too large"
        }
    }
}

public struct GrokQuotaClient: Sendable {
    public static let endpoint = URL(string: "https://cli-chat-proxy.grok.com/v1/billing?format=credits")!
    public static let responseBodyLimit = 256 * 1024
    public static let requestTimeout: TimeInterval = 8

    private let transport: GrokQuotaHTTPTransport
    private let now: @Sendable () -> Date

    public init(
        transport: GrokQuotaHTTPTransport = URLSessionGrokQuotaTransport(),
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.transport = transport
        self.now = now
    }

    public func fetch(credentials: GrokCredentials) async throws -> GrokQuotaSnapshot {
        let request = makeRequest(credentials: credentials)
        let (data, response) = try await transport.data(for: request, bodyLimit: Self.responseBodyLimit)
        switch response.statusCode {
        case 200..<300:
            return try GrokQuotaParser.parse(
                data,
                now: now(),
                source: "grok-build-billing",
                accountDisplayName: credentials.displayName
            )
        case 401:
            throw GrokQuotaClientError.tokenExpired
        case 403:
            throw GrokQuotaClientError.forbidden
        case 429:
            throw GrokQuotaClientError.rateLimited
        default:
            throw GrokQuotaClientError.httpStatus(response.statusCode, decodeErrorMessage(from: data))
        }
    }

    private func makeRequest(credentials: GrokCredentials) -> URLRequest {
        var request = URLRequest(url: Self.endpoint)
        request.httpMethod = "GET"
        request.timeoutInterval = Self.requestTimeout
        request.setValue("Bearer \(credentials.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("xai-grok-cli", forHTTPHeaderField: "X-XAI-Token-Auth")
        request.setValue(credentials.userID, forHTTPHeaderField: "x-userid")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("AgentBar/menubar", forHTTPHeaderField: "User-Agent")
        return request
    }

    private func decodeErrorMessage(from data: Data) -> String {
        if let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let error = object["error"] as? [String: Any],
               let message = error["message"] as? String {
                return PrivacyScrubber.scrub(message)
            }
            if let error = object["error"] as? String {
                return PrivacyScrubber.scrub(error)
            }
            if let message = object["message"] as? String {
                return PrivacyScrubber.scrub(message)
            }
        }
        return PrivacyScrubber.scrub(String(data: data, encoding: .utf8) ?? "No response body")
    }
}

public struct URLSessionGrokQuotaTransport: GrokQuotaHTTPTransport {
    private let session: URLSession

    public init(session: URLSession = URLSessionGrokQuotaTransport.makeSession()) {
        self.session = session
    }

    public func data(for request: URLRequest, bodyLimit: Int) async throws -> (Data, HTTPURLResponse) {
        let (bytes, response) = try await session.bytes(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw GrokQuotaClientError.invalidResponse
        }

        var buffer: [UInt8] = []
        buffer.reserveCapacity(min(bodyLimit, 4096))
        for try await byte in bytes {
            guard buffer.count < bodyLimit else {
                throw GrokQuotaClientError.responseTooLarge
            }
            buffer.append(byte)
        }
        return (Data(buffer), http)
    }

    public static func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = GrokQuotaClient.requestTimeout
        configuration.timeoutIntervalForResource = GrokQuotaClient.requestTimeout
        configuration.waitsForConnectivity = false
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.urlCache = nil
        return URLSession(configuration: configuration)
    }
}
