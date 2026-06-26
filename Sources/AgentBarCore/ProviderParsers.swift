import Foundation

public protocol ProviderParser {
    var sourceID: String { get }
    var scanRoots: [URL] { get }
    var supportsAppendOnlyParsing: Bool { get }

    func shouldParseFile(_ url: URL) -> Bool
    func parseFile(at url: URL, fromOffset: Int64?) throws -> [TokenEntry]
}

public extension ProviderParser {
    var supportsAppendOnlyParsing: Bool { true }
}

public struct ClaudeCodeParser: ProviderParser {
    public let sourceID = "claude-code"
    private let homeDirectory: URL

    public init(homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser) {
        self.homeDirectory = homeDirectory
    }

    public var scanRoots: [URL] {
        [homeDirectory.appendingPathComponent(".claude/projects", isDirectory: true)]
    }

    public func shouldParseFile(_ url: URL) -> Bool {
        url.pathExtension.lowercased() == "jsonl"
    }

    public func parseFile(at url: URL, fromOffset: Int64?) throws -> [TokenEntry] {
        let rows = try JSONLineReader.objects(at: url, fromOffset: fromOffset)
        let project = Self.projectName(from: url)
        let fallbackDate = ProviderJSON.fileModificationDate(url) ?? Date()

        return rows.compactMap { row in
            guard ProviderJSON.string(row.object, "type") == "assistant" else { return nil }
            let message = ProviderJSON.dictionary(row.object["message"]) ?? row.object
            let usage = ProviderJSON.dictionary(message["usage"]) ?? [:]
            let model = ProviderJSON.string(message, "model") ?? "unknown"
            let timestamp = ProviderJSON.date(row.object["timestamp"])
                ?? ProviderJSON.date(message["timestamp"])
                ?? fallbackDate

            let outputRaw = ProviderJSON.int64(usage, "output_tokens")
            let reportedReasoning = ProviderJSON.int64(usage, "reasoning_output_tokens")
            let reasoning: Int64
            let output: Int64
            if reportedReasoning > 0 {
                reasoning = min(reportedReasoning, outputRaw)
                output = max(0, outputRaw - reasoning)
            } else {
                reasoning = Self.estimatedThinkingTokens(outputTokens: outputRaw, content: message["content"])
                output = max(0, outputRaw - reasoning)
            }

            let messageID = ProviderJSON.string(message, "id")
                ?? "\(url.path):\(row.lineNumber):\(model):\(outputRaw)"

            return TokenEntry(
                source: sourceID,
                model: model,
                project: project,
                timestamp: timestamp,
                inputTokens: ProviderJSON.int64(usage, "input_tokens"),
                outputTokens: output,
                cachedInputTokens: ProviderJSON.int64(usage, "cache_read_input_tokens"),
                cacheCreationInputTokens: ProviderJSON.int64(usage, "cache_creation_input_tokens"),
                reasoningOutputTokens: reasoning,
                dedupKey: "\(sourceID):\(messageID)"
            )
        }
    }

    private static func projectName(from url: URL) -> String {
        let encoded = url.deletingLastPathComponent().lastPathComponent
        if encoded.isEmpty { return "unknown" }

        let decoded = encoded.removingPercentEncoding ?? encoded
        let pieces = decoded.split(separator: "-").filter { !$0.isEmpty }
        return pieces.last.map(String.init) ?? decoded
    }

    private static func estimatedThinkingTokens(outputTokens: Int64, content: Any?) -> Int64 {
        guard outputTokens > 0, let items = content as? [Any] else { return 0 }

        var thinkingCharacters = 0
        var visibleCharacters = 0

        for item in items {
            guard let dict = ProviderJSON.dictionary(item) else { continue }
            let type = ProviderJSON.string(dict, "type") ?? ""
            let count = ProviderJSON.characterCount(dict["text"] ?? dict["thinking"] ?? dict["input"] ?? dict["content"])
            if type == "thinking" || type == "redacted_thinking" {
                thinkingCharacters += count
            } else {
                visibleCharacters += max(1, count)
            }
        }

        guard thinkingCharacters > 0 else { return 0 }
        let totalCharacters = max(1, thinkingCharacters + visibleCharacters)
        let estimated = (Double(outputTokens) * Double(thinkingCharacters) / Double(totalCharacters)).rounded()
        return min(outputTokens, max(0, Int64(estimated)))
    }
}

public struct CodexSessionParser: ProviderParser {
    public let sourceID = "codex"
    private let environment: @Sendable () -> [String: String]
    private let homeDirectory: URL

