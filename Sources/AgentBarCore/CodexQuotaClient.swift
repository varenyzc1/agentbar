import Foundation

public protocol CodexQuotaHTTPTransport: Sendable {
    func data(for request: URLRequest, bodyLimit: Int) async throws -> (Data, HTTPURLResponse)
}

public enum CodexQuotaClientError: LocalizedError, Equatable {
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
            return "Invalid response from chatgpt.com"
        case .tokenExpired:
            return "Token 失效,请重新运行 codex login"
        case .forbidden:
            return "Forbidden"
        case .rateLimited:
            return "Rate limited, try again in a minute"
        case let .httpStatus(status, message):
            return "chatgpt.com returned HTTP \(status): \(message)"
        case let .decoding(message):
            return "Could not parse quota response: \(message)"
        case .responseTooLarge:
            return "Quota response was too large"
        }
    }
}

public struct CodexQuotaClient: Sendable {
    public static let bodyLimit = 64 * 1024

    private static let primaryURL = URL(string: "https://chatgpt.com/backend-api/wham/usage")!
    private static let fallbackURL = URL(string: "https://chatgpt.com/api/codex/usage")!

    private let transport: CodexQuotaHTTPTransport
    private let now: @Sendable () -> Date

    public init(
        transport: CodexQuotaHTTPTransport = URLSessionCodexQuotaTransport(),
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.transport = transport
        self.now = now
    }

    public func fetch(credentials: CodexCredentials, force: Bool = false) async throws -> CodexQuotaSnapshot {
        let timestamp = now()
        do {
            return try await fetch(
                url: Self.primaryURL,
                source: "chatgpt.com/backend-api",
                credentials: credentials,
                force: force,
                timestamp: timestamp
            )
        } catch let error as CodexQuotaHTTPStatus where error.statusCode == 404 {
            do {
                return try await fetch(
                    url: Self.fallbackURL,
                    source: "chatgpt.com/api/codex",
                    credentials: credentials,
                    force: force,
                    timestamp: timestamp
                )
            } catch let fallbackError as CodexQuotaHTTPStatus {
                throw CodexQuotaClientError.httpStatus(fallbackError.statusCode, "Not found")
            }
        } catch let error as CodexQuotaHTTPStatus {
            throw CodexQuotaClientError.httpStatus(error.statusCode, "Not found")
        }
    }

    private func fetch(
        url: URL,
        source: String,
        credentials: CodexCredentials,
        force: Bool,
        timestamp: Date
    ) async throws -> CodexQuotaSnapshot {
        let request = try request(
            url: url,
            credentials: credentials,
            force: force
        )
        let (data, response) = try await transport.data(for: request, bodyLimit: Self.bodyLimit)
        switch response.statusCode {
        case 200:
            return try CodexQuotaParser.parse(
                data,
                now: timestamp,
                source: source,
                accountDisplayName: credentials.displayName
            )
        case 404:
            throw CodexQuotaHTTPStatus(statusCode: 404)
        case 401:
            throw CodexQuotaClientError.tokenExpired
        case 403:
            throw CodexQuotaClientError.forbidden
        case 429:
            throw CodexQuotaClientError.rateLimited
        default:
            throw CodexQuotaClientError.httpStatus(
                response.statusCode,
                decodeErrorMessage(from: data)
            )
        }
    }

    private func request(url: URL, credentials: CodexCredentials, force: Bool) throws -> URLRequest {
        var finalURL = url
        if force {
            guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
                throw CodexQuotaClientError.invalidResponse
            }
            var items = components.queryItems ?? []
            items.append(URLQueryItem(name: "force", value: "1"))
            components.queryItems = items
            guard let componentURL = components.url else {
                throw CodexQuotaClientError.invalidResponse
            }
            finalURL = componentURL
        }

        var request = URLRequest(url: finalURL)
        request.httpMethod = "GET"
        request.timeoutInterval = 8
        request.setValue("Bearer \(credentials.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("AgentBar/menubar", forHTTPHeaderField: "User-Agent")
        if let accountID = credentials.accountID?.trimmingCharacters(in: .whitespacesAndNewlines),
           !accountID.isEmpty {
            request.setValue(accountID, forHTTPHeaderField: "X-Account-Id")
            request.setValue(accountID, forHTTPHeaderField: "ChatGPT-Account-Id")
            request.setValue(accountID, forHTTPHeaderField: "ChatClaude-Account-Id")
        }
        return request
    }

    private func decodeErrorMessage(from data: Data) -> String {
        if let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let error = object["error"] as? [String: Any],
               let message = error["message"] as? String {
                return PrivacyScrubber.scrub(message)
            }
            if let message = object["message"] as? String {
                return PrivacyScrubber.scrub(message)
            }
        }
        return PrivacyScrubber.scrub(String(data: data, encoding: .utf8) ?? "No response body")
    }
}

private struct CodexQuotaHTTPStatus: Error {
    let statusCode: Int
}

public struct URLSessionCodexQuotaTransport: CodexQuotaHTTPTransport {
    private let session: URLSession

    public init(session: URLSession = URLSessionCodexQuotaTransport.makeSession()) {
        self.session = session
    }

    public func data(for request: URLRequest, bodyLimit: Int) async throws -> (Data, HTTPURLResponse) {
        let (bytes, response) = try await session.bytes(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw CodexQuotaClientError.invalidResponse
        }

        var buffer: [UInt8] = []
        buffer.reserveCapacity(min(bodyLimit, 4096))
        for try await byte in bytes {
            guard buffer.count < bodyLimit else {
                throw CodexQuotaClientError.responseTooLarge
            }
            buffer.append(byte)
        }
        return (Data(buffer), http)
    }

    public static func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 8
        configuration.timeoutIntervalForResource = 8
        configuration.waitsForConnectivity = false
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.urlCache = nil
        return URLSession(configuration: configuration)
    }
}
