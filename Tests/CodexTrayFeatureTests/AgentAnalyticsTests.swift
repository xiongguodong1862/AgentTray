import XCTest
@testable import CodexTrayFeature
import SQLite3

final class AgentAnalyticsTests: XCTestCase {
    func testAnalyticsRangeAndTabDefinitionsMatchSpec() {
        XCTAssertEqual(AnalyticsRange.allCases.map(\.title), ["Today", "This Week", "This Month"])
        XCTAssertTrue(AnalyticsRange.today.usesHourlyBuckets)
        XCTAssertFalse(AnalyticsRange.week.usesHourlyBuckets)
        XCTAssertEqual(AgentAnalyticsTab.tabs(for: .codex), [.activity, .sessions, .tokens, .tools, .changes, .limits])
        XCTAssertEqual(AgentAnalyticsTab.tabs(for: .claude), [.activity, .sessions, .tokens, .tools])
        XCTAssertEqual(AgentAnalyticsTab.tabs(for: .gemini), [.activity, .sessions, .tokens, .models, .projects])
    }

    func testSingleAgentAnalyticsPanelHeightShrinksForCompactTabs() {
        let codexActivity = AgentAnalyticsLayout.preferredPanelHeight(
            agent: .codex,
            tab: .activity,
            analyticsRange: .today,
            activityRange: .week
        )
        let codexLimits = AgentAnalyticsLayout.preferredPanelHeight(
            agent: .codex,
            tab: .limits,
            analyticsRange: .month,
            activityRange: .year
        )
        let claudeActivity = AgentAnalyticsLayout.preferredPanelHeight(
            agent: .claude,
            tab: .activity,
            analyticsRange: .today,
            activityRange: .month
        )
        let claudeTools = AgentAnalyticsLayout.preferredPanelHeight(
            agent: .claude,
            tab: .tools,
            analyticsRange: .month,
            activityRange: .week
        )

        XCTAssertLessThan(codexLimits, codexActivity)
        XCTAssertLessThan(claudeTools, claudeActivity)
    }

    func testSingleAgentActivityPanelHeightTracksHeatmapRange() {
        let codexWeek = AgentAnalyticsLayout.preferredPanelHeight(
            agent: .codex,
            tab: .activity,
            analyticsRange: .today,
            activityRange: .week
        )
        let codexMonth = AgentAnalyticsLayout.preferredPanelHeight(
            agent: .codex,
            tab: .activity,
            analyticsRange: .today,
            activityRange: .month
        )
        let codexYear = AgentAnalyticsLayout.preferredPanelHeight(
            agent: .codex,
            tab: .activity,
            analyticsRange: .today,
            activityRange: .year
        )

        XCTAssertEqual(codexMonth, 728)
        XCTAssertLessThan(codexWeek, codexMonth)
        XCTAssertLessThan(codexYear, codexMonth)
        XCTAssertNotEqual(codexWeek, codexYear)
    }

    func testTokenPanelKeepsMoreHeightThanOtherCompactTabs() {
        let claudeSessions = AgentAnalyticsLayout.preferredPanelHeight(
            agent: .claude,
            tab: .sessions,
            analyticsRange: .today,
            activityRange: .month
        )
        let claudeTokens = AgentAnalyticsLayout.preferredPanelHeight(
            agent: .claude,
            tab: .tokens,
            analyticsRange: .today,
            activityRange: .month
        )

        XCTAssertGreaterThan(claudeTokens, claudeSessions)
    }

    func testCodexLimitsPanelIsShorterAfterRemovingSummaryStrip() {
        let codexLimits = AgentAnalyticsLayout.preferredPanelHeight(
            agent: .codex,
            tab: .limits,
            analyticsRange: .week,
            activityRange: .month
        )
        let codexTokens = AgentAnalyticsLayout.preferredPanelHeight(
            agent: .codex,
            tab: .tokens,
            analyticsRange: .week,
            activityRange: .month
        )

        XCTAssertLessThan(codexLimits, codexTokens)
    }