    public init(
        environment: @escaping @Sendable () -> [String: String] = { ProcessInfo.processInfo.environment },
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
    ) {
        self.environment = environment
        self.homeDirectory = homeDirectory
    }

    public var scanRoots: [URL] {
        let root = environment()["CODEX_HOME"].map { URL(fileURLWithPath: $0, isDirectory: true) }
            ?? homeDirectory.appendingPathComponent(".codex", isDirectory: true)
        return [
            root.appendingPathComponent("sessions", isDirectory: true),
            root.appendingPathComponent("archived_sessions", isDirectory: true)
        ]
    }

    public func shouldParseFile(_ url: URL) -> Bool {
        url.pathExtension.lowercased() == "jsonl"
    }

    public func parseFile(at url: URL, fromOffset: Int64?) throws -> [TokenEntry] {
        let project = (try? Self.projectName(in: url)) ?? "unknown"
        let rows = try JSONLineReader.objects(at: url, fromOffset: fromOffset)
        let metadataRows = fromOffset == nil ? rows : (try? JSONLineReader.objects(at: url, fromOffset: nil)) ?? rows
        let fallbackDate = ProviderJSON.fileModificationDate(url) ?? Date()
        let fallbackModel = Self.modelName(in: metadataRows) ?? "unknown"

        return rows.compactMap { row in
            guard ProviderJSON.string(row.object, "type") == "event_msg",
                  let payload = ProviderJSON.dictionary(row.object["payload"]),
                  ProviderJSON.string(payload, "type") == "token_count",
                  let info = ProviderJSON.dictionary(payload["info"]),
                  let usage = ProviderJSON.dictionary(info["last_token_usage"]) else {
                return nil
            }

            let model = ProviderJSON.string(info, "model")
                ?? ProviderJSON.string(row.object, "model")
                ?? fallbackModel
            let timestamp = ProviderJSON.date(row.object["timestamp"])
                ?? ProviderJSON.date(payload["timestamp"])
                ?? ProviderJSON.date(info["timestamp"])
                ?? fallbackDate

            let inputRaw = ProviderJSON.int64(usage, "input_tokens")
            let outputRaw = ProviderJSON.int64(usage, "output_tokens")
            let cachedRaw = ProviderJSON.int64(usage, "cached_input_tokens")
            let cacheCreateRaw = ProviderJSON.int64(usage, "cache_creation_input_tokens")
            let reasoningRaw = ProviderJSON.int64(usage, "reasoning_output_tokens")
            let totalRaw = ProviderJSON.int64(usage, "total_tokens")
            let normalized = ProviderJSON.normalizedOverlappingTokens(
                inputRaw: inputRaw,
                outputRaw: outputRaw,
                cachedRaw: cachedRaw,
                cacheCreateRaw: cacheCreateRaw,
                reasoningRaw: reasoningRaw
            )

            return TokenEntry(
                source: sourceID,
                model: model,
                project: project,
                timestamp: timestamp,
                inputTokens: normalized.input,
                outputTokens: normalized.output,
                cachedInputTokens: normalized.cached,
                cacheCreationInputTokens: normalized.cacheCreate,
                reasoningOutputTokens: normalized.reasoning,
                dedupKey: "\(sourceID):\(model):\(inputRaw):\(outputRaw):\(cachedRaw):\(cacheCreateRaw):\(reasoningRaw):\(totalRaw)"
            )
        }
    }

    private static func projectName(in url: URL) throws -> String {
        let rows = try JSONLineReader.objects(at: url, fromOffset: nil)
        for row in rows {
            guard ProviderJSON.string(row.object, "type") == "session_meta",
                  let payload = ProviderJSON.dictionary(row.object["payload"]),
                  let cwd = ProviderJSON.string(payload, "cwd") else {
                continue
            }
            let name = URL(fileURLWithPath: cwd, isDirectory: true).lastPathComponent
            return name.isEmpty ? "unknown" : name
        }
        return "unknown"
    }

    private static func modelName(in rows: [JSONLineObject]) -> String? {
        for row in rows {
            if let model = ProviderJSON.firstStringValue(
                in: row.object,
                keys: ["model", "model_slug", "model_id", "modelName"]
            ), !ProviderJSON.isUnknownModel(model) {
                return model
            }
        }
        return nil
    }
}

public struct GeminiCLIParser: ProviderParser {
    public let sourceID = "gemini-cli"
    public let supportsAppendOnlyParsing = false
    private let homeDirectory: URL

