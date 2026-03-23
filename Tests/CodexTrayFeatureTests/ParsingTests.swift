import XCTest
@testable import CodexTrayFeature

final class ParsingTests: XCTestCase {
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
        XCTAssertFalse(store.isLoading)
        XCTAssertNil(store.errorMessage)
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
}
