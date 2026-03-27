import Foundation
import SQLite3

struct AgentAnalyticsBuilder: Sendable {
    private let codexSessionsRoot: URL
    private let codexStateDatabaseURL: URL
    private let claudeProjectsRoot: URL
    private let geminiLogsRoot: URL
    private let calendar: Calendar

    init(
        codexSessionsRoot: URL,
        codexStateDatabaseURL: URL,
        claudeProjectsRoot: URL,
        geminiLogsRoot: URL,
        calendar: Calendar
    ) {
        self.codexSessionsRoot = codexSessionsRoot
        self.codexStateDatabaseURL = codexStateDatabaseURL
        self.claudeProjectsRoot = claudeProjectsRoot
        self.geminiLogsRoot = geminiLogsRoot
        self.calendar = calendar
    }

    func buildCodex(now: Date, primaryLimit: RateLimitWindow?, secondaryLimit: RateLimitWindow?) -> AgentAnalyticsSnapshot {
        let parsed = parseCodexSessions()
        let patchEvents = readCodexPatchEvents()
        let activityToday = makeHourlyActivity(range: .today, entries: parsed.activityEntries, now: now)
        let activityWeek = makeDailyActivity(range: .week, entries: parsed.activityEntries, now: now)
        let activityMonth = makeDailyActivity(range: .month, entries: parsed.activityEntries, now: now)

        return AgentAnalyticsSnapshot(
            selectedRangeSupported: AnalyticsRange.allCases,
            activityTrendToday: activityToday,
            activityTrendWeek: activityWeek,
            activityTrendMonth: activityMonth,
            sessionStatsToday: makeSessionStats(range: .today, sessionStarts: parsed.sessionStarts, userMessagesBySession: parsed.userMessagesBySession, activityEntries: parsed.activityEntries, now: now),
            sessionStatsWeek: makeSessionStats(range: .week, sessionStarts: parsed.sessionStarts, userMessagesBySession: parsed.userMessagesBySession, activityEntries: parsed.activityEntries, now: now),
            sessionStatsMonth: makeSessionStats(range: .month, sessionStarts: parsed.sessionStarts, userMessagesBySession: parsed.userMessagesBySession, activityEntries: parsed.activityEntries, now: now),
            tokenStatsToday: makeTokenStats(range: .today, samples: parsed.tokenSamples, now: now),
            tokenStatsWeek: makeTokenStats(range: .week, samples: parsed.tokenSamples, now: now),
            tokenStatsMonth: makeTokenStats(range: .month, samples: parsed.tokenSamples, now: now),
            toolStatsToday: makeToolStats(range: .today, toolCalls: parsed.toolCalls, sessionsWithSearch: parsed.sessionsWithSearch, sessionStarts: parsed.sessionStarts, now: now),
            toolStatsWeek: makeToolStats(range: .week, toolCalls: parsed.toolCalls, sessionsWithSearch: parsed.sessionsWithSearch, sessionStarts: parsed.sessionStarts, now: now),
            toolStatsMonth: makeToolStats(range: .month, toolCalls: parsed.toolCalls, sessionsWithSearch: parsed.sessionsWithSearch, sessionStarts: parsed.sessionStarts, now: now),
            changeStatsToday: makeChangeStats(range: .today, patchEvents: patchEvents, now: now),
            changeStatsWeek: makeChangeStats(range: .week, patchEvents: patchEvents, now: now),
            changeStatsMonth: makeChangeStats(range: .month, patchEvents: patchEvents, now: now),
            limitStatsToday: makeLimitStats(range: .today, samples: parsed.limitSamples, primaryLimit: primaryLimit, secondaryLimit: secondaryLimit, now: now),
            limitStatsWeek: makeLimitStats(range: .week, samples: parsed.limitSamples, primaryLimit: primaryLimit, secondaryLimit: secondaryLimit, now: now),
            limitStatsMonth: makeLimitStats(range: .month, samples: parsed.limitSamples, primaryLimit: primaryLimit, secondaryLimit: secondaryLimit, now: now),
            modelStatsToday: nil,
            modelStatsWeek: nil,
            modelStatsMonth: nil,
            projectStatsToday: nil,
            projectStatsWeek: nil,
            projectStatsMonth: nil
        )
    }