    public init(homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser) {
        self.homeDirectory = homeDirectory
    }

    public var scanRoots: [URL] {
        [homeDirectory.appendingPathComponent(".gemini/tmp", isDirectory: true)]
    }

    public func shouldParseFile(_ url: URL) -> Bool {
        url.pathExtension.lowercased() == "json"
    }

    public func parseFile(at url: URL, fromOffset: Int64?) throws -> [TokenEntry] {
        let data = try Data(contentsOf: url)
        let object = try JSONSerialization.jsonObject(with: data)
        let project = Self.projectName(from: url)
        let fallbackDate = ProviderJSON.fileModificationDate(url) ?? Date()
        var entries: [TokenEntry] = []
        var index = 0
        visit(
            object,
            url: url,
            project: project,
            model: "unknown",
            timestamp: fallbackDate,
            index: &index,
            entries: &entries
        )
        return entries
    }

    private func visit(
        _ value: Any,
        url: URL,
        project: String,
        model inheritedModel: String,
        timestamp inheritedTimestamp: Date,
        index: inout Int,
        entries: inout [TokenEntry]
    ) {
        if let array = value as? [Any] {
            for item in array {
                visit(item, url: url, project: project, model: inheritedModel, timestamp: inheritedTimestamp, index: &index, entries: &entries)
            }
            return
        }

        guard let dict = ProviderJSON.dictionary(value) else { return }
        let model = ProviderJSON.string(dict, "model", "modelName", "name") ?? inheritedModel
        let timestamp = ProviderJSON.date(dict["timestamp"])
            ?? ProviderJSON.date(dict["createdAt"])
            ?? ProviderJSON.date(dict["startTime"])
            ?? ProviderJSON.date(dict["time"])
            ?? inheritedTimestamp

        if let tokens = ProviderJSON.dictionary(dict["tokens"]) {
            appendGeminiEntry(
                usage: tokens,
                url: url,
                project: project,
                model: model,
                timestamp: timestamp,
                inputKey: "input",
                outputKey: "output",
                cachedKey: "cached",
                thoughtsKey: "thoughts",
                index: &index,
                entries: &entries
            )
        }

        if let usage = ProviderJSON.dictionary(dict["usageMetadata"]) {
            appendGeminiEntry(
                usage: usage,
                url: url,
                project: project,
                model: model,
                timestamp: timestamp,
                inputKey: "promptTokenCount",
                outputKey: "candidatesTokenCount",
                cachedKey: "cachedContentTokenCount",
                thoughtsKey: "thoughtsTokenCount",
                index: &index,
                entries: &entries
            )
        }

        for child in dict.values {
            visit(child, url: url, project: project, model: model, timestamp: timestamp, index: &index, entries: &entries)
        }
    }

    private func appendGeminiEntry(
        usage: [String: Any],
        url: URL,
        project: String,
        model: String,
        timestamp: Date,
        inputKey: String,
        outputKey: String,
        cachedKey: String,
        thoughtsKey: String,
        index: inout Int,
        entries: inout [TokenEntry]
    ) {
        let inputRaw = ProviderJSON.int64(usage, inputKey)
        let outputRaw = ProviderJSON.int64(usage, outputKey)
        let cachedRaw = ProviderJSON.int64(usage, cachedKey)
        let thoughtsRaw = ProviderJSON.int64(usage, thoughtsKey)
        guard inputRaw + outputRaw + cachedRaw + thoughtsRaw > 0 else { return }

        let normalized = ProviderJSON.normalizedOverlappingTokens(
            inputRaw: inputRaw,
            outputRaw: outputRaw,
            cachedRaw: cachedRaw,
            cacheCreateRaw: 0,
            reasoningRaw: thoughtsRaw
        )
        index += 1
        entries.append(
            TokenEntry(
                source: sourceID,
                model: model,
                project: project,
                timestamp: timestamp,
                inputTokens: normalized.input,
                outputTokens: normalized.output,
                cachedInputTokens: normalized.cached,
                reasoningOutputTokens: normalized.reasoning,
                dedupKey: "\(sourceID):\(url.path):\(index):\(model):\(inputRaw):\(outputRaw):\(cachedRaw):\(thoughtsRaw)"
            )
        )
    }

    private static func projectName(from url: URL) -> String {
        let sessionDirectory = url.deletingLastPathComponent().deletingLastPathComponent().lastPathComponent
        return sessionDirectory.isEmpty ? "unknown" : sessionDirectory
    }
}

