import Foundation

public struct GrokCredentials: Equatable, Sendable {
    public let accessToken: String
    public let userID: String
    public let displayName: String?

    public init(accessToken: String, userID: String, displayName: String?) {
        self.accessToken = accessToken
        self.userID = userID
        self.displayName = displayName
    }
}

public enum GrokAuthState: Equatable, Sendable {
    case credentials(GrokCredentials)
    case unsupportedAPIKey
    case notLoggedIn
    case notConfigured(URL)
    case invalid(String)
}

public struct GrokAuthLoader {
    public static let refreshBuffer: TimeInterval = 5 * 60

    private let fileManager: FileManager
    private let environment: @Sendable () -> [String: String]
    private let homeDirectory: @Sendable () -> URL
    private let now: @Sendable () -> Date
    private let refreshCredentials: @Sendable (URL, String, String) async throws -> GrokTokenRefreshResult

    public init(
        fileManager: FileManager = .default,
        environment: @escaping @Sendable () -> [String: String] = { ProcessInfo.processInfo.environment },
        homeDirectory: @escaping @Sendable () -> URL = { FileManager.default.homeDirectoryForCurrentUser },
        now: @escaping @Sendable () -> Date = { Date() },
        refreshCredentials: @escaping @Sendable (URL, String, String) async throws -> GrokTokenRefreshResult = { issuer, clientID, refreshToken in
            try await GrokOIDCClient().refresh(
                issuer: issuer,
                clientID: clientID,
                refreshToken: refreshToken
            )
        }
    ) {
        self.fileManager = fileManager
        self.environment = environment
        self.homeDirectory = homeDirectory
        self.now = now
        self.refreshCredentials = refreshCredentials
    }

    public func load() -> GrokAuthState {
        loadSession().state
    }

    public func loadRefreshingIfNeeded(force: Bool = false) async -> GrokAuthState {
        let loaded = loadSession()
        guard let session = loaded.session else { return loaded.state }
        let shouldRefresh = force
            || session.expiresAt.map { $0.timeIntervalSince(now()) <= Self.refreshBuffer } == true
        guard shouldRefresh else { return loaded.state }
        guard let issuer = session.issuer,
              issuer.absoluteString.lowercased() == "https://auth.x.ai",
              let clientID = session.clientID,
              let refreshToken = session.refreshToken else {
            return force ? .invalid("Grok login expired. Run grok login") : loaded.state
        }

        do {
            let refreshed = try await refreshCredentials(issuer, clientID, refreshToken)
            return try persist(
                refreshed,
                replacing: session,
                at: authURL(),
                refreshedAt: now()
            )
        } catch {
            if !force, let expiresAt = session.expiresAt, expiresAt > now() {
                return loaded.state
            }
            return .invalid(
                "Could not refresh Grok login: \(PrivacyScrubber.scrub(error.localizedDescription))"
            )
        }
    }

    public func authURL() -> URL {
        if let grokHome = environment()["GROK_HOME"]?.trimmingCharacters(in: .whitespacesAndNewlines),
           !grokHome.isEmpty {
            return URL(fileURLWithPath: grokHome, isDirectory: true).appendingPathComponent("auth.json")
        }
        return homeDirectory().appendingPathComponent(".grok", isDirectory: true).appendingPathComponent("auth.json")
    }

    private func loadSession() -> LoadedGrokAuth {
        let url = authURL()
        guard fileManager.fileExists(atPath: url.path) else {
            return LoadedGrokAuth(state: .notConfigured(url), session: nil)
        }

        do {
            let store = try readStore(at: url)
            let records = Self.sessionRecords(in: store)
            let hasAPIKey = Self.hasAPIKey(in: store)
            let selected = records.max { lhs, rhs in
                (Self.string(lhs.record["create_time"]) ?? "") < (Self.string(rhs.record["create_time"]) ?? "")
            }
            if let selected,
               let accessToken = Self.string(selected.record["key"]),
               let userID = Self.string(selected.record["user_id"]) {
                let record = selected.record
                let displayName = Self.string(record["email"])
                    ?? [Self.string(record["first_name"]), Self.string(record["last_name"])]
                        .compactMap { $0 }
                        .joined(separator: " ")
                        .nilIfBlank
                let credentials = GrokCredentials(
                    accessToken: accessToken,
                    userID: userID,
                    displayName: displayName
                )
                return LoadedGrokAuth(
                    state: .credentials(credentials),
                    session: GrokAuthSession(
                        scope: selected.scope,
                        credentials: credentials,
                        expiresAt: Self.date(record["expires_at"]),
                        issuer: Self.string(record["oidc_issuer"]).flatMap(URL.init(string:)),
                        clientID: Self.string(record["oidc_client_id"]),
                        refreshToken: Self.string(record["refresh_token"])
                    )
                )
            }

            return LoadedGrokAuth(state: hasAPIKey ? .unsupportedAPIKey : .notLoggedIn, session: nil)
        } catch {
            return LoadedGrokAuth(
                state: .invalid(PrivacyScrubber.scrub(error.localizedDescription)),
                session: nil
            )
        }
    }

