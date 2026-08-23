import Foundation

public protocol GrokOIDCHTTPTransport: Sendable {
    func data(for request: URLRequest, bodyLimit: Int) async throws -> (Data, HTTPURLResponse)
}

public struct GrokTokenRefreshResult: Equatable, Sendable {
    public let accessToken: String
    public let refreshToken: String?
    public let expiresIn: TimeInterval?

    public init(accessToken: String, refreshToken: String?, expiresIn: TimeInterval?) {
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.expiresIn = expiresIn
    }
}

public enum GrokOIDCClientError: LocalizedError, Equatable {
    case invalidIssuer
    case invalidDiscoveryResponse
    case unsafeTokenEndpoint
    case invalidTokenResponse
    case requestFailed(Int, String)
    case responseTooLarge

    public var errorDescription: String? {
        switch self {
        case .invalidIssuer:
            return "Invalid Grok login issuer"
        case .invalidDiscoveryResponse:
            return "Invalid Grok login discovery response"
        case .unsafeTokenEndpoint:
            return "Grok login returned an unsafe token endpoint"
        case .invalidTokenResponse:
            return "Invalid Grok token refresh response"
        case let .requestFailed(status, message):
            return "Grok token refresh failed (HTTP \(status)): \(message)"
        case .responseTooLarge:
            return "Grok token refresh response was too large"
        }
    }
}

public struct GrokOIDCClient: Sendable {
    public static let requestTimeout: TimeInterval = 8
    public static let responseBodyLimit = 64 * 1024

    private let transport: any GrokOIDCHTTPTransport

    public init(transport: any GrokOIDCHTTPTransport = URLSessionGrokOIDCTransport()) {
        self.transport = transport
    }

    public func refresh(
        issuer: URL,
        clientID: String,
        refreshToken: String
    ) async throws -> GrokTokenRefreshResult {
        guard Self.isFirstPartyIssuer(issuer) else {
            throw GrokOIDCClientError.invalidIssuer
        }

        let discoveryURL = issuer
            .appendingPathComponent(".well-known", isDirectory: true)
            .appendingPathComponent("openid-configuration")
        var discoveryRequest = URLRequest(url: discoveryURL)
        discoveryRequest.timeoutInterval = Self.requestTimeout
        discoveryRequest.setValue("application/json", forHTTPHeaderField: "Accept")

        let (discoveryData, discoveryResponse) = try await transport.data(
            for: discoveryRequest,
            bodyLimit: Self.responseBodyLimit
        )
        guard 200..<300 ~= discoveryResponse.statusCode else {
            throw GrokOIDCClientError.requestFailed(
                discoveryResponse.statusCode,
                Self.decodeErrorMessage(from: discoveryData)
            )
        }
        guard let discovery = try? JSONSerialization.jsonObject(with: discoveryData) as? [String: Any],
              let endpointValue = Self.string(discovery["token_endpoint"]),
              let tokenEndpoint = URL(string: endpointValue) else {
            throw GrokOIDCClientError.invalidDiscoveryResponse
        }
        guard Self.isSafeTokenEndpoint(tokenEndpoint, issuer: issuer) else {
            throw GrokOIDCClientError.unsafeTokenEndpoint
        }

        var tokenRequest = URLRequest(url: tokenEndpoint)
        tokenRequest.httpMethod = "POST"
        tokenRequest.timeoutInterval = Self.requestTimeout
        tokenRequest.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        tokenRequest.setValue("application/json", forHTTPHeaderField: "Accept")
        var form = URLComponents()
        form.queryItems = [
            URLQueryItem(name: "grant_type", value: "refresh_token"),
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "refresh_token", value: refreshToken)
        ]
        tokenRequest.httpBody = form.percentEncodedQuery?.data(using: .utf8)

        let (tokenData, tokenResponse) = try await transport.data(
            for: tokenRequest,
            bodyLimit: Self.responseBodyLimit
        )
        guard 200..<300 ~= tokenResponse.statusCode else {
            throw GrokOIDCClientError.requestFailed(
                tokenResponse.statusCode,
                Self.decodeErrorMessage(from: tokenData)
            )
        }
        guard let payload = try? JSONSerialization.jsonObject(with: tokenData) as? [String: Any],
              let accessToken = Self.string(payload["access_token"]) else {
            throw GrokOIDCClientError.invalidTokenResponse
        }

        return GrokTokenRefreshResult(
            accessToken: accessToken,
            refreshToken: Self.string(payload["refresh_token"]),
            expiresIn: Self.timeInterval(payload["expires_in"])
        )
    }

    private static func isFirstPartyIssuer(_ url: URL) -> Bool {
        url.scheme?.lowercased() == "https"
            && url.host?.lowercased() == "auth.x.ai"
            && (url.port == nil || url.port == 443)
    }

    private static func isSafeTokenEndpoint(_ endpoint: URL, issuer: URL) -> Bool {
        endpoint.scheme?.lowercased() == "https"
            && endpoint.host?.lowercased() == issuer.host?.lowercased()
            && (endpoint.port == nil || endpoint.port == 443)
            && endpoint.user == nil
            && endpoint.password == nil
    }

    private static func string(_ value: Any?) -> String? {
        (value as? String)?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank
    }

    private static func timeInterval(_ value: Any?) -> TimeInterval? {
        if let number = value as? NSNumber {
            return number.doubleValue
        }
        if let string = string(value), let number = TimeInterval(string) {
            return number
        }
        return nil
    }

    private static func decodeErrorMessage(from data: Data) -> String {
        if let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let error = string(payload["error"]),
               error.range(of: #"^[A-Za-z0-9_.-]{1,64}$"#, options: .regularExpression) != nil {
                return error
            }
        }
        return "Request failed"
    }
}

public struct URLSessionGrokOIDCTransport: GrokOIDCHTTPTransport {
    private let session: URLSession

    public init(session: URLSession = URLSessionGrokOIDCTransport.makeSession()) {
        self.session = session
    }

    public func data(for request: URLRequest, bodyLimit: Int) async throws -> (Data, HTTPURLResponse) {
        let (bytes, response) = try await session.bytes(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw GrokOIDCClientError.invalidTokenResponse
        }

        var buffer: [UInt8] = []
        buffer.reserveCapacity(min(bodyLimit, 4096))
        for try await byte in bytes {
            guard buffer.count < bodyLimit else {
                throw GrokOIDCClientError.responseTooLarge
            }
            buffer.append(byte)
        }
        return (Data(buffer), http)
    }

    public static func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = GrokOIDCClient.requestTimeout
        configuration.timeoutIntervalForResource = GrokOIDCClient.requestTimeout
        configuration.waitsForConnectivity = false
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.urlCache = nil
        return URLSession(configuration: configuration)
    }
}

private extension String {
    var nilIfBlank: String? {
        isEmpty ? nil : self
    }
}
