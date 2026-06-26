import Foundation

public struct UsageScanResult: Equatable, Sendable {
    public var scannedFiles: Int
    public var skippedFiles: Int
    public var parsedEntries: Int
    public var writtenBuckets: Int

    public init(scannedFiles: Int = 0, skippedFiles: Int = 0, parsedEntries: Int = 0, writtenBuckets: Int = 0) {
        self.scannedFiles = scannedFiles
        self.skippedFiles = skippedFiles
        self.parsedEntries = parsedEntries
        self.writtenBuckets = writtenBuckets
    }
}

public final class UsageScanner: @unchecked Sendable {
    private static let scanCacheVersion = "3"

    private let database: UsageDatabase
    private let parsers: [ProviderParser]
    private let fileManager: FileManager
    private let logger: UsageScannerLogger

    public init(
        database: UsageDatabase,
        parsers: [ProviderParser]? = nil,
        fileManager: FileManager = .default,
        logger: UsageScannerLogger? = nil
    ) {
        self.database = database
        self.parsers = parsers ?? [
            ClaudeCodeParser(),
            CodexSessionParser(),
            GeminiCLIParser()
        ]
        self.fileManager = fileManager
        self.logger = logger ?? UsageScannerLogger.defaultLogger()
    }

    public func scan() throws -> UsageScanResult {
        _ = try database.prepareForScan(
            cacheVersion: Self.scanCacheVersion,
            sourceIDs: parsers.map(\.sourceID)
        )

        var result = UsageScanResult()
        var addDeltaEntries: [TokenEntry] = []
        var maxSnapshotEntries: [TokenEntry] = []
        var cacheUpdates: [(path: String, source: String, size: Int64, mtimeNS: Int64, parserStateJSON: String)] = []

        for parser in parsers {
            for fileURL in candidateFiles(for: parser) {
                do {
                    let attrs = try fileManager.attributesOfItem(atPath: fileURL.path)
                    let size = (attrs[.size] as? NSNumber)?.int64Value ?? 0
                    let modifiedAt = (attrs[.modificationDate] as? Date) ?? Date.distantPast
                    let mtimeNS = Int64(modifiedAt.timeIntervalSince1970 * 1_000_000_000)
                    let cached = try database.scanFile(path: fileURL.path)

                    if cached?.size == size, cached?.mtimeNS == mtimeNS {
                        result.skippedFiles += 1
                        continue
                    }

                    let canReadDelta = parser.supportsAppendOnlyParsing
                        && (cached?.size ?? 0) > 0
                        && size > (cached?.size ?? 0)
                    let fromOffset = canReadDelta ? cached?.size : nil
                    let entries = try parser.parseFile(at: fileURL, fromOffset: fromOffset)
                    result.scannedFiles += 1
                    result.parsedEntries += entries.count

                    if canReadDelta || cached == nil {
                        addDeltaEntries.append(contentsOf: entries)
                    } else {
                        maxSnapshotEntries.append(contentsOf: entries)
                    }

                    cacheUpdates.append((
                        path: fileURL.path,
                        source: parser.sourceID,
                        size: size,
                        mtimeNS: mtimeNS,
                        parserStateJSON: #"{"parsedSize":\#(size)}"#
                    ))
                } catch {
                    logger.log("Failed to scan \(fileURL.path): \(error.localizedDescription)")
                }
            }
        }

        result.writtenBuckets += try database.ingest(entries: addDeltaEntries, strategy: .addDelta)
        result.writtenBuckets += try database.ingest(entries: maxSnapshotEntries, strategy: .maxSnapshot)

        for update in cacheUpdates {
            try database.upsertScanFile(
                path: update.path,
                source: update.source,
                size: update.size,
                mtimeNS: update.mtimeNS,
                parserStateJSON: update.parserStateJSON
            )
        }

        return result
    }

    private func candidateFiles(for parser: ProviderParser) -> [URL] {
        var files: [URL] = []
        let keys: [URLResourceKey] = [.isRegularFileKey, .isDirectoryKey]

        for root in parser.scanRoots where fileManager.fileExists(atPath: root.path) {
            guard let enumerator = fileManager.enumerator(
                at: root,
                includingPropertiesForKeys: keys,
                options: [.skipsPackageDescendants]
            ) else {
                continue
            }

            for case let fileURL as URL in enumerator {
                let values = try? fileURL.resourceValues(forKeys: Set(keys))
                guard values?.isRegularFile == true, parser.shouldParseFile(fileURL) else { continue }
                files.append(fileURL)
            }
        }

        return files
    }
}

public final class UsageScannerLogger: @unchecked Sendable {
    public let logURL: URL
    private let fileManager: FileManager
    private let lock = NSLock()

    public init(logURL: URL, fileManager: FileManager = .default) {
        self.logURL = logURL
        self.fileManager = fileManager
    }

    public static func defaultLogger() -> UsageScannerLogger {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser
        return UsageScannerLogger(
            logURL: support
                .appendingPathComponent("AgentBar", isDirectory: true)
                .appendingPathComponent("logs", isDirectory: true)
                .appendingPathComponent("scanner.log")
        )
    }

    public func log(_ message: String) {
        lock.lock()
        defer { lock.unlock() }

        let scrubbed = PrivacyScrubber.scrub(message)
        let line = "[\(ISO8601DateFormatter().string(from: Date()))] \(scrubbed)\n"
        guard let data = line.data(using: .utf8) else { return }

        do {
            try fileManager.createDirectory(at: logURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            if fileManager.fileExists(atPath: logURL.path) {
                let handle = try FileHandle(forWritingTo: logURL)
                defer { try? handle.close() }
                handle.seekToEndOfFile()
                handle.write(data)
            } else {
                try data.write(to: logURL, options: .atomic)
            }
        } catch {
            // Logging must never break local usage scanning.
        }
    }
}