private struct JSONLineObject {
    let lineNumber: Int
    let object: [String: Any]
}

private enum JSONLineReader {
    static func objects(at url: URL, fromOffset: Int64?) throws -> [JSONLineObject] {
        let data = try dataFromFile(at: url, fromOffset: fromOffset)
        guard !data.isEmpty else { return [] }

        let text = String(decoding: data, as: UTF8.self)
        var rows: [JSONLineObject] = []
        var lineNumber = 0

        for line in text.split(whereSeparator: \.isNewline) {
            lineNumber += 1
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, let lineData = trimmed.data(using: .utf8) else { continue }
            guard let object = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any] else {
                continue
            }
            rows.append(JSONLineObject(lineNumber: lineNumber, object: object))
        }

        return rows
    }

    private static func dataFromFile(at url: URL, fromOffset: Int64?) throws -> Data {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }

        if let fromOffset, fromOffset > 0 {
            let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
            let size = (attrs[.size] as? NSNumber)?.int64Value ?? 0
            guard fromOffset < size else { return Data() }
            handle.seek(toFileOffset: UInt64(fromOffset))
        }

        return handle.readDataToEndOfFile()
    }
}

private enum ProviderJSON {
    static func dictionary(_ value: Any?) -> [String: Any]? {
        value as? [String: Any]
    }

    static func string(_ dict: [String: Any], _ keys: String...) -> String? {
        for key in keys {
            if let value = dict[key] as? String, !value.isEmpty {
                return value
            }
        }
        return nil
    }

    static func int64(_ dict: [String: Any], _ key: String) -> Int64 {
        guard let value = dict[key] else { return 0 }
        if let int = value as? Int { return Int64(int) }
        if let int64 = value as? Int64 { return int64 }
        if let double = value as? Double { return Int64(double) }
        if let number = value as? NSNumber { return number.int64Value }
        if let string = value as? String { return Int64(string) ?? 0 }
        return 0
    }

    static func date(_ value: Any?) -> Date? {
        if let date = value as? Date {
            return date
        }
        if let number = value as? NSNumber {
            let raw = number.doubleValue
            return Date(timeIntervalSince1970: raw > 10_000_000_000 ? raw / 1_000 : raw)
        }
        guard let string = value as? String, !string.isEmpty else { return nil }
        if let numeric = Double(string) {
            return Date(timeIntervalSince1970: numeric > 10_000_000_000 ? numeric / 1_000 : numeric)
        }

        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: string) {
            return date
        }

        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        return plain.date(from: string)
    }

    static func characterCount(_ value: Any?) -> Int {
        if let string = value as? String {
            return string.count
        }
        if let array = value as? [Any] {
            return array.reduce(0) { $0 + characterCount($1) }
        }
        if let dict = value as? [String: Any] {
            if let data = try? JSONSerialization.data(withJSONObject: dict),
               let string = String(data: data, encoding: .utf8) {
                return string.count
            }
        }
        return 0
    }

    static func normalizedOverlappingTokens(
        inputRaw: Int64,
        outputRaw: Int64,
        cachedRaw: Int64,
        cacheCreateRaw: Int64,
        reasoningRaw: Int64
    ) -> (input: Int64, output: Int64, cached: Int64, cacheCreate: Int64, reasoning: Int64) {
        let cached = min(max(0, cachedRaw), max(0, inputRaw))
        let cacheCreate = min(max(0, cacheCreateRaw), max(0, inputRaw - cached))
        let reasoning = min(max(0, reasoningRaw), max(0, outputRaw))
        let input = max(0, inputRaw - cached - cacheCreate)
        let output = max(0, outputRaw - reasoning)
        return (input, output, cached, cacheCreate, reasoning)
    }

    static func fileModificationDate(_ url: URL) -> Date? {
        (try? FileManager.default.attributesOfItem(atPath: url.path)[.modificationDate]) as? Date
    }

    static func isUnknownModel(_ value: String?) -> Bool {
        let normalized = (value ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return normalized.isEmpty || normalized == "unknown"
    }

    static func firstStringValue(in value: Any, keys: Set<String>) -> String? {
        if let dict = value as? [String: Any] {
            for key in keys {
                if let string = dict[key] as? String, !isUnknownModel(string) {
                    return string
                }
            }
            for child in dict.values {
                if let found = firstStringValue(in: child, keys: keys) {
                    return found
                }
            }
        } else if let array = value as? [Any] {
            for child in array {
                if let found = firstStringValue(in: child, keys: keys) {
                    return found
                }
            }
        }
        return nil
    }
}
