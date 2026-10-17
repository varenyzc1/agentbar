import CryptoKit
import Foundation
import LocalAuthentication
import Security

public struct ClaudeCredentials: Equatable, Sendable {
    public let accessToken: String
    public let expiresAt: Date?
    public let plan: String?

    public init(accessToken: String, expiresAt: Date? = nil, plan: String? = nil) {
        self.accessToken = accessToken
        self.expiresAt = expiresAt
        self.plan = plan
    }

    /// A cache discriminator, never the token itself. Rotation deliberately invalidates old snapshots.
    public var cacheIdentity: String {
        SHA256.hash(data: Data("agentbar:claude:\(accessToken)".utf8))
            .map { String(format: "%02x", $0) }.joined()
    }
}

public enum ClaudeAuthState: Equatable, Sendable {
    case credentials(ClaudeCredentials)
    case notLoggedIn
    case expired
    case missingScope
    case keychainAccessRequired
    case invalid
}

public enum ClaudeKeychainError: Error {
    case accessDenied
}

/// Reads Claude Code-owned credentials without rotating or overwriting them.
public struct ClaudeAuthLoader: Sendable {
    private let environment: @Sendable () -> [String: String]
    private let homeDirectory: URL
    private let now: @Sendable () -> Date
    private let readKeychain: @Sendable (String, Bool) throws -> Data?

    public init(
        environment: @escaping @Sendable () -> [String: String] = { ProcessInfo.processInfo.environment },
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
        now: @escaping @Sendable () -> Date = { Date() },
        readKeychain: @escaping @Sendable (String, Bool) throws -> Data? = { try ClaudeAuthLoader.readKeychain(service: $0, allowInteraction: $1) }
    ) {
        self.environment = environment
        self.homeDirectory = homeDirectory
        self.now = now
        self.readKeychain = readKeychain
    }

    public var configDirectory: URL {
        let env = environment()
        let path = env["CLAUDE_SECURESTORAGE_CONFIG_DIR"] ?? env["CLAUDE_CONFIG_DIR"] ?? ""
        guard !path.isEmpty else { return homeDirectory.appendingPathComponent(".claude") }
        let expanded = path.hasPrefix("~/") ? homeDirectory.appendingPathComponent(String(path.dropFirst(2))).path : path
        return URL(fileURLWithPath: expanded, isDirectory: true).standardizedFileURL
    }

    public var keychainService: String {
        let directory = configDirectory.standardizedFileURL
        if directory == homeDirectory.appendingPathComponent(".claude").standardizedFileURL {
            return "Claude Code-credentials"
        }
        let hash = SHA256.hash(data: Data(directory.path.precomposedStringWithCanonicalMapping.utf8))
            .map { String(format: "%02x", $0) }.joined().prefix(8)
        return "Claude Code-credentials-\(hash)"
    }

    public func load(allowInteraction: Bool = false) -> ClaudeAuthState {
        do {
            if let data = try readKeychain(keychainService, allowInteraction) {
                // A present Keychain entry is authoritative; never fall back to a different stale login.
                return parse(data)
            }
        } catch {
            return .keychainAccessRequired
        }
        let file = configDirectory.appendingPathComponent(".credentials.json")
        guard FileManager.default.fileExists(atPath: file.path) else { return .notLoggedIn }
        guard let data = try? Data(contentsOf: file), data.count <= 1_048_576 else { return .invalid }
        return parse(data)
    }

    private func parse(_ data: Data) -> ClaudeAuthState {
        guard data.count <= 1_048_576,
              let root = try? JSONDecoder().decode(CredentialFile.self, from: data) else { return .invalid }
        guard let oauth = root.claudeAiOauth,
              let token = oauth.accessToken?.trimmingCharacters(in: .whitespacesAndNewlines),
              !token.isEmpty, !token.contains(where: { $0.isWhitespace }) else { return .notLoggedIn }
        if let scopes = oauth.scopes, !scopes.contains("user:profile") { return .missingScope }
        let expiresAt = oauth.expiresAt.map { Date(timeIntervalSince1970: $0 / 1000) }
        if let expiresAt, expiresAt <= now() { return .expired }
        return .credentials(ClaudeCredentials(accessToken: token, expiresAt: expiresAt, plan: oauth.subscriptionType))
    }

    public static func readKeychain(service: String, allowInteraction: Bool) throws -> Data? {
        let context = LAContext()
        context.interactionNotAllowed = !allowInteraction
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecReturnData as String: true,
            kSecUseAuthenticationContext as String: context
        ]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data else { throw ClaudeKeychainError.accessDenied }
        return data
    }

    private struct CredentialFile: Decodable {
        let claudeAiOauth: OAuth?
        struct OAuth: Decodable {
            let accessToken: String?
            let expiresAt: Double?
            let scopes: [String]?
            let subscriptionType: String?
        }
    }
}
