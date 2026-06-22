import Foundation
import SQLite3

public enum UsageDatabaseError: LocalizedError, Equatable {
    case openFailed(String)
    case sqlite(String)

    public var errorDescription: String? {
        switch self {
        case let .openFailed(message):
            return "Unable to open usage database: \(message)"
        case let .sqlite(message):
            return message
        }
    }
}

public struct ScanFileRecord: Equatable, Sendable {
    public let path: String
    public let source: String
    public let size: Int64
    public let mtimeNS: Int64
    public let parserStateJSON: String
    public let lastParsedAt: Int64

    public init(path: String, source: String, size: Int64, mtimeNS: Int64, parserStateJSON: String, lastParsedAt: Int64) {
        self.path = path
        self.source = source
        self.size = size
        self.mtimeNS = mtimeNS
        self.parserStateJSON = parserStateJSON
        self.lastParsedAt = lastParsedAt
    }
}

public enum BucketMergeStrategy: Sendable {
    case addDelta
    case maxSnapshot
}

public final class UsageDatabase: @unchecked Sendable {
    public let dbURL: URL

    private let handle: OpaquePointer
    private let lock = NSLock()

    public init(dbURL: URL? = nil) throws {
        let resolvedURL: URL
        if let dbURL {
            resolvedURL = dbURL
        } else {
            let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
                ?? FileManager.default.homeDirectoryForCurrentUser
            resolvedURL = support
                .appendingPathComponent("AgentBar", isDirectory: true)
                .appendingPathComponent("agentbar.db")
        }

        try FileManager.default.createDirectory(
            at: resolvedURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        var database: OpaquePointer?
        let flags = SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX
        guard sqlite3_open_v2(resolvedURL.path, &database, flags, nil) == SQLITE_OK, let database else {
            let message = database.map { String(cString: sqlite3_errmsg($0)) } ?? "unknown SQLite error"
            if let database {
                sqlite3_close(database)
            }
            throw UsageDatabaseError.openFailed(message)
        }

        self.dbURL = resolvedURL
        self.handle = database
        try initialize()
    }

    deinit {
        sqlite3_close(handle)
    }

    public func resetPricingToDefaults() throws {
        try locked {
            try executeUnlocked("DELETE FROM model_pricing;")
            try seedDefaultPricingUnlocked(force: true)
        }
    }

    public func allPricing() throws -> [ModelPricing] {
        try locked {
            var rows: [ModelPricing] = []
            try queryUnlocked(
                """
                SELECT pattern, display_name, family, input_per_mtok, output_per_mtok,
                       cache_read_per_mtok, cache_creation_per_mtok, reasoning_per_mtok
                FROM model_pricing
                ORDER BY LENGTH(pattern) DESC, pattern ASC;
                """
            ) { statement in
                rows.append(
                    ModelPricing(
                        pattern: columnString(statement, 0),
                        displayName: columnString(statement, 1),
                        family: columnString(statement, 2),
                        inputPerMTok: sqlite3_column_double(statement, 3),
                        outputPerMTok: sqlite3_column_double(statement, 4),
                        cacheReadPerMTok: sqlite3_column_double(statement, 5),
                        cacheCreationPerMTok: sqlite3_column_double(statement, 6),
                        reasoningPerMTok: sqlite3_column_double(statement, 7)
                    )
                )
            }
            return rows
        }
    }

    public func scanFile(path: String) throws -> ScanFileRecord? {
        try locked {
            var record: ScanFileRecord?
            try queryUnlocked(
                """
                SELECT path, source, size, mtime_ns, parser_state_json, last_parsed_at
                FROM scan_files
                WHERE path = ?;
                """,
                bind: { statement in
                    try bindText(path, to: statement, at: 1)
                },
                row: { statement in
                    record = ScanFileRecord(
                        path: columnString(statement, 0),
                        source: columnString(statement, 1),
                        size: sqlite3_column_int64(statement, 2),
                        mtimeNS: sqlite3_column_int64(statement, 3),
                        parserStateJSON: columnString(statement, 4),
                        lastParsedAt: sqlite3_column_int64(statement, 5)
                    )
                }
            )
            return record
        }
    }

    public func upsertScanFile(path: String, source: String, size: Int64, mtimeNS: Int64, parserStateJSON: String, parsedAt: Date = Date()) throws {
        try locked {
            try updateScanFileUnlocked(
                path: path,
                source: source,
                size: size,
                mtimeNS: mtimeNS,
                parserStateJSON: parserStateJSON,
                parsedAt: parsedAt
            )
        }
    }

    public func ingest(entries: [TokenEntry], strategy: BucketMergeStrategy = .addDelta, syncedAt: Date = Date()) throws -> Int {
        guard !entries.isEmpty else { return 0 }

        return try locked {
            let pricing = try pricingRowsUnlocked()
            let buckets = makeBuckets(entries: entries, pricingRows: pricing, syncedAt: syncedAt)
            guard !buckets.isEmpty else { return 0 }

            try executeUnlocked("BEGIN IMMEDIATE TRANSACTION;")
            do {
                for bucket in buckets {
                    try upsertBucketUnlocked(bucket, strategy: strategy)
                }
                try executeUnlocked("COMMIT;")
                return buckets.count
            } catch {
                try? executeUnlocked("ROLLBACK;")
                throw error
            }
        }
    }

    public func usageSummary(now: Date = Date(), settings: AppSettings = AppSettings()) throws -> UsageSummary {
        try locked {
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = settings.timeZone

            let todayDate = calendar.startOfDay(for: now)
            let todayKey = UsageAggregator.dayString(for: todayDate, calendar: calendar)
            let sevenDayStart = UsageAggregator.dayString(
                for: calendar.date(byAdding: .day, value: -6, to: todayDate) ?? todayDate,
                calendar: calendar
            )
            let monthStart = UsageAggregator.dayString(
                for: calendar.dateInterval(of: .month, for: todayDate)?.start ?? todayDate,
                calendar: calendar
            )
            let heatmapStart = UsageAggregator.dayString(
                for: calendar.date(byAdding: .day, value: -364, to: todayDate) ?? todayDate,
                calendar: calendar
            )

            let today = try usageForWhereUnlocked("bucket_date_local = ?", values: [todayKey], day: todayKey)
            let sevenDay = try usageForWhereUnlocked("bucket_date_local >= ?", values: [sevenDayStart], day: sevenDayStart)
            let month = try usageForWhereUnlocked("bucket_date_local >= ?", values: [monthStart], day: monthStart)
            let allTime = try usageForWhereUnlocked("1 = 1", values: [], day: "all")

            let topModel7Days = try topModelUnlocked(whereClause: "bucket_date_local >= ?", values: [sevenDayStart])
            let todayTopModel = try topModelUnlocked(whereClause: "bucket_date_local = ?", values: [todayKey])
            let sourceBreakdown = try sourceBreakdownUnlocked(startDay: sevenDayStart)
            let heatmapDays = try heatmapUnlocked(startDay: heatmapStart, today: todayDate, calendar: calendar)
            let dailyUsageDays = try dailyUsageUnlocked(startDay: heatmapStart)
            let dailyModelUsageDays = try dailyModelUsageUnlocked(startDay: heatmapStart)

            let quota = QuotaSnapshot(
                tokenBudget: settings.monthlyTokenBudget,
                costBudgetUSD: settings.monthlyCostBudgetUSD,
                monthTokens: Int(clamping: month.totalTokens),
                monthCostUSD: month.costUSD,
                tokenRemainingPercent: remainingPercent(used: Double(month.totalTokens), budget: settings.monthlyTokenBudget.map(Double.init)),
                costRemainingPercent: remainingPercent(used: month.costUSD, budget: settings.monthlyCostBudgetUSD)
            )

            return UsageSummary(
                today: today,
                sevenDayTokens: sevenDay.totalTokens,
                sevenDayCostUSD: sevenDay.costUSD,
                allTimeTokens: allTime.totalTokens,
                allTimeCostUSD: allTime.costUSD,
                monthTokens: month.totalTokens,
                monthCostUSD: month.costUSD,
                quota: quota,
                heatmapDays: heatmapDays,
                topModel7Days: topModel7Days,
                todayTopModel: todayTopModel,
                sourceBreakdown7Days: sourceBreakdown,
                dailyUsageDays: dailyUsageDays,
                dailyModelUsageDays: dailyModelUsageDays
            )
        }
    }

    public func recalculateHistoricalCosts() throws {
        try locked {
            let pricing = try pricingRowsUnlocked()
            var rows: [(id: Int64, model: String, input: Int64, output: Int64, cached: Int64, cacheCreate: Int64, reasoning: Int64)] = []
            try queryUnlocked(
                """
                SELECT id, model, input_tokens, output_tokens, cached_input_tokens,
                       cache_creation_input_tokens, reasoning_output_tokens
                FROM usage_buckets;
                """
            ) { statement in
                rows.append((
                    id: sqlite3_column_int64(statement, 0),
                    model: columnString(statement, 1),
                    input: sqlite3_column_int64(statement, 2),
                    output: sqlite3_column_int64(statement, 3),
                    cached: sqlite3_column_int64(statement, 4),
                    cacheCreate: sqlite3_column_int64(statement, 5),
                    reasoning: sqlite3_column_int64(statement, 6)
                ))
            }

            try executeUnlocked("BEGIN IMMEDIATE TRANSACTION;")
            do {
                for row in rows {
                    let pricingRow = ModelPricingCatalog.match(model: row.model, in: pricing)
                    let entry = TokenEntry(
                        source: "recalculate",
                        model: row.model,
                        project: "recalculate",
                        timestamp: Date(),
                        inputTokens: row.input,
                        outputTokens: row.output,
                        cachedInputTokens: row.cached,
                        cacheCreationInputTokens: row.cacheCreate,
                        reasoningOutputTokens: row.reasoning,
                        dedupKey: "\(row.id)"
                    )
                    let cost = ModelPricingCatalog.estimateCostUSD(tokens: entry, pricing: pricingRow)
                    try executePreparedUnlocked(
                        "UPDATE usage_buckets SET model_family = ?, estimated_cost_usd = ?, synced_at = ? WHERE id = ?;"
                    ) { statement in
                        try bindText(pricingRow.family, to: statement, at: 1)
                        sqlite3_bind_double(statement, 2, cost)
                        sqlite3_bind_int64(statement, 3, Int64(Date().timeIntervalSince1970))
                        sqlite3_bind_int64(statement, 4, row.id)
                    }
                }
                try executeUnlocked("COMMIT;")
            } catch {
                try? executeUnlocked("ROLLBACK;")
                throw error
            }
        }
    }

    private func initialize() throws {
        try locked {
            try executeUnlocked("PRAGMA journal_mode = WAL;")
            try executeUnlocked("PRAGMA foreign_keys = ON;")
            try executeUnlocked("PRAGMA synchronous = NORMAL;")
            try createSchemaUnlocked()
            try seedDefaultPricingUnlocked(force: false)
            try setMetaUnlocked(key: "schema_version", value: "1")
            try setMetaUnlocked(key: "scan_cache_version", value: "1")
        }
    }

    private func createSchemaUnlocked() throws {
        try executeUnlocked(
            """
            CREATE TABLE IF NOT EXISTS usage_buckets (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              source TEXT NOT NULL,
              model TEXT NOT NULL,
              model_family TEXT NOT NULL DEFAULT '',
              project TEXT NOT NULL DEFAULT 'unknown',
              bucket_start INTEGER NOT NULL,
              bucket_date_local TEXT NOT NULL,
              input_tokens INTEGER NOT NULL DEFAULT 0,
              output_tokens INTEGER NOT NULL DEFAULT 0,
              cached_input_tokens INTEGER NOT NULL DEFAULT 0,
              cache_creation_input_tokens INTEGER NOT NULL DEFAULT 0,
              reasoning_output_tokens INTEGER NOT NULL DEFAULT 0,
              total_tokens INTEGER NOT NULL DEFAULT 0,
              estimated_cost_usd REAL NOT NULL DEFAULT 0,
              synced_at INTEGER NOT NULL,
              UNIQUE (source, model, project, bucket_start)
            );
            """
        )
        try executeUnlocked("CREATE INDEX IF NOT EXISTS idx_buckets_date ON usage_buckets(bucket_date_local);")
        try executeUnlocked("CREATE INDEX IF NOT EXISTS idx_buckets_start ON usage_buckets(bucket_start DESC);")
        try executeUnlocked("CREATE INDEX IF NOT EXISTS idx_buckets_source ON usage_buckets(source, bucket_start DESC);")
        try executeUnlocked(
            """
            CREATE TABLE IF NOT EXISTS scan_files (
              path TEXT PRIMARY KEY,
              source TEXT NOT NULL,
              size INTEGER NOT NULL,
              mtime_ns INTEGER NOT NULL,
              parser_state_json TEXT NOT NULL DEFAULT '',
              last_parsed_at INTEGER NOT NULL
            );
            """
        )
        try executeUnlocked(
            """
            CREATE TABLE IF NOT EXISTS model_pricing (
              pattern TEXT PRIMARY KEY,
              display_name TEXT,
              family TEXT,
              input_per_mtok REAL NOT NULL,
              output_per_mtok REAL NOT NULL,
              cache_read_per_mtok REAL NOT NULL DEFAULT 0,
              cache_creation_per_mtok REAL NOT NULL DEFAULT 0,
              reasoning_per_mtok REAL NOT NULL DEFAULT 0
            );
            """
        )
        try executeUnlocked(
            """
            CREATE TABLE IF NOT EXISTS meta (
              key TEXT PRIMARY KEY,
              value TEXT NOT NULL
            );
            """
        )
    }

    private func seedDefaultPricingUnlocked(force: Bool) throws {
        if !force {
            var existing = 0
            try queryUnlocked("SELECT COUNT(*) FROM model_pricing;") { statement in
                existing = Int(sqlite3_column_int(statement, 0))
            }
            guard existing == 0 else { return }
        }

        for row in ModelPricingCatalog.defaults {
            try executePreparedUnlocked(
                """
                INSERT OR REPLACE INTO model_pricing
                (pattern, display_name, family, input_per_mtok, output_per_mtok,
                 cache_read_per_mtok, cache_creation_per_mtok, reasoning_per_mtok)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?);
                """
            ) { statement in
                try bindText(row.pattern, to: statement, at: 1)
                try bindText(row.displayName, to: statement, at: 2)
                try bindText(row.family, to: statement, at: 3)
                sqlite3_bind_double(statement, 4, row.inputPerMTok)
                sqlite3_bind_double(statement, 5, row.outputPerMTok)
                sqlite3_bind_double(statement, 6, row.cacheReadPerMTok)
                sqlite3_bind_double(statement, 7, row.cacheCreationPerMTok)
                sqlite3_bind_double(statement, 8, row.reasoningPerMTok)
            }
        }
    }

    private func pricingRowsUnlocked() throws -> [ModelPricing] {
        var rows: [ModelPricing] = []
        try queryUnlocked(
            """
            SELECT pattern, display_name, family, input_per_mtok, output_per_mtok,
                   cache_read_per_mtok, cache_creation_per_mtok, reasoning_per_mtok
            FROM model_pricing;
            """
        ) { statement in
            rows.append(
                ModelPricing(
                    pattern: columnString(statement, 0),
                    displayName: columnString(statement, 1),
                    family: columnString(statement, 2),
                    inputPerMTok: sqlite3_column_double(statement, 3),
                    outputPerMTok: sqlite3_column_double(statement, 4),
                    cacheReadPerMTok: sqlite3_column_double(statement, 5),
                    cacheCreationPerMTok: sqlite3_column_double(statement, 6),
                    reasoningPerMTok: sqlite3_column_double(statement, 7)
                )
            )
        }
        return rows
    }

    private func setMetaUnlocked(key: String, value: String) throws {
        try executePreparedUnlocked(
            "INSERT OR REPLACE INTO meta (key, value) VALUES (?, ?);"
        ) { statement in
            try bindText(key, to: statement, at: 1)
            try bindText(value, to: statement, at: 2)
        }
    }

    private func updateScanFileUnlocked(path: String, source: String, size: Int64, mtimeNS: Int64, parserStateJSON: String, parsedAt: Date) throws {
        try executePreparedUnlocked(
            """
            INSERT INTO scan_files (path, source, size, mtime_ns, parser_state_json, last_parsed_at)
            VALUES (?, ?, ?, ?, ?, ?)
            ON CONFLICT(path) DO UPDATE SET
                source = excluded.source,
                size = excluded.size,
                mtime_ns = excluded.mtime_ns,
                parser_state_json = excluded.parser_state_json,
                last_parsed_at = excluded.last_parsed_at;
            """
        ) { statement in
            try bindText(path, to: statement, at: 1)
            try bindText(source, to: statement, at: 2)
            sqlite3_bind_int64(statement, 3, size)
            sqlite3_bind_int64(statement, 4, mtimeNS)
            try bindText(parserStateJSON, to: statement, at: 5)
            sqlite3_bind_int64(statement, 6, Int64(parsedAt.timeIntervalSince1970))
        }
    }

    private func makeBuckets(entries: [TokenEntry], pricingRows: [ModelPricing], syncedAt: Date) -> [UsageBucketAggregate] {
        var bestByDedupKey: [String: TokenEntry] = [:]
        for entry in entries where entry.totalTokens > 0 {
            if let existing = bestByDedupKey[entry.dedupKey], existing.totalTokens >= entry.totalTokens {
                continue
            }
            bestByDedupKey[entry.dedupKey] = entry
        }

        var buckets: [UsageBucketKey: UsageBucketAggregate] = [:]
        for entry in bestByDedupKey.values {
            let bucketStart = Self.roundToHalfHour(entry.timestamp)
            let bucketStartSeconds = Int64(bucketStart.timeIntervalSince1970)
            let key = UsageBucketKey(
                source: entry.source,
                model: entry.model,
                project: entry.project,
                bucketStart: bucketStartSeconds
            )
            let pricing = ModelPricingCatalog.match(model: entry.model, in: pricingRows)
            let cost = ModelPricingCatalog.estimateCostUSD(tokens: entry, pricing: pricing)
            var aggregate = buckets[key] ?? UsageBucketAggregate(
                source: entry.source,
                model: entry.model,
                modelFamily: pricing.family,
                project: entry.project,
                bucketStart: bucketStartSeconds,
                bucketDateLocal: Self.localDayString(for: bucketStart),
                syncedAt: Int64(syncedAt.timeIntervalSince1970)
            )

            aggregate.modelFamily = pricing.family
            aggregate.inputTokens += entry.inputTokens
            aggregate.outputTokens += entry.outputTokens
            aggregate.cachedInputTokens += entry.cachedInputTokens
            aggregate.cacheCreationInputTokens += entry.cacheCreationInputTokens
            aggregate.reasoningOutputTokens += entry.reasoningOutputTokens
            aggregate.estimatedCostUSD += cost
            aggregate.syncedAt = Int64(syncedAt.timeIntervalSince1970)
            buckets[key] = aggregate
        }

        return Array(buckets.values)
    }

    private func upsertBucketUnlocked(_ bucket: UsageBucketAggregate, strategy: BucketMergeStrategy) throws {
        let updateClause: String
        switch strategy {
        case .addDelta:
            updateClause = """
                model_family = excluded.model_family,
                input_tokens = usage_buckets.input_tokens + excluded.input_tokens,
                output_tokens = usage_buckets.output_tokens + excluded.output_tokens,
                cached_input_tokens = usage_buckets.cached_input_tokens + excluded.cached_input_tokens,
                cache_creation_input_tokens = usage_buckets.cache_creation_input_tokens + excluded.cache_creation_input_tokens,
                reasoning_output_tokens = usage_buckets.reasoning_output_tokens + excluded.reasoning_output_tokens,
                total_tokens = usage_buckets.total_tokens + excluded.total_tokens,
                estimated_cost_usd = usage_buckets.estimated_cost_usd + excluded.estimated_cost_usd,
                synced_at = excluded.synced_at
            """
        case .maxSnapshot:
            updateClause = """
                model_family = excluded.model_family,
                input_tokens = MAX(input_tokens, excluded.input_tokens),
                output_tokens = MAX(output_tokens, excluded.output_tokens),
                cached_input_tokens = MAX(cached_input_tokens, excluded.cached_input_tokens),
                cache_creation_input_tokens = MAX(cache_creation_input_tokens, excluded.cache_creation_input_tokens),
                reasoning_output_tokens = MAX(reasoning_output_tokens, excluded.reasoning_output_tokens),
                total_tokens = MAX(total_tokens, excluded.total_tokens),
                estimated_cost_usd = MAX(estimated_cost_usd, excluded.estimated_cost_usd),
                synced_at = excluded.synced_at
            """
        }

        try executePreparedUnlocked(
            """
            INSERT INTO usage_buckets
            (source, model, model_family, project, bucket_start, bucket_date_local,
             input_tokens, output_tokens, cached_input_tokens, cache_creation_input_tokens,
             reasoning_output_tokens, total_tokens, estimated_cost_usd, synced_at)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT (source, model, project, bucket_start) DO UPDATE SET
            \(updateClause);
            """
        ) { statement in
            try bindText(bucket.source, to: statement, at: 1)
            try bindText(bucket.model, to: statement, at: 2)
            try bindText(bucket.modelFamily, to: statement, at: 3)
            try bindText(bucket.project, to: statement, at: 4)
            sqlite3_bind_int64(statement, 5, bucket.bucketStart)
            try bindText(bucket.bucketDateLocal, to: statement, at: 6)
            sqlite3_bind_int64(statement, 7, bucket.inputTokens)
            sqlite3_bind_int64(statement, 8, bucket.outputTokens)
            sqlite3_bind_int64(statement, 9, bucket.cachedInputTokens)
            sqlite3_bind_int64(statement, 10, bucket.cacheCreationInputTokens)
            sqlite3_bind_int64(statement, 11, bucket.reasoningOutputTokens)
            sqlite3_bind_int64(statement, 12, bucket.totalTokens)
            sqlite3_bind_double(statement, 13, bucket.estimatedCostUSD)
            sqlite3_bind_int64(statement, 14, bucket.syncedAt)
        }
    }

    private func usageForWhereUnlocked(_ whereClause: String, values: [String], day: String) throws -> DailyUsage {
        var usage = DailyUsage(day: day)
        try queryUnlocked(
            """
            SELECT COALESCE(SUM(input_tokens), 0),
                   COALESCE(SUM(output_tokens), 0),
                   COALESCE(SUM(cached_input_tokens), 0),
                   COALESCE(SUM(cache_creation_input_tokens), 0),
                   COALESCE(SUM(reasoning_output_tokens), 0),
                   COALESCE(SUM(estimated_cost_usd), 0),
                   COUNT(*)
            FROM usage_buckets
            WHERE \(whereClause);
            """,
            bind: { statement in
                for (index, value) in values.enumerated() {
                    try bindText(value, to: statement, at: Int32(index + 1))
                }
            },
            row: { statement in
                usage = DailyUsage(
                    day: day,
                    inputTokens: sqlite3_column_int64(statement, 0),
                    outputTokens: sqlite3_column_int64(statement, 1),
                    cachedInputTokens: sqlite3_column_int64(statement, 2),
                    cacheCreationInputTokens: sqlite3_column_int64(statement, 3),
                    reasoningOutputTokens: sqlite3_column_int64(statement, 4),
                    requestCount: Int(sqlite3_column_int(statement, 6)),
                    costUSD: sqlite3_column_double(statement, 5)
                )
            }
        )
        return usage
    }

    private func topModelUnlocked(whereClause: String, values: [String]) throws -> ModelUsage? {
        var result: ModelUsage?
        try queryUnlocked(
            """
            SELECT model, SUM(total_tokens) AS tokens, SUM(estimated_cost_usd) AS cost
            FROM usage_buckets
            WHERE \(whereClause)
              AND TRIM(LOWER(model)) != 'unknown'
              AND TRIM(model) != ''
            GROUP BY model
            ORDER BY tokens DESC
            LIMIT 1;
            """,
            bind: { statement in
                for (index, value) in values.enumerated() {
                    try bindText(value, to: statement, at: Int32(index + 1))
                }
            },
            row: { statement in
                result = ModelUsage(
                    model: columnString(statement, 0),
                    tokens: sqlite3_column_int64(statement, 1),
                    costUSD: sqlite3_column_double(statement, 2)
                )
            }
        )
        return result
    }

    private func sourceBreakdownUnlocked(startDay: String) throws -> [SourceUsage] {
        var rows: [SourceUsage] = []
        try queryUnlocked(
            """
            SELECT source, SUM(total_tokens) AS tokens, SUM(estimated_cost_usd) AS cost
            FROM usage_buckets
            WHERE bucket_date_local >= ?
            GROUP BY source
            ORDER BY tokens DESC;
            """,
            bind: { statement in
                try bindText(startDay, to: statement, at: 1)
            },
            row: { statement in
                rows.append(
                    SourceUsage(
                        source: columnString(statement, 0),
                        tokens: sqlite3_column_int64(statement, 1),
                        costUSD: sqlite3_column_double(statement, 2)
                    )
                )
            }
        )
        return rows
    }

    private func dailyUsageUnlocked(startDay: String) throws -> [DailyUsage] {
        var rows: [DailyUsage] = []
        try queryUnlocked(
            """
            SELECT bucket_date_local,
                   SUM(input_tokens),
                   SUM(output_tokens),
                   SUM(cached_input_tokens),
                   SUM(cache_creation_input_tokens),
                   SUM(reasoning_output_tokens),
                   SUM(estimated_cost_usd),
                   COUNT(*)
            FROM usage_buckets
            WHERE bucket_date_local >= ?
            GROUP BY bucket_date_local
            ORDER BY bucket_date_local ASC;
            """,
            bind: { statement in
                try bindText(startDay, to: statement, at: 1)
            },
            row: { statement in
                rows.append(
                    DailyUsage(
                        day: columnString(statement, 0),
                        inputTokens: sqlite3_column_int64(statement, 1),
                        outputTokens: sqlite3_column_int64(statement, 2),
                        cachedInputTokens: sqlite3_column_int64(statement, 3),
                        cacheCreationInputTokens: sqlite3_column_int64(statement, 4),
                        reasoningOutputTokens: sqlite3_column_int64(statement, 5),
                        requestCount: Int(sqlite3_column_int(statement, 7)),
                        costUSD: sqlite3_column_double(statement, 6)
                    )
                )
            }
        )
        return rows
    }

    private func dailyModelUsageUnlocked(startDay: String) throws -> [DailyModelUsage] {
        var rows: [DailyModelUsage] = []
        try queryUnlocked(
            """
            SELECT bucket_date_local,
                   model,
                   SUM(input_tokens),
                   SUM(output_tokens),
                   SUM(cached_input_tokens),
                   SUM(cache_creation_input_tokens),
                   SUM(reasoning_output_tokens),
                   SUM(estimated_cost_usd)
            FROM usage_buckets
            WHERE bucket_date_local >= ?
              AND TRIM(LOWER(model)) != 'unknown'
              AND TRIM(model) != ''
            GROUP BY bucket_date_local, model
            ORDER BY bucket_date_local ASC, model ASC;
            """,
            bind: { statement in
                try bindText(startDay, to: statement, at: 1)
            },
            row: { statement in
                rows.append(
                    DailyModelUsage(
                        day: columnString(statement, 0),
                        model: columnString(statement, 1),
                        inputTokens: sqlite3_column_int64(statement, 2),
                        outputTokens: sqlite3_column_int64(statement, 3),
                        cachedInputTokens: sqlite3_column_int64(statement, 4),
                        cacheCreationInputTokens: sqlite3_column_int64(statement, 5),
                        reasoningOutputTokens: sqlite3_column_int64(statement, 6),
                        costUSD: sqlite3_column_double(statement, 7)
                    )
                )
            }
        )
        return rows
    }

    private func heatmapUnlocked(startDay: String, today: Date, calendar: Calendar) throws -> [HeatmapDay] {
        struct DayModelTotal {
            var tokens: Int64 = 0
            var cost: Double = 0
        }

        var byDay: [String: DayModelTotal] = [:]
        var modelTotalsByDay: [String: [String: Int64]] = [:]

        try queryUnlocked(
            """
            SELECT bucket_date_local, model, SUM(total_tokens) AS tokens, SUM(estimated_cost_usd) AS cost
            FROM usage_buckets
            WHERE bucket_date_local >= ?
            GROUP BY bucket_date_local, model
            ORDER BY bucket_date_local ASC;
            """,
            bind: { statement in
                try bindText(startDay, to: statement, at: 1)
            },
            row: { statement in
                let day = columnString(statement, 0)
                let model = columnString(statement, 1)
                let tokens = sqlite3_column_int64(statement, 2)
                let cost = sqlite3_column_double(statement, 3)
                byDay[day, default: DayModelTotal()].tokens += tokens
                byDay[day, default: DayModelTotal()].cost += cost
                if !Self.isUnknownModel(model) {
                    modelTotalsByDay[day, default: [:]][model, default: 0] += tokens
                }
            }
        )

        let dates = (0..<365).compactMap { offset in
            calendar.date(byAdding: .day, value: offset - 364, to: today)
        }
        let maxTokens = dates.map { date in
            byDay[UsageAggregator.dayString(for: date, calendar: calendar)]?.tokens ?? 0
        }.max() ?? 0

        return dates.map { date in
            let key = UsageAggregator.dayString(for: date, calendar: calendar)
            let totals = byDay[key] ?? DayModelTotal()
            let topModel = modelTotalsByDay[key]?.max { left, right in
                left.value < right.value
            }?.key
            return HeatmapDay(
                day: key,
                tokens: totals.tokens,
                costUSD: totals.cost,
                topModel: topModel,
                level: Self.heatmapLevel(tokens: totals.tokens, maxTokens: maxTokens)
            )
        }
    }

    private func executeUnlocked(_ sql: String) throws {
        var error: UnsafeMutablePointer<Int8>?
        let code = sqlite3_exec(handle, sql, nil, nil, &error)
        if code != SQLITE_OK {
            let message = error.map { String(cString: $0) } ?? sqliteMessage
            if let error {
                sqlite3_free(error)
            }
            throw UsageDatabaseError.sqlite(PrivacyScrubber.scrub(message))
        }
    }

    private func executePreparedUnlocked(_ sql: String, bind: (OpaquePointer) throws -> Void = { _ in }) throws {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            throw UsageDatabaseError.sqlite(sqliteMessage)
        }
        defer { sqlite3_finalize(statement) }

        try bind(statement)
        let code = sqlite3_step(statement)
        guard code == SQLITE_DONE else {
            throw UsageDatabaseError.sqlite(sqliteMessage)
        }
    }

