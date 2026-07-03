import Foundation

public protocol CodexResetCreditsHTTPTransport: Sendable {
    func data(for request: URLRequest, bodyLimit: Int) async throws -> (Data, HTTPURLResponse)
}

public enum CodexResetCreditsClientError: LocalizedError, Equatable {
    case invalidResponse
    case tokenExpired
    case forbidden
    case rateLimited(String?)
    case httpStatus(Int, String)
    case decoding(String)
    case responseTooLarge

    public var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "Invalid reset credits response from chatgpt.com"
        case .tokenExpired:
            return "Token 失效,请重新登录 Codex Desktop"
        case .forbidden:
            return "Forbidden. Please relogin Codex Desktop"
        case let .rateLimited(retryAfter):
            if let retryAfter, !retryAfter.isEmpty {
                return "Reset credits query was rate limited. Retry after \(retryAfter)s"
            }
            return "Reset credits query was rate limited"
        case let .httpStatus(status, message):
            return "chatgpt.com returned HTTP \(status): \(message)"
        case let .decoding(message):
            return "Could not parse reset credits response: \(message)"
        case .responseTooLarge:
            return "Reset credits response was too large"
        }
    }
}

public struct CodexResetCreditsClient: Sendable {
    public static let bodyLimit = 64 * 1024
    public static let requestTimeout: TimeInterval = 20

    private static let resetCreditsURL = URL(string: "https://chatgpt.com/backend-api/wham/rate-limit-reset-credits")!

    private let transport: CodexResetCreditsHTTPTransport
    private let now: @Sendable () -> Date

    public init(
        transport: CodexResetCreditsHTTPTransport = URLSessionCodexResetCreditsTransport(),
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.transport = transport
        self.now = now
    }

    public func fetch(credentials: CodexCredentials) async throws -> CodexResetCreditsSnapshot {
        let request = request(credentials: credentials)
        let timestamp = now()
        let (data, response) = try await transport.data(for: request, bodyLimit: Self.bodyLimit)

        switch response.statusCode {
        case 200:
            return try CodexResetCreditsParser.parse(
                data,
                now: timestamp,
                source: "chatgpt.com/backend-api"
            )
        case 401:
            throw CodexResetCreditsClientError.tokenExpired
        case 403:
            throw CodexResetCreditsClientError.forbidden
        case 429:
            throw CodexResetCreditsClientError.rateLimited(response.value(forHTTPHeaderField: "Retry-After"))
        default:
            throw CodexResetCreditsClientError.httpStatus(
                response.statusCode,
                decodeErrorMessage(from: data)
            )
        }
    }

    private func request(credentials: CodexCredentials) -> URLRequest {
        var request = URLRequest(url: Self.resetCreditsURL)
        request.httpMethod = "GET"
        request.timeoutInterval = Self.requestTimeout
        request.setValue("Bearer \(credentials.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("Codex Desktop", forHTTPHeaderField: "originator")
        request.setValue("CODEX", forHTTPHeaderField: "OAI-Product-Sku")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("AgentBar/reset-credits", forHTTPHeaderField: "User-Agent")

        let accountID = accountIDFromAccessToken(credentials.accessToken)
            ?? credentials.accountID?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let accountID, !accountID.isEmpty {
            request.setValue(accountID, forHTTPHeaderField: "ChatGPT-Account-Id")
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

public struct URLSessionCodexResetCreditsTransport: CodexResetCreditsHTTPTransport {
    private let session: URLSession

    public init(session: URLSession = URLSessionCodexResetCreditsTransport.makeSession()) {
        self.session = session
    }

    public func data(for request: URLRequest, bodyLimit: Int) async throws -> (Data, HTTPURLResponse) {
        let (bytes, response) = try await session.bytes(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw CodexResetCreditsClientError.invalidResponse
        }

        var buffer: [UInt8] = []
        buffer.reserveCapacity(min(bodyLimit, 4096))
        for try await byte in bytes {
            guard buffer.count < bodyLimit else {
                throw CodexResetCreditsClientError.responseTooLarge
            }
            buffer.append(byte)
        }
        return (Data(buffer), http)
    }

    public static func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = CodexResetCreditsClient.requestTimeout
        configuration.timeoutIntervalForResource = CodexResetCreditsClient.requestTimeout
        configuration.waitsForConnectivity = false
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.urlCache = nil
        return URLSession(configuration: configuration)
    }
}

private func accountIDFromAccessToken(_ accessToken: String) -> String? {
    let pieces = accessToken.split(separator: ".")
    guard pieces.count >= 2,
          let data = Data(base64URLEncoded: String(pieces[1])),
          let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let auth = object["https://api.openai.com/auth"] as? [String: Any] else {
        return nil
    }
    return (auth["chatgpt_account_id"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank
}

private extension String {
    var nilIfBlank: String? {
        isEmpty ? nil : self
    }
}

private extension Data {
    init?(base64URLEncoded value: String) {
        var base64 = value
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let remainder = base64.count % 4
        if remainder > 0 {
            base64 += String(repeating: "=", count: 4 - remainder)
        }
        self.init(base64Encoded: base64)
    }
}