    private func persist(
        _ refreshed: GrokTokenRefreshResult,
        replacing session: GrokAuthSession,
        at url: URL,
        refreshedAt: Date
    ) throws -> GrokAuthState {
        var store = try readStore(at: url)
        guard var record = store[session.scope] as? [String: Any] else {
            return load()
        }
        guard Self.string(record["key"]) == session.credentials.accessToken,
              Self.string(record["refresh_token"]) == session.refreshToken else {
            return load()
        }

        record["key"] = refreshed.accessToken
        if let rotatedRefreshToken = refreshed.refreshToken {
            record["refresh_token"] = rotatedRefreshToken
        }
        if let expiresIn = refreshed.expiresIn, expiresIn > 0 {
            record["expires_at"] = Self.iso8601String(from: refreshedAt.addingTimeInterval(expiresIn))
        } else if let expiresAt = Self.jwtExpiration(refreshed.accessToken) {
            record["expires_at"] = Self.iso8601String(from: expiresAt)
        } else {
            record.removeValue(forKey: "expires_at")
        }
        store[session.scope] = record

        let permissions = try? fileManager.attributesOfItem(atPath: url.path)[.posixPermissions]
        let data = try JSONSerialization.data(withJSONObject: store, options: [.sortedKeys])
        try data.write(to: url, options: .atomic)
        if let permissions {
            try? fileManager.setAttributes([.posixPermissions: permissions], ofItemAtPath: url.path)
        }
        return load()
    }

    private func readStore(at url: URL) throws -> [String: Any] {
        let data = try Data(contentsOf: url)
        guard let store = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw GrokAuthFileError.invalid
        }
        return store
    }

    private static func sessionRecords(in store: [String: Any]) -> [(scope: String, record: [String: Any])] {
        store.compactMap { scope, value in
            guard let record = value as? [String: Any],
                  isFirstPartySession(scope: scope, record: record) else { return nil }
            return (scope, record)
        }
    }

    private static func hasAPIKey(in store: [String: Any]) -> Bool {
        store.contains { scope, value in
            guard let record = value as? [String: Any] else { return false }
            let mode = string(record["auth_mode"])?.lowercased() ?? ""
            return (scope == "xai::api_key" || mode == "api_key") && string(record["key"]) != nil
        }
    }

    private static func isFirstPartySession(scope: String, record: [String: Any]) -> Bool {
        let mode = string(record["auth_mode"])?.lowercased() ?? ""
        guard ["oidc", "external", "web_login", "grok"].contains(mode) else { return false }
        let issuer = string(record["oidc_issuer"])?.lowercased()
        return issuer == "https://auth.x.ai"
            || scope.lowercased().hasPrefix("https://auth.x.ai::")
            || mode == "web_login"
            || mode == "grok"
    }

    private static func string(_ value: Any?) -> String? {
        (value as? String)?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank
    }

    private static func date(_ value: Any?) -> Date? {
        guard let value = string(value) else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: value) ?? ISO8601DateFormatter().date(from: value)
    }

    private static func iso8601String(from date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }

    private static func jwtExpiration(_ token: String) -> Date? {
        let parts = token.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 3 else { return nil }
        var value = String(parts[1]).replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        value += String(repeating: "=", count: (4 - value.count % 4) % 4)
        guard let data = Data(base64Encoded: value),
              let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let expiration = payload["exp"] as? NSNumber else { return nil }
        return Date(timeIntervalSince1970: expiration.doubleValue)
    }
}

private struct LoadedGrokAuth {
    let state: GrokAuthState
    let session: GrokAuthSession?
}

private struct GrokAuthSession {
    let scope: String
    let credentials: GrokCredentials
    let expiresAt: Date?
    let issuer: URL?
    let clientID: String?
    let refreshToken: String?
}

private enum GrokAuthFileError: LocalizedError {
    case invalid

    var errorDescription: String? { "Invalid Grok auth file" }
}

private extension String {
    var nilIfBlank: String? {
        isEmpty ? nil : self
    }
}