    func buildClaude(now: Date) -> AgentAnalyticsSnapshot {
        let parsed = parseClaudeSessions()
        let activityToday = makeHourlyActivity(range: .today, entries: parsed.activityEntries, now: now)
        let activityWeek = makeDailyActivity(range: .week, entries: parsed.activityEntries, now: now)
        let activityMonth = makeDailyActivity(range: .month, entries: parsed.activityEntries, now: now)

        return AgentAnalyticsSnapshot(
            selectedRangeSupported: AnalyticsRange.allCases,
            activityTrendToday: activityToday,
            activityTrendWeek: activityWeek,
            activityTrendMonth: activityMonth,
            sessionStatsToday: makeSessionStats(range: .today, sessionStarts: parsed.sessionStarts, userMessagesBySession: parsed.userMessagesBySession, activityEntries: parsed.activityEntries, now: now),
            sessionStatsWeek: makeSessionStats(range: .week, sessionStarts: parsed.sessionStarts, userMessagesBySession: parsed.userMessagesBySession, activityEntries: parsed.activityEntries, now: now),
            sessionStatsMonth: makeSessionStats(range: .month, sessionStarts: parsed.sessionStarts, userMessagesBySession: parsed.userMessagesBySession, activityEntries: parsed.activityEntries, now: now),
            tokenStatsToday: makeTokenStats(range: .today, samples: parsed.tokenSamples, now: now),
            tokenStatsWeek: makeTokenStats(range: .week, samples: parsed.tokenSamples, now: now),
            tokenStatsMonth: makeTokenStats(range: .month, samples: parsed.tokenSamples, now: now),
            toolStatsToday: makeToolStats(range: .today, toolCalls: parsed.toolCalls, sessionsWithSearch: [], sessionStarts: parsed.sessionStarts, now: now),
            toolStatsWeek: makeToolStats(range: .week, toolCalls: parsed.toolCalls, sessionsWithSearch: [], sessionStarts: parsed.sessionStarts, now: now),
            toolStatsMonth: makeToolStats(range: .month, toolCalls: parsed.toolCalls, sessionsWithSearch: [], sessionStarts: parsed.sessionStarts, now: now),
            changeStatsToday: nil,
            changeStatsWeek: nil,
            changeStatsMonth: nil,
            limitStatsToday: nil,
            limitStatsWeek: nil,
            limitStatsMonth: nil,
            modelStatsToday: nil,
            modelStatsWeek: nil,
            modelStatsMonth: nil,
            projectStatsToday: nil,
            projectStatsWeek: nil,
            projectStatsMonth: nil
        )
    }

    func buildGemini(now: Date) -> AgentAnalyticsSnapshot {
        let parsed = parseGeminiSessions()
        let activityToday = makeHourlyActivity(range: .today, entries: parsed.activityEntries, now: now)
        let activityWeek = makeDailyActivity(range: .week, entries: parsed.activityEntries, now: now)
        let activityMonth = makeDailyActivity(range: .month, entries: parsed.activityEntries, now: now)

        return AgentAnalyticsSnapshot(
            selectedRangeSupported: AnalyticsRange.allCases,
            activityTrendToday: activityToday,
            activityTrendWeek: activityWeek,
            activityTrendMonth: activityMonth,
            sessionStatsToday: makeSessionStats(range: .today, sessionStarts: parsed.sessionStarts, userMessagesBySession: parsed.userMessagesBySession, activityEntries: parsed.activityEntries, now: now),
            sessionStatsWeek: makeSessionStats(range: .week, sessionStarts: parsed.sessionStarts, userMessagesBySession: parsed.userMessagesBySession, activityEntries: parsed.activityEntries, now: now),
            sessionStatsMonth: makeSessionStats(range: .month, sessionStarts: parsed.sessionStarts, userMessagesBySession: parsed.userMessagesBySession, activityEntries: parsed.activityEntries, now: now),
            tokenStatsToday: makeTokenStats(range: .today, samples: parsed.tokenSamples, now: now),
            tokenStatsWeek: makeTokenStats(range: .week, samples: parsed.tokenSamples, now: now),
            tokenStatsMonth: makeTokenStats(range: .month, samples: parsed.tokenSamples, now: now),
            toolStatsToday: nil,
            toolStatsWeek: nil,
            toolStatsMonth: nil,
            changeStatsToday: nil,
            changeStatsWeek: nil,
            changeStatsMonth: nil,
            limitStatsToday: nil,
            limitStatsWeek: nil,
            limitStatsMonth: nil,
            modelStatsToday: makeModelStats(range: .today, modelSamples: parsed.modelSamples, now: now),
            modelStatsWeek: makeModelStats(range: .week, modelSamples: parsed.modelSamples, now: now),
            modelStatsMonth: makeModelStats(range: .month, modelSamples: parsed.modelSamples, now: now),
            projectStatsToday: makeProjectStats(range: .today, projectSamples: parsed.projectSamples, now: now),
            projectStatsWeek: makeProjectStats(range: .week, projectSamples: parsed.projectSamples, now: now),
            projectStatsMonth: makeProjectStats(range: .month, projectSamples: parsed.projectSamples, now: now)
        )
    }
}

private extension AgentAnalyticsBuilder {
    struct ActivityEntry {
        let timestamp: Date
        let sessionID: String?
    }

    struct TokenSample {
        let timestamp: Date
        let sessionID: String?
        let inputTokens: Int
        let outputTokens: Int
        let reasoningTokens: Int
        let totalTokens: Int
    }

    struct ToolCallSample {
        let timestamp: Date
        let sessionID: String?
        let name: String
    }

    struct LimitSample {
        let timestamp: Date
        let primaryPercent: Double?
        let secondaryPercent: Double?
    }