    func testBucketLabelStyleUsesDateAndWeekdayForDailySeries() {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: Date(timeIntervalSinceReferenceDate: 0))
        let dates = (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: start) }

        XCTAssertEqual(AnalyticsDateFormatter.labelStyle(for: dates), .dateWithWeekday)
    }

    func testBucketLabelStyleUsesTimeForHourlySeries() {
        let calendar = Calendar.current
        let start = Date(timeIntervalSinceReferenceDate: 0)
        let dates = (0..<7).compactMap { calendar.date(byAdding: .hour, value: $0, to: start) }

        XCTAssertEqual(AnalyticsDateFormatter.labelStyle(for: dates), .timeOfDay)
    }

    func testLimitWarningLevelThresholdsMatchSpec() {
        XCTAssertEqual(AnalyticsWarningLevelCalculator.level(for: nil), .none)
        XCTAssertEqual(AnalyticsWarningLevelCalculator.level(for: 79.9), .none)
        XCTAssertEqual(AnalyticsWarningLevelCalculator.level(for: 80), .warning)
        XCTAssertEqual(AnalyticsWarningLevelCalculator.level(for: 89.9), .warning)
        XCTAssertEqual(AnalyticsWarningLevelCalculator.level(for: 90), .critical)
    }

    func testCodexAnalyticsBuilderAggregatesSessionsTokensToolsChangesAndLimits() throws {
        let tempRoot = URL(fileURLWithPath: NSTemporaryDirectory())
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        let sessionsRoot = tempRoot.appending(path: "sessions/2026/03/24", directoryHint: .isDirectory)
        let databaseURL = tempRoot.appending(path: "state.sqlite")
        let claudeRoot = tempRoot.appending(path: "claude", directoryHint: .isDirectory)
        let geminiRoot = tempRoot.appending(path: "gemini", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: sessionsRoot, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: claudeRoot, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: geminiRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        let session = """
        {"timestamp":"2026-03-24T01:00:00.000Z","type":"session_meta","payload":{"id":"thread-1","timestamp":"2026-03-24T01:00:00.000Z"}}
        {"timestamp":"2026-03-24T01:05:00.000Z","type":"event_msg","payload":{"type":"user_message"}}
        {"timestamp":"2026-03-24T01:07:00.000Z","type":"event_msg","payload":{"type":"agent_message"}}
        {"timestamp":"2026-03-24T01:09:00.000Z","type":"event_msg","payload":{"type":"token_count","last_token_usage":{"input_tokens":100,"output_tokens":40,"reasoning_tokens":10,"total_tokens":150},"rate_limits":{"primary":{"used_percent":85,"window_minutes":300,"resets_at":1774314000},"secondary":{"used_percent":91,"window_minutes":10080,"resets_at":1774861200}}}}
        {"timestamp":"2026-03-24T01:10:00.000Z","type":"response_item","payload":{"type":"function_call","name":"read_file"}}
        {"timestamp":"2026-03-24T01:11:00.000Z","type":"response_item","payload":{"type":"web_search_call","name":"web_search_call"}}
        """
        try session.write(to: sessionsRoot.appending(path: "thread-1.jsonl"), atomically: true, encoding: .utf8)

        var db: OpaquePointer?
        XCTAssertEqual(sqlite3_open(databaseURL.path, &db), SQLITE_OK)
        defer { sqlite3_close(db) }
        XCTAssertEqual(sqlite3_exec(db, "CREATE TABLE logs (ts REAL, message TEXT);", nil, nil, nil), SQLITE_OK)
        let patchText = """
        ToolCall: apply_patch
        *** Begin Patch
        *** Update File: foo.swift
        +new
        -old
        *** End Patch
        """
        let patchTimestamp = try XCTUnwrap(ISO8601DateParser.parse("2026-03-24T01:10:00.000Z")).timeIntervalSince1970
        let insert = "INSERT INTO logs (ts, message) VALUES (\(patchTimestamp), '\(patchText.replacingOccurrences(of: "'", with: "''"))');"
        XCTAssertEqual(sqlite3_exec(db, insert, nil, nil, nil), SQLITE_OK)

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .current
        let builder = AgentAnalyticsBuilder(
            codexSessionsRoot: tempRoot.appending(path: "sessions"),
            codexStateDatabaseURL: databaseURL,
            claudeProjectsRoot: claudeRoot,
            geminiLogsRoot: geminiRoot,
            calendar: calendar
        )

        let now = try XCTUnwrap(ISO8601DateParser.parse("2026-03-24T12:00:00.000Z"))
        let analytics = builder.buildCodex(
            now: now,
            primaryLimit: RateLimitWindow(usedPercent: 85, windowMinutes: 300, resetsAt: try XCTUnwrap(ISO8601DateParser.parse("2026-03-24T17:00:00.000Z"))),
            secondaryLimit: RateLimitWindow(usedPercent: 91, windowMinutes: 10080, resetsAt: try XCTUnwrap(ISO8601DateParser.parse("2026-03-29T17:00:00.000Z")))
        )

        XCTAssertEqual(analytics.sessionStatsToday.totalSessions, 1)
        XCTAssertEqual(analytics.sessionStatsToday.averageTurnsPerSession, 1, accuracy: 0.001)
        XCTAssertEqual(analytics.tokenStatsToday.totalTokens, 150)
        XCTAssertEqual(analytics.tokenStatsToday.inputTokens, 100)
        XCTAssertEqual(analytics.tokenStatsToday.outputTokens, 40)
        XCTAssertEqual(analytics.tokenStatsToday.reasoningTokens, 10)
        XCTAssertEqual(analytics.toolStatsToday?.totalToolCalls, 2)
        XCTAssertEqual(analytics.toolStatsToday?.searchSessionCount, 1)
        XCTAssertEqual(analytics.changeStatsToday?.totalAddedLines, 1)
        XCTAssertEqual(analytics.changeStatsToday?.totalDeletedLines, 1)
        XCTAssertEqual(analytics.limitStatsToday?.primaryWarningLevel, .warning)
        XCTAssertEqual(analytics.limitStatsToday?.secondaryWarningLevel, .critical)
    }

    func testGeminiAnalyticsBuilderAggregatesModelAndProjectStats() throws {
        let tempRoot = URL(fileURLWithPath: NSTemporaryDirectory())
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        let chatsRoot = tempRoot.appending(path: ".gemini/tmp/demo/chats", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: chatsRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        let chat = """
        {
          "sessionId": "session-1",
          "messages": [
            { "id": "u1", "timestamp": "2026-03-24T02:00:00.000Z", "type": "user" },
            { "id": "a1", "timestamp": "2026-03-24T02:01:00.000Z", "type": "gemini", "model": "gemini-2.5-pro", "tokens": { "input": 80, "output": 20, "total": 100 } },
            { "id": "a2", "timestamp": "2026-03-24T04:01:00.000Z", "type": "gemini", "model": "gemini-2.5-pro", "tokens": { "input": 40, "output": 10, "total": 50 } }
          ]
        }
        """
        try chat.write(to: chatsRoot.appending(path: "session-1.json"), atomically: true, encoding: .utf8)

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .current
        let builder = AgentAnalyticsBuilder(
            codexSessionsRoot: tempRoot.appending(path: "sessions"),
            codexStateDatabaseURL: tempRoot.appending(path: "state.sqlite"),
            claudeProjectsRoot: tempRoot.appending(path: "claude"),
            geminiLogsRoot: tempRoot.appending(path: ".gemini/tmp"),
            calendar: calendar
        )

        let analytics = builder.buildGemini(now: try XCTUnwrap(ISO8601DateParser.parse("2026-03-24T12:00:00.000Z")))

        XCTAssertEqual(analytics.sessionStatsToday.totalSessions, 1)
        XCTAssertEqual(analytics.tokenStatsToday.totalTokens, 150)
        XCTAssertEqual(analytics.modelStatsToday?.dominantModelName, "gemini-2.5-pro")
        XCTAssertEqual(try XCTUnwrap(analytics.modelStatsToday?.modelAverageTokenItems.first?.averageValue), 75, accuracy: 0.001)
        XCTAssertEqual(analytics.projectStatsToday?.projectCount, 1)
        XCTAssertEqual(analytics.projectStatsToday?.highestTokenProjectName, "demo")
        XCTAssertEqual(analytics.projectStatsToday?.highestTokenProjectValue, 150)
    }

    func testClaudeAnalyticsBuilderIgnoresEntriesOlderThanLast30Days() throws {
        let tempRoot = URL(fileURLWithPath: NSTemporaryDirectory())
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        let claudeRoot = tempRoot.appending(path: ".claude/projects/sample", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: claudeRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        let sessionLog = """
        {"sessionId":"old-session","type":"assistant","timestamp":"2026-02-20T01:02:00.000Z","message":{"model":"claude-sonnet-4-5","usage":{"input_tokens":900,"output_tokens":100},"content":[]}}
        {"sessionId":"recent-session","type":"assistant","timestamp":"2026-03-24T05:03:00.000Z","message":{"model":"claude-sonnet-4-5","usage":{"input_tokens":800,"output_tokens":200},"content":[]}}
        """
        try sessionLog.write(
            to: claudeRoot.appending(path: "session.jsonl"),
            atomically: true,
            encoding: .utf8
        )

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .current
        let builder = AgentAnalyticsBuilder(
            codexSessionsRoot: tempRoot.appending(path: "sessions"),
            codexStateDatabaseURL: tempRoot.appending(path: "state.sqlite"),
            claudeProjectsRoot: tempRoot.appending(path: ".claude/projects"),
            geminiLogsRoot: tempRoot.appending(path: ".gemini/tmp"),
            calendar: calendar
        )

        let analytics = builder.buildClaude(now: try XCTUnwrap(ISO8601DateParser.parse("2026-03-24T12:00:00.000Z")))

        XCTAssertEqual(analytics.tokenStatsMonth.totalTokens, 1_000)
        XCTAssertEqual(analytics.sessionStatsMonth.totalSessions, 1)
    }

    func testGeminiAnalyticsBuilderIgnoresEntriesOlderThanLast30Days() throws {
        let tempRoot = URL(fileURLWithPath: NSTemporaryDirectory())
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        let chatsRoot = tempRoot.appending(path: ".gemini/tmp/demo/chats", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: chatsRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        let chat = """
        {
          "sessionId": "session-1",
          "messages": [
            { "id": "a0", "timestamp": "2026-02-20T02:01:00.000Z", "type": "gemini", "model": "gemini-2.5-pro", "tokens": { "input": 90, "output": 10, "total": 100 } },
            { "id": "a1", "timestamp": "2026-03-24T02:01:00.000Z", "type": "gemini", "model": "gemini-2.5-pro", "tokens": { "input": 80, "output": 20, "total": 100 } },
            { "id": "a2", "timestamp": "2026-03-24T04:01:00.000Z", "type": "gemini", "model": "gemini-2.5-pro", "tokens": { "input": 40, "output": 10, "total": 50 } }
          ]
        }
        """
        try chat.write(to: chatsRoot.appending(path: "session-1.json"), atomically: true, encoding: .utf8)

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .current
        let builder = AgentAnalyticsBuilder(
            codexSessionsRoot: tempRoot.appending(path: "sessions"),
            codexStateDatabaseURL: tempRoot.appending(path: "state.sqlite"),
            claudeProjectsRoot: tempRoot.appending(path: ".claude/projects"),
            geminiLogsRoot: tempRoot.appending(path: ".gemini/tmp"),
            calendar: calendar
        )

        let analytics = builder.buildGemini(now: try XCTUnwrap(ISO8601DateParser.parse("2026-03-24T12:00:00.000Z")))

        XCTAssertEqual(analytics.tokenStatsMonth.totalTokens, 150)
        XCTAssertEqual(analytics.projectStatsMonth?.highestTokenProjectValue, 150)
    }

    func testCodexTokenUsageFallsBackToInfoLastTokenUsage() throws {
        let tempRoot = URL(fileURLWithPath: NSTemporaryDirectory())
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        let sessionsRoot = tempRoot.appending(path: "sessions/2026/03/26", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: sessionsRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        let session = """
        {"timestamp":"2026-03-26T08:55:42.000Z","type":"session_meta","payload":{"id":"thread-1","timestamp":"2026-03-26T08:55:42.000Z"}}
        {"timestamp":"2026-03-26T08:55:58.794Z","type":"event_msg","payload":{"type":"token_count","info":{"last_token_usage":{"input_tokens":39020,"output_tokens":267,"reasoning_output_tokens":50,"total_tokens":39287}}}}
        """
        try session.write(to: sessionsRoot.appending(path: "thread-1.jsonl"), atomically: true, encoding: .utf8)

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .current
        let builder = AgentAnalyticsBuilder(
            codexSessionsRoot: tempRoot.appending(path: "sessions"),
            codexStateDatabaseURL: tempRoot.appending(path: "state.sqlite"),
            claudeProjectsRoot: tempRoot.appending(path: "claude"),
            geminiLogsRoot: tempRoot.appending(path: "gemini"),
            calendar: calendar
        )

        let analytics = builder.buildCodex(
            now: try XCTUnwrap(ISO8601DateParser.parse("2026-03-26T12:00:00.000Z")),
            primaryLimit: nil,
            secondaryLimit: nil
        )

        XCTAssertEqual(analytics.tokenStatsToday.totalTokens, 39287)
        XCTAssertEqual(analytics.tokenStatsToday.inputTokens, 39020)
        XCTAssertEqual(analytics.tokenStatsToday.outputTokens, 267)
        XCTAssertEqual(analytics.tokenStatsToday.reasoningTokens, 50)
    }

    func testCodexWeeklyLimitSeriesKeepsLatestSamplePerDay() throws {
        let tempRoot = URL(fileURLWithPath: NSTemporaryDirectory())
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        let sessionsRoot = tempRoot.appending(path: "sessions/2026/03/24", directoryHint: .isDirectory)
        let databaseURL = tempRoot.appending(path: "state.sqlite")
        try FileManager.default.createDirectory(at: sessionsRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        let session = """
        {"timestamp":"2026-03-24T01:00:00.000Z","type":"session_meta","payload":{"id":"thread-1","timestamp":"2026-03-24T01:00:00.000Z"}}
        {"timestamp":"2026-03-24T01:05:00.000Z","type":"event_msg","payload":{"type":"token_count","rate_limits":{"primary":{"used_percent":10},"secondary":{"used_percent":50}}}}
        {"timestamp":"2026-03-24T18:05:00.000Z","type":"event_msg","payload":{"type":"token_count","rate_limits":{"primary":{"used_percent":12},"secondary":{"used_percent":52}}}}
        {"timestamp":"2026-03-25T08:05:00.000Z","type":"event_msg","payload":{"type":"token_count","rate_limits":{"primary":{"used_percent":20},"secondary":{"used_percent":60}}}}
        """
        try session.write(to: sessionsRoot.appending(path: "thread-1.jsonl"), atomically: true, encoding: .utf8)

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .current
        let builder = AgentAnalyticsBuilder(
            codexSessionsRoot: tempRoot.appending(path: "sessions"),
            codexStateDatabaseURL: databaseURL,
            claudeProjectsRoot: tempRoot.appending(path: "claude"),
            geminiLogsRoot: tempRoot.appending(path: "gemini"),
            calendar: calendar
        )

        let analytics = builder.buildCodex(
            now: try XCTUnwrap(ISO8601DateParser.parse("2026-03-26T12:00:00.000Z")),
            primaryLimit: nil,
            secondaryLimit: nil
        )

        XCTAssertEqual(analytics.limitStatsWeek?.primarySeries.count, 2)
        XCTAssertEqual(analytics.limitStatsWeek?.secondarySeries.count, 2)
        XCTAssertEqual(analytics.limitStatsWeek?.primarySeries.first?.percent, 12)
        XCTAssertEqual(analytics.limitStatsWeek?.secondarySeries.first?.percent, 52)
    }
}
