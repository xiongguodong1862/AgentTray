import Foundation
import SQLite3

struct SessionDayAccumulator {
    var dialogs = 0
    var activityTimestamps: [Date] = []
}

struct PatchStats: Equatable {
    var modifiedFiles: Set<String> = []
    var addedLines = 0
    var deletedLines = 0

    mutating func merge(_ other: PatchStats) {
        modifiedFiles.formUnion(other.modifiedFiles)
        addedLines += other.addedLines
        deletedLines += other.deletedLines
    }
}

struct SessionScanResult {
    var days: [Date: SessionDayAccumulator] = [:]
    var latestPrimary: (timestamp: Date, value: RateLimitWindow)?
    var latestSecondary: (timestamp: Date, value: RateLimitWindow)?
    var hasSourceData = false
}

public struct CodexUsageSnapshotBuilder: Sendable {
    private let sessionsRoot: URL
    private let stateDatabaseURL: URL
    private let calendar: Calendar
    private let petBaselineStore: PetProgressBaselineStore

    public init(
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
        calendar: Calendar = .current
    ) {
        self.init(
            sessionsRoot: homeDirectory.appending(path: ".codex/sessions"),
            stateDatabaseURL: homeDirectory.appending(path: ".codex/state_5.sqlite"),
            calendar: calendar,
            petBaselineStore: PetProgressBaselineStore()
        )
    }

    init(
        sessionsRoot: URL,
        stateDatabaseURL: URL,
        calendar: Calendar = .current,
        petBaselineStore: PetProgressBaselineStore = PetProgressBaselineStore()
    ) {
        self.sessionsRoot = sessionsRoot
        self.stateDatabaseURL = stateDatabaseURL
        self.calendar = calendar
        self.petBaselineStore = petBaselineStore
    }

    public func buildSnapshot(now: Date = .now) throws -> UsageSnapshot {
        let sessionResult = try CodexSessionScanner(rootURL: sessionsRoot, calendar: calendar).scanAll()
        let patchStatsByDay = try CodexSQLiteLogReader(databaseURL: stateDatabaseURL, calendar: calendar).readDailyPatchStats()
        let mergedMetrics = mergeMetrics(sessionResult: sessionResult, patchStatsByDay: patchStatsByDay)
        let lastSevenDays = buildLastSevenDays(from: mergedMetrics, now: now)
        let lastYearDays = buildLastYearDays(from: mergedMetrics, now: now)
        let today = lastSevenDays.last ?? .empty(for: calendar.startOfDay(for: now))
        let totalXP = mergedMetrics.values.reduce(0) { partialResult, metric in
            partialResult + Int(metric.activityScore.rounded())
        }
        let baselineDay = calendar.startOfDay(for: now)
        let todayXP = Int(today.activityScore.rounded())
        let baseline = resolvePetBaseline(totalXP: totalXP, todayXP: todayXP, day: baselineDay)
        let adjustedTodayXP: Int
        if calendar.isDate(baseline.day, inSameDayAs: baselineDay) {
            adjustedTodayXP = max(0, todayXP - baseline.todayXP)
        } else {
            adjustedTodayXP = max(0, todayXP)
        }
        let adjustedTotalXP = max(0, totalXP - baseline.totalXP)
        let pet = PetProgressCalculator.progress(totalXP: adjustedTotalXP, todayXP: adjustedTodayXP)

        return UsageSnapshot(
            generatedAt: now,
            primaryLimit: sessionResult.latestPrimary?.value,
            secondaryLimit: sessionResult.latestSecondary?.value,
            today: today,
            lastSevenDays: lastSevenDays,
            lastYearDays: lastYearDays,
            pet: pet,
            hasSourceData: sessionResult.hasSourceData || !patchStatsByDay.isEmpty
        )
    }

    private func resolvePetBaseline(totalXP: Int, todayXP: Int, day: Date) -> PetProgressBaseline {
        if let baseline = petBaselineStore.load() {
            return baseline
        }

        let baseline = PetProgressBaseline(totalXP: totalXP, todayXP: todayXP, day: day)
        try? petBaselineStore.save(baseline)
        return baseline
    }