    struct PatchEvent {
        let timestamp: Date
        let stats: PatchStats
    }

    struct ModelSample {
        let timestamp: Date
        let modelName: String
        let averageTokenContribution: Int
    }

    struct ProjectSample {
        let timestamp: Date
        let projectName: String
        let tokens: Int
    }

    struct ParsedAnalyticsData {
        var activityEntries: [ActivityEntry] = []
        var sessionStarts: [String: Date] = [:]
        var userMessagesBySession: [String: Int] = [:]
        var tokenSamples: [TokenSample] = []
        var toolCalls: [ToolCallSample] = []
        var sessionsWithSearch: Set<String> = []
        var limitSamples: [LimitSample] = []
        var modelSamples: [ModelSample] = []
        var projectSamples: [ProjectSample] = []
    }

    func parseCodexSessions() -> ParsedAnalyticsData {
        guard FileManager.default.fileExists(atPath: codexSessionsRoot.path) else { return ParsedAnalyticsData() }

        var parsed = ParsedAnalyticsData()
        let enumerator = FileManager.default.enumerator(
            at: codexSessionsRoot,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        )

        while let fileURL = enumerator?.nextObject() as? URL {
            guard fileURL.pathExtension == "jsonl" else { continue }
            guard let content = try? String(contentsOf: fileURL, encoding: .utf8) else { continue }
            var sessionID = fileURL.deletingPathExtension().lastPathComponent

            for rawLine in content.split(separator: "\n", omittingEmptySubsequences: false) {
                guard
                    let data = String(rawLine).data(using: .utf8),
                    let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                    let timestampString = json["timestamp"] as? String,
                    let timestamp = ISO8601DateParser.parse(timestampString),
                    let type = json["type"] as? String
                else {
                    continue
                }

                switch type {
                case "session_meta":
                    if let payload = json["payload"] as? [String: Any] {
                        if let id = payload["id"] as? String, !id.isEmpty {
                            sessionID = id
                        }
                        if let metaTimestampString = payload["timestamp"] as? String,
                           let metaTimestamp = ISO8601DateParser.parse(metaTimestampString) {
                            parsed.sessionStarts[sessionID] = min(parsed.sessionStarts[sessionID] ?? metaTimestamp, metaTimestamp)
                        } else {
                            parsed.sessionStarts[sessionID] = min(parsed.sessionStarts[sessionID] ?? timestamp, timestamp)
                        }
                    }
                case "event_msg":
                    guard let payload = json["payload"] as? [String: Any],
                          let payloadType = payload["type"] as? String else { continue }
                    switch payloadType {
                    case "user_message":
                        parsed.activityEntries.append(ActivityEntry(timestamp: timestamp, sessionID: sessionID))
                        parsed.userMessagesBySession[sessionID, default: 0] += 1
                        parsed.sessionStarts[sessionID] = min(parsed.sessionStarts[sessionID] ?? timestamp, timestamp)
                    case "agent_message", "task_started", "task_complete":
                        parsed.activityEntries.append(ActivityEntry(timestamp: timestamp, sessionID: sessionID))
                    case "token_count":
                        let tokenUsage = extractCodexTokenUsage(from: payload)
                        if tokenUsage.totalTokens > 0 {
                            parsed.tokenSamples.append(TokenSample(
                                timestamp: timestamp,
                                sessionID: sessionID,
                                inputTokens: tokenUsage.inputTokens,
                                outputTokens: tokenUsage.outputTokens,
                                reasoningTokens: tokenUsage.reasoningTokens,
                                totalTokens: tokenUsage.totalTokens
                            ))
                        }
                        if let limits = payload["rate_limits"] as? [String: Any] {
                            parsed.limitSamples.append(LimitSample(
                                timestamp: timestamp,
                                primaryPercent: extractRateLimitPercent(named: "primary", from: limits),
                                secondaryPercent: extractRateLimitPercent(named: "secondary", from: limits)
                            ))
                        }
                    default:
                        break
                    }
                case "response_item":
                    guard let payload = json["payload"] as? [String: Any],
                          let payloadType = payload["type"] as? String else { continue }
                    parsed.activityEntries.append(ActivityEntry(timestamp: timestamp, sessionID: sessionID))
                    if let toolName = extractCodexToolName(payload: payload, fallbackType: payloadType) {
                        parsed.toolCalls.append(ToolCallSample(timestamp: timestamp, sessionID: sessionID, name: toolName))
                    }
                    if payloadType == "web_search_call" {
                        parsed.sessionsWithSearch.insert(sessionID)
                    }
                default:
                    break
                }
            }
        }

        return parsed
    }