    private func queryUnlocked(
        _ sql: String,
        bind: (OpaquePointer) throws -> Void = { _ in },
        row: (OpaquePointer) throws -> Void
    ) throws {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            throw UsageDatabaseError.sqlite(sqliteMessage)
        }
        defer { sqlite3_finalize(statement) }

        try bind(statement)
        while true {
            let code = sqlite3_step(statement)
            switch code {
            case SQLITE_ROW:
                try row(statement)
            case SQLITE_DONE:
                return
            default:
                throw UsageDatabaseError.sqlite(sqliteMessage)
            }
        }
    }

    private func locked<T>(_ work: () throws -> T) throws -> T {
        lock.lock()
        defer { lock.unlock() }
        return try work()
    }

    private var sqliteMessage: String {
        PrivacyScrubber.scrub(String(cString: sqlite3_errmsg(handle)))
    }

    private static func roundToHalfHour(_ date: Date) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        var components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        components.minute = (components.minute ?? 0) < 30 ? 0 : 30
        components.second = 0
        components.nanosecond = 0
        return calendar.date(from: components) ?? date
    }

    private static func localDayString(for date: Date) -> String {
        UsageAggregator.dayString(for: date, timeZone: .current)
    }

    private static func heatmapLevel(tokens: Int64, maxTokens: Int64) -> Int {
        guard tokens > 0, maxTokens > 0 else { return 0 }
        let ratio = Double(tokens) / Double(maxTokens)
        switch ratio {
        case ...0.25:
            return 1
        case ...0.50:
            return 2
        case ...0.75:
            return 3
        default:
            return 4
        }
    }

    private static func isUnknownModel(_ model: String) -> Bool {
        let normalized = model.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return normalized.isEmpty || normalized == "unknown"
    }

    private func remainingPercent(used: Double?, budget: Double?) -> Double? {
        guard let used, let budget, budget > 0 else { return nil }
        return max(0, min(100, (1 - used / budget) * 100))
    }
}

