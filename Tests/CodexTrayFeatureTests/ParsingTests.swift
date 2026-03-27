import XCTest
@testable import CodexTrayFeature

final class ParsingTests: XCTestCase {
    func testCodexInstallationLocatorUsesDefaultCodexHomeWithoutOverrides() throws {
        let tempHome = URL(fileURLWithPath: NSTemporaryDirectory())
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: tempHome, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempHome) }

        let installation = CodexInstallationLocator(
            environment: [:],
            homeDirectory: tempHome
        ).locate()

        XCTAssertEqual(installation.codexHome, tempHome.appending(path: ".codex"))
        XCTAssertEqual(installation.sessionsRoot, tempHome.appending(path: ".codex/sessions"))
        XCTAssertEqual(installation.sqliteHome, tempHome.appending(path: ".codex"))
        XCTAssertEqual(installation.stateDatabaseURL, tempHome.appending(path: ".codex/state_5.sqlite"))
        XCTAssertEqual(installation.surfaceKind, .unknown)
        XCTAssertEqual(installation.auth.storagePreference, .unknown)
        XCTAssertEqual(installation.auth.authFileURL, tempHome.appending(path: ".codex/auth.json"))
        XCTAssertFalse(installation.auth.authFileExists)
    }

    func testCodexInstallationLocatorUsesConfiguredSQLiteHomeAndKeyringPreference() throws {
        let tempRoot = URL(fileURLWithPath: NSTemporaryDirectory())
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        let codexHome = tempRoot.appending(path: "custom-codex-home", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: codexHome, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        let config = """
        sqlite_home = "sqlite-store"
        cli_auth_credentials_store = "keyring"
        """
        try config.write(
            to: codexHome.appending(path: "config.toml"),
            atomically: true,
            encoding: .utf8
        )

        let installation = CodexInstallationLocator(
            environment: ["CODEX_HOME": codexHome.path],
            homeDirectory: tempRoot
        ).locate()

        XCTAssertEqual(installation.codexHome, codexHome)
        XCTAssertEqual(installation.sessionsRoot, codexHome.appending(path: "sessions"))
        XCTAssertEqual(installation.sqliteHome, codexHome.appending(path: "sqlite-store"))
        XCTAssertEqual(installation.stateDatabaseURL, codexHome.appending(path: "sqlite-store/state_5.sqlite"))
        XCTAssertEqual(installation.surfaceKind, .unknown)
        XCTAssertEqual(installation.auth.storagePreference, .keyring)
        XCTAssertEqual(installation.auth.authFileURL, codexHome.appending(path: "auth.json"))
        XCTAssertFalse(installation.auth.authFileExists)
    }

    func testCodexInstallationLocatorLetsCODEXSQLITEHOMEOverrideConfigAndReadsAuthFile() throws {
        let tempRoot = URL(fileURLWithPath: NSTemporaryDirectory())
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        let codexHome = tempRoot.appending(path: "codex-home", directoryHint: .isDirectory)
        let sqliteHome = tempRoot.appending(path: "sqlite-home", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: codexHome, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: sqliteHome, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        let config = """
        sqlite_home = "ignored-by-env"
        cli_auth_credentials_store = "file"
        """
        try config.write(
            to: codexHome.appending(path: "config.toml"),
            atomically: true,
            encoding: .utf8
        )

        let authJSON = """
        {
          "auth_mode": "chatgpt",
          "OPENAI_API_KEY": "sk-test",
          "tokens": {
            "id_token": "id-token",
            "access_token": "access-token",
            "refresh_token": "refresh-token"
          }
        }
        """
        try authJSON.write(
            to: codexHome.appending(path: "auth.json"),
            atomically: true,
            encoding: .utf8
        )

        let installation = CodexInstallationLocator(
            environment: [
                "CODEX_HOME": codexHome.path,
                "CODEX_SQLITE_HOME": sqliteHome.path,
            ],
            homeDirectory: tempRoot
        ).locate()

        XCTAssertEqual(installation.sqliteHome, sqliteHome)
        XCTAssertEqual(installation.stateDatabaseURL, sqliteHome.appending(path: "state_5.sqlite"))
        XCTAssertEqual(installation.auth.storagePreference, .file)
        XCTAssertEqual(installation.auth.authMode, "chatgpt")
        XCTAssertTrue(installation.auth.authFileExists)
        XCTAssertTrue(installation.auth.hasAPIKeyInAuthFile)
        XCTAssertTrue(installation.auth.hasTokenSetInAuthFile)
    }

    @MainActor
    func testUsageStoreUsesCachedSnapshotImmediatelyOnInit() throws {
        let tempDirectory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let cacheURL = tempDirectory.appending(path: "usage-snapshot.json")
        let cacheStore = SnapshotCacheStore(cacheURL: cacheURL)
        let expectedSnapshot = UsageSnapshot(
            generatedAt: Date(timeIntervalSince1970: 1_700_000_000),
            primaryLimit: RateLimitWindow(
                usedPercent: 28,
                windowMinutes: 300,
                resetsAt: Date(timeIntervalSince1970: 1_700_003_600)
            ),
            secondaryLimit: RateLimitWindow(
                usedPercent: 46,
                windowMinutes: 10_080,
                resetsAt: Date(timeIntervalSince1970: 1_700_086_400)
            ),
            today: .empty(for: Date(timeIntervalSince1970: 1_699_977_600)),
            lastSevenDays: (0..<7).map { offset in
                let date = Date(timeIntervalSince1970: 1_699_977_600 + Double(offset * 86_400))
                return .empty(for: date)
            },
            lastYearDays: (0..<365).map { offset in
                let date = Date(timeIntervalSince1970: 1_668_528_000 + Double(offset * 86_400))
                return .empty(for: date)
            },
            pet: PetProgress(level: 4, stage: .pixelKitten, currentXP: 18, nextLevelXP: 140, todayXP: 12),
            hasSourceData: true
        )
        try cacheStore.save(expectedSnapshot)

        let store = UsageStore(cacheStore: cacheStore)

        XCTAssertEqual(store.snapshot, expectedSnapshot)
        XCTAssertFalse(store.environmentInfo.codexHomePath.isEmpty)
        XCTAssertFalse(store.environmentInfo.sqliteHomePath.isEmpty)
        XCTAssertFalse(store.environmentInfo.authStorageLabel.isEmpty)
        XCTAssertFalse(store.isLoading)
        XCTAssertNil(store.errorMessage)
    }

    @MainActor
    func testUsageStoreUsesCachedMultiAgentSnapshotImmediatelyOnInit() throws {
        let tempDirectory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let codexCacheURL = tempDirectory.appending(path: "usage-snapshot.json")
        let multiCacheURL = tempDirectory.appending(path: "multi-agent-snapshot.json")
        let codexCacheStore = SnapshotCacheStore(cacheURL: codexCacheURL)
        let multiCacheStore = MultiAgentSnapshotCacheStore(cacheURL: multiCacheURL)

        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let day = Calendar.current.startOfDay(for: date)
        let codexSnapshot = UsageSnapshot(
            generatedAt: date,
            primaryLimit: nil,
            secondaryLimit: nil,
            today: .empty(for: day),
            lastSevenDays: (0..<7).map { offset in
                UsageMetricsDay(
                    date: Calendar.current.date(byAdding: .day, value: offset - 6, to: day) ?? day,
                    dialogs: 0,
                    activeMinutes: 0,
                    modifiedFiles: 0,
                    addedLines: 0,
                    deletedLines: 0
                )
            },
            lastYearDays: (0..<365).map { offset in
                UsageMetricsDay(
                    date: Calendar.current.date(byAdding: .day, value: offset - 364, to: day) ?? day,
                    dialogs: 0,
                    activeMinutes: 0,
                    modifiedFiles: 0,
                    addedLines: 0,
                    deletedLines: 0
                )
            },
            pet: PetProgress(level: 0, stage: .cursorEgg, currentXP: 0, nextLevelXP: 180, todayXP: 0),
            hasSourceData: true
        )
        try codexCacheStore.save(codexSnapshot)

        let claudeSnapshot = AgentSnapshot(
            agent: .claude,
            generatedAt: date,
            status: AgentStatusSummary(primaryLabel: "今日 Token", primaryValue: "2.5K"),
            today: UsageMetricsDay(
                date: day,
                dialogs: 2,
                activeMinutes: 20,
                modifiedFiles: 0,
                addedLines: 0,
                deletedLines: 0,
                tokenUsage: 2500,
                toolCalls: 2,
                customActivityScore: 24,
                interactionLabel: "会话",
                sourceAgents: ["Claude"]
            ),
            lastSevenDays: [],
            lastYearDays: [],
            currentModel: "claude-sonnet-4-5",
            lastActiveAt: date,
            environment: AgentEnvironmentSummary(
                runtimeLabel: "Claude Code",
                authLabel: nil,
                currentModel: "claude-sonnet-4-5",
                dataSourceLabel: "~/.claude/projects",
                updatedAt: date
            ),
            isAvailable: true
        )
        let cachedMulti = MultiAgentSnapshot(
            generatedAt: date,
            agents: [claudeSnapshot],
            mostRecentlyActiveAgent: .claude,
            focusedAgent: .claude,
            pet: PetProgress(level: 3, stage: .pixelKitten, currentXP: 20, nextLevelXP: 265, todayXP: 5),
            xpBreakdown: [AgentXPBreakdown(agent: .claude, todayXP: 5, totalXP: 20)],
            todaySummary: MultiAgentTodaySummary(totalSessions: 2, totalActiveMinutes: 20, totalTokenUsage: 2500, totalToolCalls: 2),
            lastSevenDays: [],
            lastMonthDays: [],
            lastYearDays: []
        )
        try multiCacheStore.save(cachedMulti)

        let store = UsageStore(
            cacheStore: codexCacheStore,
            multiAgentCacheStore: multiCacheStore,
            agentCacheStore: AgentSnapshotCacheStore(directoryURL: tempDirectory.appending(path: "agent-snapshots", directoryHint: .isDirectory))
        )

        XCTAssertEqual(store.multiAgentSnapshot.mostRecentlyActiveAgent, .claude)
        XCTAssertEqual(store.multiAgentSnapshot.focusedAgent, .claude)
        XCTAssertEqual(store.multiAgentSnapshot.todaySummary.totalTokenUsage, 2500)
        XCTAssertEqual(store.focusedAgent, .claude)
    }

    @MainActor
    func testUsageStoreExposesBuilderEnvironmentInfoImmediately() {
        let environmentInfo = CodexEnvironmentInfo(
            environmentLabel: "Extension",
            authMethodLabel: "ChatGPT OAuth",
            codexHomePath: "~/.codex-alt",
            sqliteHomePath: "/tmp/codex-sqlite",
            authStorageLabel: "keyring",
            authModeLabel: "chatgpt",
            authFileExists: false
        )
        let builder = CodexUsageSnapshotBuilder(
            sessionsRoot: URL(fileURLWithPath: "/tmp/codex-home/sessions"),
            stateDatabaseURL: URL(fileURLWithPath: "/tmp/codex-sqlite/state_5.sqlite"),
            environmentInfo: environmentInfo
        )

        let store = UsageStore(builder: builder)

        XCTAssertEqual(store.environmentInfo, environmentInfo)
        XCTAssertEqual(
            store.environmentInfo.summaryLine,
            "Environment: Extension  ·  Auth: ChatGPT OAuth"
        )
    }

    func testApplyPatchParserCountsFilesAndLineChanges() {
        let patch = """
        ToolCall: apply_patch *** Begin Patch
        *** Update File: Sources/CodexTrayFeature/App/UsageStore.swift
        @@
        -old line
        +new line
        +another new line
        *** Add File: Tests/CodexTrayFeatureTests/NewTests.swift
        +import XCTest
        +final class NewTests: XCTestCase {}
        *** End Patch
        """

        let stats = ApplyPatchStatsParser.parse(patch)
        XCTAssertEqual(stats.modifiedFiles.count, 2)
        XCTAssertEqual(stats.addedLines, 4)
        XCTAssertEqual(stats.deletedLines, 1)
    }

    func testSnapshotBuilderReturnsSevenDaysEvenWithoutSources() throws {
        let tempDirectory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let builder = CodexUsageSnapshotBuilder(
            sessionsRoot: tempDirectory.appending(path: "sessions"),
            stateDatabaseURL: tempDirectory.appending(path: "state_5.sqlite")
        )

        let snapshot = try builder.buildSnapshot(now: Date(timeIntervalSince1970: 1_700_000_000))
        XCTAssertEqual(snapshot.lastSevenDays.count, 7)
        XCTAssertEqual(snapshot.lastYearDays.count, 365)
        XCTAssertFalse(snapshot.hasSourceData)
        XCTAssertEqual(snapshot.today.dialogs, 0)
    }

    func testSnapshotBuilderCountsThreadsInsteadOfUserMessages() throws {
        let tempDirectory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        let sessionsRoot = tempDirectory.appending(path: "sessions/2026/03/23", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: sessionsRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let sessionOne = """
        {"timestamp":"2026-03-23T01:00:00.000Z","type":"session_meta","payload":{"id":"thread-1","timestamp":"2026-03-23T01:00:00.000Z"}}
        {"timestamp":"2026-03-23T01:01:00.000Z","type":"event_msg","payload":{"type":"user_message"}}
        {"timestamp":"2026-03-23T01:03:00.000Z","type":"event_msg","payload":{"type":"user_message"}}
        {"timestamp":"2026-03-23T01:04:00.000Z","type":"event_msg","payload":{"type":"agent_message"}}
        """
        let sessionTwo = """
        {"timestamp":"2026-03-23T05:00:00.000Z","type":"session_meta","payload":{"id":"thread-2","timestamp":"2026-03-23T05:00:00.000Z"}}
        {"timestamp":"2026-03-23T05:02:00.000Z","type":"event_msg","payload":{"type":"user_message"}}
        {"timestamp":"2026-03-23T05:05:00.000Z","type":"response_item","payload":{"type":"function_call"}}
        """

        try sessionOne.write(to: sessionsRoot.appending(path: "thread-1.jsonl"), atomically: true, encoding: .utf8)
        try sessionTwo.write(to: sessionsRoot.appending(path: "thread-2.jsonl"), atomically: true, encoding: .utf8)

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .current

        let builder = CodexUsageSnapshotBuilder(
            sessionsRoot: tempDirectory.appending(path: "sessions"),
            stateDatabaseURL: tempDirectory.appending(path: "state_5.sqlite"),
            calendar: calendar
        )

        let snapshot = try builder.buildSnapshot(now: ISO8601DateParser.parse("2026-03-23T12:00:00.000Z") ?? .now)

        XCTAssertEqual(snapshot.today.dialogs, 2)
        XCTAssertEqual(snapshot.today.activeMinutes, 8)
        XCTAssertEqual(snapshot.lastYearDays.last?.dialogs ?? -1, 2)
    }

    func testSnapshotBuilderUsesFirstOpenAsPetBaseline() throws {
        let tempDirectory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        let sessionsRoot = tempDirectory.appending(path: "sessions/2026/03/23", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: sessionsRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let session = """
        {"timestamp":"2026-03-23T01:00:00.000Z","type":"session_meta","payload":{"id":"thread-1","timestamp":"2026-03-23T01:00:00.000Z"}}
        {"timestamp":"2026-03-23T01:01:00.000Z","type":"event_msg","payload":{"type":"user_message"}}
        {"timestamp":"2026-03-23T01:03:00.000Z","type":"event_msg","payload":{"type":"agent_message"}}
        """
        try session.write(to: sessionsRoot.appending(path: "thread-1.jsonl"), atomically: true, encoding: .utf8)

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .current

        let baselineStore = PetProgressBaselineStore(
            cacheURL: tempDirectory.appending(path: "pet-progress-baseline.json")
        )
        let builder = CodexUsageSnapshotBuilder(
            sessionsRoot: tempDirectory.appending(path: "sessions"),
            stateDatabaseURL: tempDirectory.appending(path: "state_5.sqlite"),
            calendar: calendar,
            petBaselineStore: baselineStore
        )

        let firstSnapshot = try builder.buildSnapshot(now: ISO8601DateParser.parse("2026-03-23T12:00:00.000Z") ?? .now)
        let secondSession = """
        {"timestamp":"2026-03-23T06:00:00.000Z","type":"session_meta","payload":{"id":"thread-2","timestamp":"2026-03-23T06:00:00.000Z"}}
        {"timestamp":"2026-03-23T06:01:00.000Z","type":"event_msg","payload":{"type":"user_message"}}
        {"timestamp":"2026-03-23T06:03:00.000Z","type":"event_msg","payload":{"type":"agent_message"}}
        """
        try secondSession.write(to: sessionsRoot.appending(path: "thread-2.jsonl"), atomically: true, encoding: .utf8)
        let secondSnapshot = try builder.buildSnapshot(now: ISO8601DateParser.parse("2026-03-23T13:00:00.000Z") ?? .now)

        XCTAssertEqual(firstSnapshot.pet.level, 0)
        XCTAssertEqual(firstSnapshot.pet.currentXP, 0)
        XCTAssertEqual(firstSnapshot.pet.todayXP, 0)
        XCTAssertEqual(secondSnapshot.pet.level, 0)
        XCTAssertGreaterThan(secondSnapshot.pet.currentXP, 0)
        XCTAssertEqual(secondSnapshot.pet.currentXP, secondSnapshot.pet.todayXP)
    }

    func testSnapshotBuilderResetsExpiredPrimaryLimitWindowOnNextOpen() throws {
        let tempDirectory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        let sessionsRoot = tempDirectory.appending(path: "sessions/2026/03/23", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: sessionsRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let session = """
        {"timestamp":"2026-03-23T16:00:00.000Z","type":"session_meta","payload":{"id":"thread-1","timestamp":"2026-03-23T16:00:00.000Z"}}
        {"timestamp":"2026-03-23T16:01:00.000Z","type":"event_msg","payload":{"type":"user_message"}}
        {"timestamp":"2026-03-23T16:02:00.000Z","type":"event_msg","payload":{"type":"token_count","rate_limits":{"primary":{"used_percent":64,"window_minutes":300,"resets_at":1774260000},"secondary":{"used_percent":10,"window_minutes":10080,"resets_at":1774861200}}}}
        """
        try session.write(to: sessionsRoot.appending(path: "thread-1.jsonl"), atomically: true, encoding: .utf8)

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .current

        let builder = CodexUsageSnapshotBuilder(
            sessionsRoot: tempDirectory.appending(path: "sessions"),
            stateDatabaseURL: tempDirectory.appending(path: "state_5.sqlite"),
            calendar: calendar
        )

        let snapshot = try builder.buildSnapshot(now: ISO8601DateParser.parse("2026-03-24T03:00:00.000Z") ?? .now)
        let primaryLimit = try XCTUnwrap(snapshot.primaryLimit)
        let secondaryLimit = try XCTUnwrap(snapshot.secondaryLimit)

        XCTAssertEqual(primaryLimit.usedPercent, 0, accuracy: 0.0001)
        XCTAssertEqual(primaryLimit.remainingPercent, 100, accuracy: 0.0001)
        XCTAssertEqual(
            primaryLimit.resetsAt,
            ISO8601DateParser.parse("2026-03-24T06:00:00.000Z")
        )
        XCTAssertEqual(secondaryLimit.usedPercent, 10, accuracy: 0.0001)
    }

    func testSnapshotBuilderIncludesCodexTokenCountInDailyUsage() throws {
        let tempDirectory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        let sessionsRoot = tempDirectory.appending(path: "sessions/2026/03/23", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: sessionsRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let session = """
        {"timestamp":"2026-03-23T16:00:00.000Z","type":"session_meta","payload":{"id":"thread-1","timestamp":"2026-03-23T16:00:00.000Z"}}
        {"timestamp":"2026-03-23T16:01:00.000Z","type":"event_msg","payload":{"type":"user_message"}}
        {"timestamp":"2026-03-23T16:02:00.000Z","type":"event_msg","payload":{"type":"token_count","last_token_usage":{"input_tokens":1200,"output_tokens":300,"reasoning_tokens":50,"total_tokens":1550}}}
        """
        try session.write(to: sessionsRoot.appending(path: "thread-1.jsonl"), atomically: true, encoding: .utf8)

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .current

        let builder = CodexUsageSnapshotBuilder(
            sessionsRoot: tempDirectory.appending(path: "sessions"),
            stateDatabaseURL: tempDirectory.appending(path: "state_5.sqlite"),
            calendar: calendar
        )

        let snapshot = try builder.buildSnapshot(now: ISO8601DateParser.parse("2026-03-23T18:00:00.000Z") ?? .now)

        XCTAssertEqual(snapshot.today.dialogs, 1)
        XCTAssertEqual(snapshot.today.tokenUsage, 1_550)
        XCTAssertEqual(snapshot.lastYearDays.last?.tokenUsage, 1_550)
    }
}