    func parseClaudeSessions() -> ParsedAnalyticsData {
        guard FileManager.default.fileExists(atPath: claudeProjectsRoot.path) else { return ParsedAnalyticsData() }
        var parsed = ParsedAnalyticsData()
        let enumerator = FileManager.default.enumerator(
            at: claudeProjectsRoot,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        )

        while let fileURL = enumerator?.nextObject() as? URL {
            guard fileURL.pathExtension == "jsonl" else { continue }
            guard let content = try? String(contentsOf: fileURL, encoding: .utf8) else { continue }

            for rawLine in content.split(separator: "\n", omittingEmptySubsequences: false) {
                guard
                    let data = String(rawLine).data(using: .utf8),
                    let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                    let timestampString = json["timestamp"] as? String,
                    let timestamp = ISO8601DateParser.parse(timestampString),
                    let sessionID = json["sessionId"] as? String,
                    let type = json["type"] as? String
                else {
                    continue
                }

                parsed.activityEntries.append(ActivityEntry(timestamp: timestamp, sessionID: sessionID))
                parsed.sessionStarts[sessionID] = min(parsed.sessionStarts[sessionID] ?? timestamp, timestamp)

                if type == "user" {
                    parsed.userMessagesBySession[sessionID, default: 0] += 1
                }

                if type == "assistant",
                   let message = json["message"] as? [String: Any] {
                    let usage = message["usage"] as? [String: Any] ?? [:]
                    let inputTokens = intValue(in: usage, keys: ["input_tokens", "inputTokens"])
                    let outputTokens = intValue(in: usage, keys: ["output_tokens", "outputTokens"])
                    let totalTokens = inputTokens + outputTokens
                    if totalTokens > 0 {
                        parsed.tokenSamples.append(TokenSample(
                            timestamp: timestamp,
                            sessionID: sessionID,
                            inputTokens: inputTokens,
                            outputTokens: outputTokens,
                            reasoningTokens: 0,
                            totalTokens: totalTokens
                        ))
                    }
                    if let contentItems = message["content"] as? [[String: Any]] {
                        for item in contentItems where (item["type"] as? String) == "tool_use" {
                            let name = (item["name"] as? String) ?? "tool_use"
                            parsed.toolCalls.append(ToolCallSample(timestamp: timestamp, sessionID: sessionID, name: name))
                        }
                    }
                }
            }
        }

        return parsed
    }

    func parseGeminiSessions() -> ParsedAnalyticsData {
        guard FileManager.default.fileExists(atPath: geminiLogsRoot.path) else { return ParsedAnalyticsData() }
        var parsed = ParsedAnalyticsData()

        let enumerator = FileManager.default.enumerator(
            at: geminiLogsRoot,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        )

        var usedChats = false
        while let fileURL = enumerator?.nextObject() as? URL {
            guard fileURL.pathComponents.contains("chats"), fileURL.pathExtension == "json" else { continue }
            usedChats = true
            guard let content = try? Data(contentsOf: fileURL),
                  let chat = try? JSONSerialization.jsonObject(with: content) as? [String: Any],
                  let sessionID = chat["sessionId"] as? String,
                  let messages = chat["messages"] as? [[String: Any]]
            else {
                continue
            }
            let projectName = geminiProjectName(for: fileURL)

            for message in messages {
                guard
                    let timestampString = message["timestamp"] as? String,
                    let timestamp = ISO8601DateParser.parse(timestampString)
                else {
                    continue
                }

                parsed.activityEntries.append(ActivityEntry(timestamp: timestamp, sessionID: sessionID))
                parsed.sessionStarts[sessionID] = min(parsed.sessionStarts[sessionID] ?? timestamp, timestamp)

                if (message["type"] as? String) == "user" {
                    parsed.userMessagesBySession[sessionID, default: 0] += 1
                }

                let tokenUsage = extractGeminiTokenUsage(from: message)
                if tokenUsage.totalTokens > 0 {
                    parsed.tokenSamples.append(TokenSample(
                        timestamp: timestamp,
                        sessionID: sessionID,
                        inputTokens: tokenUsage.inputTokens,
                        outputTokens: tokenUsage.outputTokens,
                        reasoningTokens: 0,
                        totalTokens: tokenUsage.totalTokens
                    ))
                    parsed.projectSamples.append(ProjectSample(timestamp: timestamp, projectName: projectName, tokens: tokenUsage.totalTokens))
                }

                if let model = extractGeminiModel(from: message), !model.isEmpty {
                    parsed.modelSamples.append(ModelSample(timestamp: timestamp, modelName: model, averageTokenContribution: max(0, tokenUsage.totalTokens)))
                }
            }
        }

        guard !usedChats else { return parsed }

        let fallbackEnumerator = FileManager.default.enumerator(
            at: geminiLogsRoot,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        )

        while let fileURL = fallbackEnumerator?.nextObject() as? URL {
            guard fileURL.lastPathComponent == "logs.json",
                  let data = try? Data(contentsOf: fileURL),
                  let items = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]
            else {
                continue
            }
            let sessionProject = geminiProjectName(for: fileURL)
            for item in items {
                guard
                    let timestampString = item["timestamp"] as? String,
                    let timestamp = ISO8601DateParser.parse(timestampString),
                    let sessionID = item["sessionId"] as? String
                else {
                    continue
                }

                parsed.activityEntries.append(ActivityEntry(timestamp: timestamp, sessionID: sessionID))
                parsed.sessionStarts[sessionID] = min(parsed.sessionStarts[sessionID] ?? timestamp, timestamp)
                if (item["type"] as? String) == "user" {
                    parsed.userMessagesBySession[sessionID, default: 0] += 1
                }
                let tokenUsage = extractGeminiTokenUsage(from: item)
                if tokenUsage.totalTokens > 0 {
                    parsed.tokenSamples.append(TokenSample(
                        timestamp: timestamp,
                        sessionID: sessionID,
                        inputTokens: tokenUsage.inputTokens,
                        outputTokens: tokenUsage.outputTokens,
                        reasoningTokens: 0,
                        totalTokens: tokenUsage.totalTokens
                    ))
                    parsed.projectSamples.append(ProjectSample(timestamp: timestamp, projectName: sessionProject, tokens: tokenUsage.totalTokens))
                }
                if let model = extractGeminiModel(from: item), !model.isEmpty {
                    parsed.modelSamples.append(ModelSample(timestamp: timestamp, modelName: model, averageTokenContribution: max(0, tokenUsage.totalTokens)))
                }
            }
        }