private struct UsageBucketKey: Hashable {
    let source: String
    let model: String
    let project: String
    let bucketStart: Int64
}

private struct UsageBucketAggregate {
    let source: String
    let model: String
    var modelFamily: String
    let project: String
    let bucketStart: Int64
    let bucketDateLocal: String
    var inputTokens: Int64 = 0
    var outputTokens: Int64 = 0
    var cachedInputTokens: Int64 = 0
    var cacheCreationInputTokens: Int64 = 0
    var reasoningOutputTokens: Int64 = 0
    var estimatedCostUSD: Double = 0
    var syncedAt: Int64

    var totalTokens: Int64 {
        inputTokens
            + outputTokens
            + cachedInputTokens
            + cacheCreationInputTokens
            + reasoningOutputTokens
    }
}

private let sqliteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

private func bindText(_ value: String, to statement: OpaquePointer, at index: Int32) throws {
    let code = sqlite3_bind_text(statement, index, value, -1, sqliteTransient)
    guard code == SQLITE_OK else {
        throw UsageDatabaseError.sqlite("Unable to bind SQLite text value")
    }
}

private func columnString(_ statement: OpaquePointer, _ index: Int32) -> String {
    guard let text = sqlite3_column_text(statement, index) else { return "" }
    return String(cString: text)
}
