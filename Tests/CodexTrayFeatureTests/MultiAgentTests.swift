import XCTest
@testable import CodexTrayFeature

final class MultiAgentTests: XCTestCase {
    func testClaudeSnapshotBuilderParsesSessionsTokensAndModel() throws {
        let tempHome = URL(fileURLWithPath: NSTemporaryDirectory())
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        let projectRoot = tempHome
            .appending(path: ".claude/projects/sample", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: projectRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempHome) }

        let sessionLog = """
        {"sessionId":"session-1","type":"user","timestamp":"2026-03-24T01:00:00.000Z"}
        {"sessionId":"session-1","type":"assistant","timestamp":"2026-03-24T01:02:00.000Z","message":{"model":"claude-sonnet-4-5","usage":{"input_tokens":1200,"output_tokens":300},"content":[{"type":"text","text":"ok"},{"type":"tool_use","name":"Read","input":{"file_path":"/tmp/a"}}]}}
        {"sessionId":"session-2","type":"user","timestamp":"2026-03-24T05:00:00.000Z"}
        {"sessionId":"session-2","type":"assistant","timestamp":"2026-03-24T05:03:00.000Z","message":{"model":"claude-sonnet-4-5","usage":{"input_tokens":800,"output_tokens":200},"content":[{"type":"tool_use","name":"Edit","input":{"file_path":"/tmp/b"}}]}}
        """
        try sessionLog.write(
            to: projectRoot.appending(path: "session.jsonl"),
            atomically: true,
            encoding: .utf8
        )

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .current
        let builder = ClaudeUsageSnapshotBuilder(homeDirectory: tempHome, calendar: calendar)

        let snapshot = try builder.build(now: ISO8601DateParser.parse("2026-03-24T12:00:00.000Z") ?? .now)

        XCTAssertTrue(snapshot.isAvailable)
        XCTAssertEqual(snapshot.currentModel, "claude-sonnet-4-5")
        XCTAssertEqual(snapshot.today.dialogs, 2)
        XCTAssertEqual(snapshot.today.tokenUsage, 2_500)
        XCTAssertEqual(snapshot.today.toolCalls, 2)
        XCTAssertEqual(snapshot.status.primaryValue, "2.5K")
        XCTAssertEqual(snapshot.status.secondaryValue, "2")
    }

    func testMultiAgentSnapshotBuilderCreatesAggregateSummary() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let day = Calendar.current.startOfDay(for: now)
        let codexSnapshot = UsageSnapshot(
            generatedAt: now,
            primaryLimit: nil,
            secondaryLimit: nil,
            today: UsageMetricsDay(
                date: day,
                dialogs: 3,
                activeMinutes: 45,
                modifiedFiles: 2,
                addedLines: 20,
                deletedLines: 5
            ),
            lastSevenDays: (0..<7).map { offset in
                UsageMetricsDay(
                    date: Calendar.current.date(byAdding: .day, value: offset - 6, to: day) ?? day,
                    dialogs: 1,
                    activeMinutes: 10,
                    modifiedFiles: 1,
                    addedLines: 4,
                    deletedLines: 1
                )
            },
            lastYearDays: (0..<365).map { offset in
                UsageMetricsDay(
                    date: Calendar.current.date(byAdding: .day, value: offset - 364, to: day) ?? day,
                    dialogs: offset == 364 ? 3 : 0,
                    activeMinutes: offset == 364 ? 45 : 0,
                    modifiedFiles: offset == 364 ? 2 : 0,
                    addedLines: offset == 364 ? 20 : 0,
                    deletedLines: offset == 364 ? 5 : 0
                )
            },
            pet: PetProgress(level: 0, stage: .cursorEgg, currentXP: 0, nextLevelXP: 180, todayXP: 0),
            hasSourceData: true
        )
        let environment = CodexEnvironmentInfo(
            environmentLabel: "CLI",
            authMethodLabel: "ChatGPT OAuth",
            codexHomePath: "~/.codex",
            sqliteHomePath: "~/.codex",
            authStorageLabel: "file",
            authModeLabel: "chatgpt",
            authFileExists: true
        )

        let snapshot = MultiAgentSnapshotBuilder().placeholder(
            codexSnapshot: codexSnapshot,
            codexEnvironment: environment,
            focusedAgent: .codex
        )

        XCTAssertEqual(snapshot.agents.count, 3)
        XCTAssertEqual(snapshot.todaySummary.totalSessions, 3)
        XCTAssertEqual(snapshot.todaySummary.totalActiveMinutes, 45)
        XCTAssertEqual(snapshot.mostRecentlyActiveAgent, .codex)
        XCTAssertEqual(snapshot.focusedAgent, .codex)
    }
}