        return parsed
    }

    func readCodexPatchEvents() -> [PatchEvent] {
        guard FileManager.default.fileExists(atPath: codexStateDatabaseURL.path) else { return [] }
        var database: OpaquePointer?
        let openResult = sqlite3_open_v2(codexStateDatabaseURL.path, &database, SQLITE_OPEN_READONLY, nil)
        guard openResult == SQLITE_OK, let database else {
            if let database {
                sqlite3_close(database)
            }
            return []
        }
        defer { sqlite3_close(database) }

        let query = """
        SELECT ts, message
        FROM logs
        WHERE message LIKE '%ToolCall: apply_patch%'
        """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, query, -1, &statement, nil) == SQLITE_OK, let statement else {
            return []
        }
        defer { sqlite3_finalize(statement) }

        var events: [PatchEvent] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            let timestamp = sqlite3_column_double(statement, 0)
            guard let cString = sqlite3_column_text(statement, 1) else { continue }
            let message = String(cString: cString)
            let parsedStats = ApplyPatchStatsParser.parse(message)
            guard parsedStats.addedLines > 0 || parsedStats.deletedLines > 0 || !parsedStats.modifiedFiles.isEmpty else {
                continue
            }
            events.append(PatchEvent(timestamp: Date(timeIntervalSince1970: timestamp), stats: parsedStats))
        }
        return events
    }

    func makeHourlyActivity(range: AnalyticsRange, entries: [ActivityEntry], now: Date) -> [HourlyActivityPoint] {
        let filtered = entries.filter { contains($0.timestamp, in: range, now: now) }
        let calendar = self.calendar
        return (0..<24).map { hour in
            let hourEntries = filtered.filter { calendar.component(.hour, from: $0.timestamp) == hour }
            let activeMinutes = ActivityTimelineCalculator.activeMinutes(for: hourEntries.map(\.timestamp))
            let sessions = Set(hourEntries.compactMap(\.sessionID)).count
            return HourlyActivityPoint(hour: hour, activeMinutes: activeMinutes, sessions: sessions)
        }
    }

    func makeDailyActivity(range: AnalyticsRange, entries: [ActivityEntry], now: Date) -> [DailyActivityPoint] {
        let days = dayBuckets(for: range, now: now)
        let filtered = entries.filter { contains($0.timestamp, in: range, now: now) }
        let grouped = Dictionary(grouping: filtered) { calendar.startOfDay(for: $0.timestamp) }
        return days.map { day in
            let items = grouped[day] ?? []
            return DailyActivityPoint(
                date: day,
                activeMinutes: ActivityTimelineCalculator.activeMinutes(for: items.map(\.timestamp)),
                sessions: Set(items.compactMap(\.sessionID)).count
            )
        }
    }

    func makeSessionStats(
        range: AnalyticsRange,
        sessionStarts: [String: Date],
        userMessagesBySession: [String: Int],
        activityEntries: [ActivityEntry],
        now: Date
    ) -> SessionStatsSnapshot {
        let sessions = sessionStarts.filter { contains($0.value, in: range, now: now) }
        let totalSessions = sessions.count
        let totalTurns = sessions.keys.reduce(0) { $0 + (userMessagesBySession[$1] ?? 0) }
        let activeDays = Set(activityEntries.filter { contains($0.timestamp, in: range, now: now) }.map { calendar.startOfDay(for: $0.timestamp) }).count

        let series = range.usesHourlyBuckets
            ? hourBuckets(now: now).map { bucket in
                let count = sessions.values.filter { calendar.component(.hour, from: $0) == calendar.component(.hour, from: bucket) }.count
                return CountSeriesPoint(bucketStart: bucket, value: count)
            }
            : dayBuckets(for: range, now: now).map { bucket in
                let count = sessions.values.filter { calendar.isDate($0, inSameDayAs: bucket) }.count
                return CountSeriesPoint(bucketStart: bucket, value: count)
            }

        return SessionStatsSnapshot(
            totalSessions: totalSessions,
            averageTurnsPerSession: totalSessions == 0 ? 0 : Double(totalTurns) / Double(totalSessions),
            activeDays: activeDays,
            series: series
        )
    }

    func makeTokenStats(range: AnalyticsRange, samples: [TokenSample], now: Date) -> TokenStatsSnapshot {
        let filtered = samples.filter { contains($0.timestamp, in: range, now: now) }
        let grouped = Dictionary(grouping: filtered) { bucketStart(for: $0.timestamp, range: range) }
        let buckets = range.usesHourlyBuckets ? hourBuckets(now: now) : dayBuckets(for: range, now: now)

        let series = buckets.map { bucket in
            let total = (grouped[bucket] ?? []).reduce(0) { $0 + $1.totalTokens }
            return CountSeriesPoint(bucketStart: bucket, value: total)
        }

        var running = 0
        let cumulative = series.map { point in
            running += point.value
            return CountSeriesPoint(bucketStart: point.bucketStart, value: running)
        }

        let sessionCount = Set(filtered.compactMap(\.sessionID)).count
        let totalTokens = filtered.reduce(0) { $0 + $1.totalTokens }
        return TokenStatsSnapshot(
            totalTokens: totalTokens,
            averageTokensPerSession: sessionCount == 0 ? 0 : Double(totalTokens) / Double(sessionCount),
            inputTokens: filtered.reduce(0) { $0 + $1.inputTokens },
            outputTokens: filtered.reduce(0) { $0 + $1.outputTokens },
            reasoningTokens: filtered.reduce(0) { $0 + $1.reasoningTokens },
            series: series,
            cumulativeSeries: cumulative
        )
    }

    func makeToolStats(
        range: AnalyticsRange,
        toolCalls: [ToolCallSample],
        sessionsWithSearch: Set<String>,
        sessionStarts: [String: Date],
        now: Date
    ) -> ToolStatsSnapshot {
        let filtered = toolCalls.filter { contains($0.timestamp, in: range, now: now) }
        let totalToolCalls = filtered.count
        let counts = Dictionary(grouping: filtered, by: \.name).mapValues(\.count)
        let sorted = counts.sorted { lhs, rhs in
            if lhs.value == rhs.value {
                return lhs.key < rhs.key
            }
            return lhs.value > rhs.value
        }
        let top = sorted.prefix(6)
        let topTools = top.map { item in
            NamedCountItem(name: item.key, count: item.value, ratio: totalToolCalls == 0 ? 0 : Double(item.value) / Double(totalToolCalls))
        }
        let sessionIDsInRange = Set(sessionStarts.filter { contains($0.value, in: range, now: now) }.keys)
        let searchCount = sessionsWithSearch.intersection(sessionIDsInRange).count
        let nonSearchCount = max(0, sessionIDsInRange.count - searchCount)
        return ToolStatsSnapshot(
            totalToolCalls: totalToolCalls,
            distinctToolCount: counts.count,
            topTools: topTools,
            searchSessionCount: searchCount,
            nonSearchSessionCount: nonSearchCount
        )
    }

    func makeChangeStats(range: AnalyticsRange, patchEvents: [PatchEvent], now: Date) -> ChangeStatsSnapshot {
        let filtered = patchEvents.filter { contains($0.timestamp, in: range, now: now) }
        let buckets = range.usesHourlyBuckets ? hourBuckets(now: now) : dayBuckets(for: range, now: now)
        let grouped = Dictionary(grouping: filtered) { bucketStart(for: $0.timestamp, range: range) }
        let addedSeries = buckets.map { bucket in
            CountSeriesPoint(bucketStart: bucket, value: (grouped[bucket] ?? []).reduce(0) { $0 + $1.stats.addedLines })
        }
        let deletedSeries = buckets.map { bucket in
            CountSeriesPoint(bucketStart: bucket, value: (grouped[bucket] ?? []).reduce(0) { $0 + $1.stats.deletedLines })
        }
        let netSeries = zip(addedSeries, deletedSeries).map {
            CountSeriesPoint(bucketStart: $0.bucketStart, value: $0.value - $1.value)
        }
        return ChangeStatsSnapshot(
            totalAddedLines: filtered.reduce(0) { $0 + $1.stats.addedLines },
            totalDeletedLines: filtered.reduce(0) { $0 + $1.stats.deletedLines },
            totalNetLines: filtered.reduce(0) { $0 + $1.stats.addedLines - $1.stats.deletedLines },
            modifiedFiles: Set(filtered.flatMap { $0.stats.modifiedFiles }).count,
            addedSeries: addedSeries,
            deletedSeries: deletedSeries,
            netSeries: netSeries
        )
    }

    func makeLimitStats(
        range: AnalyticsRange,
        samples: [LimitSample],
        primaryLimit: RateLimitWindow?,
        secondaryLimit: RateLimitWindow?,
        now: Date
    ) -> LimitStatsSnapshot {
        let filtered = samples
            .filter { contains($0.timestamp, in: range, now: now) }
            .sorted { $0.timestamp < $1.timestamp }
        let bucketed = Dictionary(grouping: filtered) { bucketStart(for: $0.timestamp, range: range) }
        let orderedBuckets = (range.usesHourlyBuckets ? hourBuckets(now: now) : dayBuckets(for: range, now: now)).sorted()
        return LimitStatsSnapshot(
            primaryCurrentPercent: primaryLimit?.usedPercent,
            secondaryCurrentPercent: secondaryLimit?.usedPercent,
            primaryResetAt: primaryLimit?.resetsAt,
            secondaryResetAt: secondaryLimit?.resetsAt,
            primaryWarningLevel: AnalyticsWarningLevelCalculator.level(for: primaryLimit?.usedPercent),
            secondaryWarningLevel: AnalyticsWarningLevelCalculator.level(for: secondaryLimit?.usedPercent),
            primarySeries: orderedBuckets.compactMap { bucket in
                guard let last = bucketed[bucket]?.last(where: { $0.primaryPercent != nil }),
                      let percent = last.primaryPercent else { return nil }
                return TimedPercentPoint(timestamp: bucket, percent: percent)
            },
            secondarySeries: orderedBuckets.compactMap { bucket in
                guard let last = bucketed[bucket]?.last(where: { $0.secondaryPercent != nil }),
                      let percent = last.secondaryPercent else { return nil }
                return TimedPercentPoint(timestamp: bucket, percent: percent)
            }
        )
    }

    func makeModelStats(range: AnalyticsRange, modelSamples: [ModelSample], now: Date) -> ModelStatsSnapshot {
        let filtered = modelSamples.filter { contains($0.timestamp, in: range, now: now) }
        let grouped = Dictionary(grouping: filtered, by: \.modelName)
        let totalCount = filtered.count
        let usage = grouped.map { name, items in
            NamedCountItem(name: name, count: items.count, ratio: totalCount == 0 ? 0 : Double(items.count) / Double(totalCount))
        }
        .sorted { lhs, rhs in
            if lhs.count == rhs.count {
                return lhs.name < rhs.name
            }
            return lhs.count > rhs.count
        }

        let averages = grouped.map { name, items in
            NamedAverageItem(name: name, averageValue: items.isEmpty ? 0 : Double(items.reduce(0) { $0 + $1.averageTokenContribution }) / Double(items.count))
        }
        .sorted { lhs, rhs in
            if lhs.averageValue == rhs.averageValue {
                return lhs.name < rhs.name
            }
            return lhs.averageValue > rhs.averageValue
        }

        return ModelStatsSnapshot(
            modelUsageItems: usage,
            modelAverageTokenItems: averages,
            dominantModelName: usage.first?.name
        )
    }

    func makeProjectStats(range: AnalyticsRange, projectSamples: [ProjectSample], now: Date) -> ProjectStatsSnapshot {
        let filtered = projectSamples.filter { contains($0.timestamp, in: range, now: now) }
        let groupedByProject = Dictionary(grouping: filtered, by: \.projectName)
        let topProjects = groupedByProject
            .map { name, items in
                (name, items.reduce(0) { $0 + $1.tokens })
            }
            .sorted { lhs, rhs in
                if lhs.1 == rhs.1 {
                    return lhs.0 < rhs.0
                }
                return lhs.1 > rhs.1
            }
            .prefix(3)

        let buckets = range.usesHourlyBuckets ? hourBuckets(now: now) : dayBuckets(for: range, now: now)
        let series = topProjects.map { item in
            let points = buckets.map { bucket in
                let value = (groupedByProject[item.0] ?? [])
                    .filter { bucketStart(for: $0.timestamp, range: range) == bucket }
                    .reduce(0) { $0 + $1.tokens }
                return CountSeriesPoint(bucketStart: bucket, value: value)
            }
            return ProjectTokenSeries(projectName: item.0, points: points)
        }

        return ProjectStatsSnapshot(
            topProjects: series,
            projectCount: groupedByProject.count,
            highestTokenProjectName: topProjects.first?.0,
            highestTokenProjectValue: topProjects.first?.1 ?? 0
        )
    }

    func contains(_ date: Date, in range: AnalyticsRange, now: Date) -> Bool {
        switch range {
        case .today:
            return calendar.isDate(date, inSameDayAs: now)
        case .week:
            guard let start = calendar.date(byAdding: .day, value: -6, to: calendar.startOfDay(for: now)) else { return false }
            return date >= start && date <= now
        case .month:
            guard let start = calendar.date(byAdding: .day, value: -29, to: calendar.startOfDay(for: now)) else { return false }
            return date >= start && date <= now
        }
    }

    func dayBuckets(for range: AnalyticsRange, now: Date) -> [Date] {
        let dayCount = range == .week ? 7 : 30
        let startOfToday = calendar.startOfDay(for: now)
        return (0..<dayCount).map { offset in
            calendar.date(byAdding: .day, value: offset - (dayCount - 1), to: startOfToday) ?? startOfToday
        }
    }

    func hourBuckets(now: Date) -> [Date] {
        let startOfToday = calendar.startOfDay(for: now)
        return (0..<24).map { offset in
            calendar.date(byAdding: .hour, value: offset, to: startOfToday) ?? startOfToday
        }
    }

    func bucketStart(for timestamp: Date, range: AnalyticsRange) -> Date {
        if range.usesHourlyBuckets {
            return calendar.dateInterval(of: .hour, for: timestamp)?.start ?? timestamp
        }
        return calendar.startOfDay(for: timestamp)
    }

    func extractCodexToolName(payload: [String: Any], fallbackType: String) -> String? {
        if let name = payload["name"] as? String, !name.isEmpty {
            return name
        }
        if let tool = payload["tool"] as? String, !tool.isEmpty {
            return tool
        }
        return fallbackType == "web_search_call" ? "web_search_call" : fallbackType
    }

    func extractRateLimitPercent(named name: String, from limits: [String: Any]) -> Double? {
        guard let window = limits[name] as? [String: Any] else { return nil }
        if let value = window["used_percent"] as? Double {
            return value
        }
        if let value = window["used_percent"] as? Int {
            return Double(value)
        }
        return nil
    }

    func extractCodexTokenUsage(from payload: [String: Any]) -> (inputTokens: Int, outputTokens: Int, reasoningTokens: Int, totalTokens: Int) {
        let sources = [
            payload["last_token_usage"],
            (payload["info"] as? [String: Any])?["last_token_usage"],
            payload["token_usage"],
            payload["usage"],
            payload["info"]
        ]
        for source in sources {
            guard let usage = source as? [String: Any] else { continue }
            let input = intValue(in: usage, keys: ["input_tokens", "inputTokens"])
            let output = intValue(in: usage, keys: ["output_tokens", "outputTokens"])
            let reasoning = intValue(in: usage, keys: ["reasoning_tokens", "reasoningTokens", "reasoning_output_tokens"])
            let explicitTotal = intValue(in: usage, keys: ["total_tokens", "totalTokens"])
            let total = explicitTotal > 0 ? explicitTotal : (input + output + reasoning)
            if total > 0 {
                return (input, output, reasoning, total)
            }
        }
        return (0, 0, 0, 0)
    }

    func extractGeminiTokenUsage(from item: [String: Any]) -> (inputTokens: Int, outputTokens: Int, totalTokens: Int) {
        if let tokens = item["tokens"] as? [String: Any] {
            let input = intValue(in: tokens, keys: ["input"])
            let output = intValue(in: tokens, keys: ["output"])
            let total = max(intValue(in: tokens, keys: ["total"]), input + output)
            return (input, output, total)
        }
        let sources = [item["usage"], (item["message"] as? [String: Any])?["usage"]]
        for source in sources {
            guard let usage = source as? [String: Any] else { continue }
            let input = intValue(in: usage, keys: ["input_tokens", "inputTokens", "prompt_tokens", "promptTokenCount"])
            let output = intValue(in: usage, keys: ["output_tokens", "outputTokens", "completion_tokens", "candidatesTokenCount"])
            let total = max(intValue(in: usage, keys: ["total_tokens", "totalTokens", "totalTokenCount"]), input + output)
            if total > 0 {
                return (input, output, total)
            }
        }
        return (0, 0, 0)
    }

    func extractGeminiModel(from item: [String: Any]) -> String? {
        if let model = item["model"] as? String, !model.isEmpty {
            return model
        }
        if let message = item["message"] as? [String: Any],
           let model = message["model"] as? String, !model.isEmpty {
            return model
        }
        return nil
    }

    func geminiProjectName(for fileURL: URL) -> String {
        let parent = fileURL.deletingLastPathComponent().lastPathComponent
        if parent == "chats" {
            let project = fileURL.deletingLastPathComponent().deletingLastPathComponent().lastPathComponent
            if !project.isEmpty && project != "tmp" {
                return project
            }
        }
        let direct = fileURL.deletingLastPathComponent().lastPathComponent
        if !direct.isEmpty && direct != "tmp" {
            return direct
        }
        let stem = fileURL.deletingPathExtension().lastPathComponent
        return stem.isEmpty ? "Unknown" : stem
    }

    func intValue(in dictionary: [String: Any], keys: [String]) -> Int {
        for key in keys {
            if let value = dictionary[key] as? Int {
                return value
            }
            if let value = dictionary[key] as? Double {
                return Int(value)
            }
            if let value = dictionary[key] as? String, let int = Int(value) {
                return int
            }
        }
        return 0
    }
}
