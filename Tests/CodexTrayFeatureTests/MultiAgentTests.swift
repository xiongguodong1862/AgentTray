import XCTest
@testable import CodexTrayFeature

final class MultiAgentTests: XCTestCase {
    func testGeminiSnapshotBuilderPrefersChatSessionsOverLogsFallback() throws {
        let tempHome = URL(fileURLWithPath: NSTemporaryDirectory())
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        let projectRoot = tempHome.appending(path: ".gemini/tmp/codextray", directoryHint: .isDirectory)
        let chatsRoot = projectRoot.appending(path: "chats", directoryHint: .isDirectory)
        let settingsURL = tempHome.appending(path: ".gemini/settings.json")
        try FileManager.default.createDirectory(at: chatsRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempHome) }

        let chatSession = """
        {
          "sessionId": "session-chat-1",
          "startTime": "2026-03-24T10:29:17.569Z",
          "lastUpdated": "2026-03-24T10:31:35.759Z",
          "messages": [
            {
              "id": "u1",
              "timestamp": "2026-03-24T10:29:17.569Z",
              "type": "user",
              "content": [{ "text": "你好" }]
            },
            {
              "id": "a1",
              "timestamp": "2026-03-24T10:29:21.179Z",
              "type": "gemini",
              "content": "你好",
              "tokens": {
                "input": 6943,
                "output": 69,
                "cached": 0,
                "thoughts": 142,
                "tool": 0,
                "total": 7154
              },
              "model": "gemini-3-flash-preview"
            },
            {
              "id": "u2",
              "timestamp": "2026-03-24T10:31:31.925Z",
              "type": "user",
              "content": [{ "text": "你当前用的什么模型" }]
            },
            {
              "id": "a2",
              "timestamp": "2026-03-24T10:31:35.759Z",
              "type": "gemini",
              "content": "Gemini 2.0 Flash",
              "tokens": {
                "input": 7017,
                "output": 101,
                "cached": 5900,
                "thoughts": 0,
                "tool": 0,
                "total": 7118
              },
              "model": "gemini-3-flash-preview"
            }
          ],
          "kind": "main"
        }
        """
        try chatSession.write(
            to: chatsRoot.appending(path: "session-2026-03-24T10-29-4c164546.json"),
            atomically: true,
            encoding: .utf8
        )

        let fallbackLogs = """
        [
          {
            "sessionId": "session-log-1",
            "messageId": 0,
            "type": "user",
            "message": "这条不应该优先被使用",
            "timestamp": "2026-03-24T11:00:00.000Z"
          }
        ]
        """
        try fallbackLogs.write(
            to: projectRoot.appending(path: "logs.json"),
            atomically: true,
            encoding: .utf8
        )

        try FileManager.default.createDirectory(
            at: settingsURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try """
        {
          "security": {
            "auth": {
              "selectedType": "oauth-personal"
            }
          }
        }
        """.write(to: settingsURL, atomically: true, encoding: .utf8)

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .current
        let builder = GeminiUsageSnapshotBuilder(
            logsRoot: tempHome.appending(path: ".gemini/tmp", directoryHint: .isDirectory),
            settingsURL: settingsURL,
            calendar: calendar
        )

        let snapshot = try builder.build(now: ISO8601DateParser.parse("2026-03-24T12:00:00.000Z") ?? .now)

        XCTAssertTrue(snapshot.isAvailable)
        XCTAssertEqual(snapshot.currentModel, "gemini-3-flash-preview")
        XCTAssertEqual(snapshot.today.dialogs, 1)
        XCTAssertEqual(snapshot.today.tokenUsage, 14_272)
        XCTAssertEqual(snapshot.today.toolCalls, 0)
        XCTAssertEqual(snapshot.status.primaryLabel, "今日 Token")
        XCTAssertEqual(snapshot.status.primaryValue, "14.3K")
        XCTAssertNil(snapshot.status.secondaryValue)
    }

    func testGeminiSnapshotBuilderParsesLogsJSONSessionsTokensAndModel() throws {
        let tempHome = URL(fileURLWithPath: NSTemporaryDirectory())
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        let logsRoot = tempHome
            .appending(path: ".gemini/tmp/codextray", directoryHint: .isDirectory)
        let settingsURL = tempHome.appending(path: ".gemini/settings.json")
        try FileManager.default.createDirectory(at: logsRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempHome) }

        let logs = """
        [
          {
            "sessionId": "session-1",
            "messageId": 0,
            "type": "user",
            "message": "你好",
            "timestamp": "2026-03-24T10:29:14.498Z"
          },
          {
            "sessionId": "session-1",
            "messageId": 1,
            "type": "assistant",
            "model": "gemini-2.5-pro",
            "usage": {
              "input_tokens": 1200,
              "output_tokens": 300
            },
            "message": {
              "content": [
                { "type": "text", "text": "你好" },
                { "type": "tool_use", "name": "read_file" }
              ]
            },
            "timestamp": "2026-03-24T10:31:14.498Z"
          }
        ]
        """
        try logs.write(
            to: logsRoot.appending(path: "logs.json"),
            atomically: true,
            encoding: .utf8
        )

        try FileManager.default.createDirectory(
            at: settingsURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try """
        {
          "security": {
            "auth": {
              "selectedType": "oauth-personal"
            }
          }
        }
        """.write(to: settingsURL, atomically: true, encoding: .utf8)

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .current
        let builder = GeminiUsageSnapshotBuilder(
            logsRoot: tempHome.appending(path: ".gemini/tmp", directoryHint: .isDirectory),
            settingsURL: settingsURL,
            calendar: calendar
        )

        let snapshot = try builder.build(now: ISO8601DateParser.parse("2026-03-24T12:00:00.000Z") ?? .now)

        XCTAssertTrue(snapshot.isAvailable)
        XCTAssertEqual(snapshot.currentModel, "gemini-2.5-pro")
        XCTAssertEqual(snapshot.today.dialogs, 1)
        XCTAssertEqual(snapshot.today.tokenUsage, 1_500)
        XCTAssertEqual(snapshot.today.toolCalls, 1)
        XCTAssertEqual(snapshot.status.primaryLabel, "今日 Token")
        XCTAssertEqual(snapshot.status.primaryValue, "1.5K")
        XCTAssertNil(snapshot.status.secondaryValue)
        XCTAssertEqual(snapshot.environment.authLabel, "oauth-personal")
    }

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
        XCTAssertEqual(snapshot.status.primaryLabel, "今日 Token")
        XCTAssertEqual(snapshot.status.primaryValue, "2.5K")
        XCTAssertNil(snapshot.status.secondaryValue)
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
