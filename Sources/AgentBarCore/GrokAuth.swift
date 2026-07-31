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
    private let fileManager: FileManager
    private let environment: @Sendable () -> [String: String]
    private let homeDirectory: @Sendable () -> URL

    public init(
        fileManager: FileManager = .default,
        environment: @escaping @Sendable () -> [String: String] = { ProcessInfo.processInfo.environment },
        homeDirectory: @escaping @Sendable () -> URL = { FileManager.default.homeDirectoryForCurrentUser }
    ) {
        self.fileManager = fileManager
        self.environment = environment
        self.homeDirectory = homeDirectory
    }

    public func load() -> GrokAuthState {
        let url = authURL()
        guard fileManager.fileExists(atPath: url.path) else {
            return .notConfigured(url)
        }

        do {
            let data = try Data(contentsOf: url)
            guard let store = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                return .invalid("Invalid Grok auth file")
            }

            var sessionRecords: [(scope: String, record: [String: Any])] = []
            var hasAPIKey = false
            for (scope, value) in store {
                guard let record = value as? [String: Any] else { continue }
                let mode = Self.string(record["auth_mode"])?.lowercased() ?? ""
                if scope == "xai::api_key" || mode == "api_key" {
                    if Self.string(record["key"]) != nil { hasAPIKey = true }
                    continue
                }
                if Self.isFirstPartySession(scope: scope, record: record) {
                    sessionRecords.append((scope, record))
                }
            }

            let selected = sessionRecords.max { lhs, rhs in
                (Self.string(lhs.record["create_time"]) ?? "") < (Self.string(rhs.record["create_time"]) ?? "")
            }
            if let record = selected?.record,
               let accessToken = Self.string(record["key"]),
               let userID = Self.string(record["user_id"]) {
                let displayName = Self.string(record["email"])
                    ?? [Self.string(record["first_name"]), Self.string(record["last_name"])]
                        .compactMap { $0 }
                        .joined(separator: " ")
                        .nilIfBlank
                return .credentials(
                    GrokCredentials(
                        accessToken: accessToken,
                        userID: userID,
                        displayName: displayName
                    )
                )
            }

            return hasAPIKey ? .unsupportedAPIKey : .notLoggedIn
        } catch {
            return .invalid(PrivacyScrubber.scrub(error.localizedDescription))
        }
    }

    public func authURL() -> URL {
        if let grokHome = environment()["GROK_HOME"]?.trimmingCharacters(in: .whitespacesAndNewlines),
           !grokHome.isEmpty {
            return URL(fileURLWithPath: grokHome, isDirectory: true).appendingPathComponent("auth.json")
        }
        return homeDirectory().appendingPathComponent(".grok", isDirectory: true).appendingPathComponent("auth.json")
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
}

private extension String {
    var nilIfBlank: String? {
        isEmpty ? nil : self
    }
}
