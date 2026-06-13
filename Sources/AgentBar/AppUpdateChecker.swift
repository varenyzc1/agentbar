import Foundation

struct AppVersion {
    let shortVersion: String
    let build: String

    static var current: AppVersion {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String
        return AppVersion(
            shortVersion: clean(version) ?? "0.0.0",
            build: clean(build) ?? "0"
        )
    }

    var displayText: String {
        "AgentBar \(shortVersion) (\(build))"
    }

    static func isNewer(_ candidate: String, than current: String) -> Bool {
        compare(candidate, current) == .orderedDescending
    }

    private static func compare(_ lhs: String, _ rhs: String) -> ComparisonResult {
        let left = components(lhs)
        let right = components(rhs)
        let count = max(left.count, right.count)

        for index in 0..<count {
            let leftValue = index < left.count ? left[index] : 0
            let rightValue = index < right.count ? right[index] : 0
            if leftValue > rightValue { return .orderedDescending }
            if leftValue < rightValue { return .orderedAscending }
        }

        return .orderedSame
    }

    private static func components(_ version: String) -> [Int] {
        clean(version)?
            .split(separator: ".")
            .map { part in
                let digits = part.prefix { $0.isNumber }
                return Int(digits) ?? 0
            } ?? []
    }

    private static func clean(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let cleaned = trimmed.hasPrefix("v") ? String(trimmed.dropFirst()) : trimmed
        return cleaned.isEmpty ? nil : cleaned
    }
}

struct AppRelease: Equatable {
    let version: String
    let url: URL
}

enum AppUpdateCheckerError: LocalizedError {
    case invalidResponse
    case httpStatus(Int)
    case invalidRelease

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "Invalid response from GitHub"
        case let .httpStatus(status):
            return "GitHub returned HTTP \(status)"
        case .invalidRelease:
            return "Could not parse latest release"
        }
    }
}

struct AppUpdateChecker {
    private static let latestReleaseURL = URL(string: "https://api.github.com/repos/varenyzc1/agentbar/releases/latest")!
    private let session: URLSession

    init(session: URLSession = AppUpdateChecker.makeSession()) {
        self.session = session
    }

    func latestRelease() async throws -> AppRelease {
        var request = URLRequest(url: Self.latestReleaseURL)
        request.httpMethod = "GET"
        request.timeoutInterval = 8
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("AgentBar/update-checker", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw AppUpdateCheckerError.invalidResponse
        }

        guard (200..<300).contains(http.statusCode) else {
            throw AppUpdateCheckerError.httpStatus(http.statusCode)
        }

        let release = try JSONDecoder().decode(GitHubRelease.self, from: data)
        guard let version = AppVersion.cleanTag(release.tagName),
              let url = URL(string: release.htmlURL) else {
            throw AppUpdateCheckerError.invalidRelease
        }
        return AppRelease(version: version, url: url)
    }

    static func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 8
        configuration.timeoutIntervalForResource = 8
        configuration.waitsForConnectivity = false
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.urlCache = nil
        return URLSession(configuration: configuration)
    }
}

private struct GitHubRelease: Decodable {
    let tagName: String
    let htmlURL: String

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case htmlURL = "html_url"
    }
}

private extension AppVersion {
    static func cleanTag(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let cleaned = trimmed.hasPrefix("v") ? String(trimmed.dropFirst()) : trimmed
        return cleaned.isEmpty ? nil : cleaned
    }
}