    private func mergeMetrics(
        sessionResult: SessionScanResult,
        patchStatsByDay: [Date: PatchStats]
    ) -> [Date: UsageMetricsDay] {
        let allDays = Set(sessionResult.days.keys).union(patchStatsByDay.keys)
        var metricsByDay: [Date: UsageMetricsDay] = [:]

        for day in allDays {
            let session = sessionResult.days[day]
            let patch = patchStatsByDay[day]
            metricsByDay[day] = UsageMetricsDay(
                date: day,
                dialogs: session?.dialogs ?? 0,
                activeMinutes: ActivityTimelineCalculator.activeMinutes(for: session?.activityTimestamps ?? []),
                modifiedFiles: patch?.modifiedFiles.count ?? 0,
                addedLines: patch?.addedLines ?? 0,
                deletedLines: patch?.deletedLines ?? 0
            )
        }

        return metricsByDay
    }

    private func buildLastSevenDays(from metricsByDay: [Date: UsageMetricsDay], now: Date) -> [UsageMetricsDay] {
        let endOfToday = calendar.startOfDay(for: now)
        return (0..<7).map { offset in
            let date = calendar.date(byAdding: .day, value: offset - 6, to: endOfToday) ?? endOfToday
            return metricsByDay[date] ?? .empty(for: date)
        }
    }

    private func buildLastYearDays(from metricsByDay: [Date: UsageMetricsDay], now: Date) -> [UsageMetricsDay] {
        let endOfToday = calendar.startOfDay(for: now)
        return (0..<365).map { offset in
            let date = calendar.date(byAdding: .day, value: offset - 364, to: endOfToday) ?? endOfToday
            return metricsByDay[date] ?? .empty(for: date)
        }
    }
}

struct CodexSessionScanner {
    let rootURL: URL
    let calendar: Calendar

    func scanAll() throws -> SessionScanResult {
        guard FileManager.default.fileExists(atPath: rootURL.path) else {
            return SessionScanResult()
        }

        var result = SessionScanResult()
        let enumerator = FileManager.default.enumerator(
            at: rootURL,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        )

        while let fileURL = enumerator?.nextObject() as? URL {
            guard fileURL.pathExtension == "jsonl" else { continue }
            try scanFile(fileURL, into: &result)
        }

        return result
    }

    private func scanFile(_ fileURL: URL, into result: inout SessionScanResult) throws {
        guard let content = try? String(contentsOf: fileURL, encoding: .utf8) else { return }
        var sessionStartDay: Date?
        var sawUserMessage = false

        for rawLine in content.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = String(rawLine)
            guard
                let data = line.data(using: .utf8),
                let jsonObject = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                let timestampString = jsonObject["timestamp"] as? String,
                let timestamp = ISO8601DateParser.parse(timestampString)
            else {
                continue
            }

            let eventType = jsonObject["type"] as? String
            if sessionStartDay == nil {
                sessionStartDay = calendar.startOfDay(for: timestamp)
            }
            switch eventType {
            case "session_meta":
                if let payload = jsonObject["payload"] as? [String: Any],
                   let sessionTimestampString = payload["timestamp"] as? String,
                   let sessionTimestamp = ISO8601DateParser.parse(sessionTimestampString) {
                    sessionStartDay = calendar.startOfDay(for: sessionTimestamp)
                }
            case "event_msg":
                guard let payload = jsonObject["payload"] as? [String: Any] else { continue }
                if consumeEventMessage(payload, timestamp: timestamp, into: &result) {
                    sawUserMessage = true
                }
            case "response_item":
                guard let payload = jsonObject["payload"] as? [String: Any] else { continue }
                consumeResponseItem(payload, timestamp: timestamp, into: &result)
            default:
                break
            }
        }

        if sawUserMessage, let sessionStartDay {
            result.days[sessionStartDay, default: SessionDayAccumulator()].dialogs += 1
        }
    }

    private func consumeEventMessage(
        _ payload: [String: Any],
        timestamp: Date,
        into result: inout SessionScanResult
    ) -> Bool {
        guard let payloadType = payload["type"] as? String else { return false }
        let day = calendar.startOfDay(for: timestamp)

        switch payloadType {
        case "user_message":
            result.hasSourceData = true
            result.days[day, default: SessionDayAccumulator()].activityTimestamps.append(timestamp)
            return true
        case "agent_message", "task_started", "task_complete":
            result.hasSourceData = true
            result.days[day, default: SessionDayAccumulator()].activityTimestamps.append(timestamp)
        case "token_count":
            result.hasSourceData = true
        default:
            break
        }

        guard payloadType == "token_count", let rateLimits = payload["rate_limits"] as? [String: Any] else { return false }
        if let primary = extractLimitWindow(named: "primary", from: rateLimits) {
            if result.latestPrimary == nil || timestamp > result.latestPrimary!.timestamp {
                result.latestPrimary = (timestamp, primary)
            }
        }
        if let secondary = extractLimitWindow(named: "secondary", from: rateLimits) {
            if result.latestSecondary == nil || timestamp > result.latestSecondary!.timestamp {
                result.latestSecondary = (timestamp, secondary)
            }
        }

        return false
    }

    private func consumeResponseItem(
        _ payload: [String: Any],
        timestamp: Date,
        into result: inout SessionScanResult
    ) {
        guard payload["type"] as? String != nil else {
            return
        }

        let day = calendar.startOfDay(for: timestamp)
        result.hasSourceData = true
        result.days[day, default: SessionDayAccumulator()].activityTimestamps.append(timestamp)
    }

    private func extractLimitWindow(named name: String, from rateLimits: [String: Any]) -> RateLimitWindow? {
        guard
            let window = rateLimits[name] as? [String: Any],
            let usedPercent = window["used_percent"] as? Double,
            let windowMinutes = window["window_minutes"] as? Int,
            let resetsAt = window["resets_at"] as? Double
        else {
            return nil
        }

        return RateLimitWindow(
            usedPercent: usedPercent,
            windowMinutes: windowMinutes,
            resetsAt: Date(timeIntervalSince1970: resetsAt)
        )
    }
}

struct CodexSQLiteLogReader {
    let databaseURL: URL
    let calendar: Calendar

    func readDailyPatchStats() throws -> [Date: PatchStats] {
        guard FileManager.default.fileExists(atPath: databaseURL.path) else {
            return [:]
        }

        var database: OpaquePointer?
        let openResult = sqlite3_open_v2(databaseURL.path, &database, SQLITE_OPEN_READONLY, nil)
        guard openResult == SQLITE_OK, let database else {
            if let database {
                sqlite3_close(database)
            }
            return [:]
        }
        defer { sqlite3_close(database) }

        let query = """
        SELECT ts, message
        FROM logs
        WHERE message LIKE '%ToolCall: apply_patch%'
        """

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, query, -1, &statement, nil) == SQLITE_OK, let statement else {
            return [:]
        }
        defer { sqlite3_finalize(statement) }

        var statsByDay: [Date: PatchStats] = [:]

        while sqlite3_step(statement) == SQLITE_ROW {
            let timestamp = sqlite3_column_double(statement, 0)
            guard let cString = sqlite3_column_text(statement, 1) else { continue }
            let message = String(cString: cString)
            let parsedStats = ApplyPatchStatsParser.parse(message)
            guard parsedStats.addedLines > 0 || parsedStats.deletedLines > 0 || !parsedStats.modifiedFiles.isEmpty else {
                continue
            }

            let day = calendar.startOfDay(for: Date(timeIntervalSince1970: timestamp))
            var merged = statsByDay[day] ?? PatchStats()
            merged.merge(parsedStats)
            statsByDay[day] = merged
        }

        return statsByDay
    }
}

enum ApplyPatchStatsParser {
    static func parse(_ rawText: String) -> PatchStats {
        guard let beginRange = rawText.range(of: "*** Begin Patch") else {
            return PatchStats()
        }

        let patchText = String(rawText[beginRange.lowerBound...])
        var stats = PatchStats()

        patchText.enumerateLines { line, _ in
            if let file = filePath(prefix: "*** Add File: ", in: line) {
                stats.modifiedFiles.insert(file)
                return
            }
            if let file = filePath(prefix: "*** Update File: ", in: line) {
                stats.modifiedFiles.insert(file)
                return
            }
            if let file = filePath(prefix: "*** Delete File: ", in: line) {
                stats.modifiedFiles.insert(file)
                return
            }
            if let file = filePath(prefix: "*** Move to: ", in: line) {
                stats.modifiedFiles.insert(file)
                return
            }

            guard !line.hasPrefix("***") else { return }
            if line.hasPrefix("+") {
                stats.addedLines += 1
            } else if line.hasPrefix("-") {
                stats.deletedLines += 1
            }
        }

        return stats
    }

    private static func filePath(prefix: String, in line: String) -> String? {
        guard line.hasPrefix(prefix) else { return nil }
        return String(line.dropFirst(prefix.count))
    }
}

enum ISO8601DateParser {
    static func parse(_ value: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: value) {
            return date
        }

        let fallbackFormatter = ISO8601DateFormatter()
        fallbackFormatter.formatOptions = [.withInternetDateTime]
        return fallbackFormatter.date(from: value)
    }
}
