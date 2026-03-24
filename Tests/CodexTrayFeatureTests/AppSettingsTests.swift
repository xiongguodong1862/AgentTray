import XCTest
@testable import CodexTrayFeature

@MainActor
final class AppSettingsTests: XCTestCase {
    func testAppSettingsStorePersistsUpdates() {
        let defaults = makeUserDefaults()
        let storageKey = "CodexTrayFeatureTests.settings"

        let store = AppSettingsStore(userDefaults: defaults, storageKey: storageKey)
        store.updateDefaultAgent(.claude)
        store.updateDefaultHeatmapRange(.month)
        store.updateRefreshInterval(.fiveMinutes)
        store.updateShowsHotspot(false)
        store.updateThemeTint(.classicDeepBlue)
        store.updateHeatmapColor(.rose)

        let reloaded = AppSettingsStore(userDefaults: defaults, storageKey: storageKey)
        XCTAssertEqual(
            reloaded.settings,
            AppSettings(
                defaultAgent: .claude,
                defaultHeatmapRange: .month,
                refreshInterval: .fiveMinutes,
                showsHotspot: false,
                themeTint: .classicDeepBlue,
                heatmapColor: .rose
            )
        )
    }

    func testDefaultAgentPreferenceFollowRecentFallsBackToAll() {
        XCTAssertEqual(DefaultAgentPreference.followRecent.resolve(mostRecentlyActive: nil), .all)
        XCTAssertEqual(DefaultAgentPreference.followRecent.resolve(mostRecentlyActive: .gemini), .gemini)
    }

    func testDefaultAgentPreferenceOptionsHideUnavailableAgents() {
        XCTAssertEqual(
            DefaultAgentPreference.options(for: [.codex, .gemini]),
            [.all, .codex, .gemini, .followRecent]
        )
    }

    func testHeatmapPaletteUsesConfiguredGradientSequence() {
        XCTAssertEqual(HeatmapPalette.hex(for: 0, preset: .aqua), HeatmapColorPreset.aqua.gradientHexes[0])
        XCTAssertEqual(HeatmapPalette.hex(for: 2, preset: .aqua), HeatmapColorPreset.aqua.gradientHexes[2])
        XCTAssertEqual(HeatmapPalette.hex(for: 99, preset: .aqua), HeatmapColorPreset.aqua.gradientHexes[4])
    }

    func testClassicDeepBlueUsesOriginalGradientStops() {
        XCTAssertEqual(
            ThemeTintPreset.classicDeepBlue.gradientHexes,
            ["#000000", "#000000", "#071321", "#0B1D31", "#102942"]
        )
    }

    func testUsageStoreHonorsConfiguredDefaultAgentOnInit() throws {
        let tempDirectory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let codexCacheStore = SnapshotCacheStore(cacheURL: tempDirectory.appending(path: "usage-snapshot.json"))
        let multiCacheStore = MultiAgentSnapshotCacheStore(cacheURL: tempDirectory.appending(path: "multi-agent-snapshot.json"))
        let agentCacheStore = AgentSnapshotCacheStore(directoryURL: tempDirectory.appending(path: "agent-snapshots", directoryHint: .isDirectory))
        let defaults = makeUserDefaults()
        let settingsStore = AppSettingsStore(userDefaults: defaults, storageKey: "CodexTrayFeatureTests.default-agent")
        settingsStore.updateDefaultAgent(.claude)

        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let day = Calendar.current.startOfDay(for: date)
        try codexCacheStore.save(
            UsageSnapshot(
                generatedAt: date,
                primaryLimit: nil,
                secondaryLimit: nil,
                today: .empty(for: day),
                lastSevenDays: [],
                lastYearDays: [],
                pet: PetProgress(level: 0, stage: .cursorEgg, currentXP: 0, nextLevelXP: 180, todayXP: 0),
                hasSourceData: true
            )
        )

        let claudeSnapshot = AgentSnapshot(
            agent: .claude,
            generatedAt: date,
            status: AgentStatusSummary(primaryLabel: "今日 Token", primaryValue: "2.5K"),
            today: .empty(for: day),
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
        try multiCacheStore.save(
            MultiAgentSnapshot(
                generatedAt: date,
                agents: [claudeSnapshot],
                mostRecentlyActiveAgent: .claude,
                focusedAgent: .codex,
                pet: PetProgress(level: 1, stage: .pixelKitten, currentXP: 10, nextLevelXP: 180, todayXP: 3),
                xpBreakdown: [AgentXPBreakdown(agent: .claude, todayXP: 3, totalXP: 10)],
                todaySummary: MultiAgentTodaySummary(totalSessions: 0, totalActiveMinutes: 0, totalTokenUsage: 0, totalToolCalls: 0),
                lastSevenDays: [],
                lastMonthDays: [],
                lastYearDays: []
            )
        )

        let store = UsageStore(
            cacheStore: codexCacheStore,
            multiAgentCacheStore: multiCacheStore,
            agentCacheStore: agentCacheStore,
            settingsStore: settingsStore
        )

        XCTAssertEqual(store.selectedAgent, .claude)
        XCTAssertEqual(store.focusedAgent, .claude)
    }

    func testUsageStoreResetSelectionToDefaultRestoresConfiguredAgent() throws {
        let tempDirectory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let codexCacheStore = SnapshotCacheStore(cacheURL: tempDirectory.appending(path: "usage-snapshot.json"))
        let multiCacheStore = MultiAgentSnapshotCacheStore(cacheURL: tempDirectory.appending(path: "multi-agent-snapshot.json"))
        let agentCacheStore = AgentSnapshotCacheStore(directoryURL: tempDirectory.appending(path: "agent-snapshots", directoryHint: .isDirectory))
        let defaults = makeUserDefaults()
        let settingsStore = AppSettingsStore(userDefaults: defaults, storageKey: "CodexTrayFeatureTests.reset-selection")
        settingsStore.updateDefaultAgent(.claude)

        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let day = Calendar.current.startOfDay(for: date)
        try codexCacheStore.save(
            UsageSnapshot(
                generatedAt: date,
                primaryLimit: nil,
                secondaryLimit: nil,
                today: .empty(for: day),
                lastSevenDays: [],
                lastYearDays: [],
                pet: PetProgress(level: 0, stage: .cursorEgg, currentXP: 0, nextLevelXP: 180, todayXP: 0),
                hasSourceData: true
            )
        )

        let claudeSnapshot = AgentSnapshot(
            agent: .claude,
            generatedAt: date,
            status: AgentStatusSummary(primaryLabel: "今日 Token", primaryValue: "2.5K"),
            today: .empty(for: day),
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
        let geminiSnapshot = AgentSnapshot(
            agent: .gemini,
            generatedAt: date,
            status: AgentStatusSummary(primaryLabel: "今日 Token", primaryValue: "1.0K"),
            today: .empty(for: day),
            lastSevenDays: [],
            lastYearDays: [],
            currentModel: "gemini-2.5-pro",
            lastActiveAt: date.addingTimeInterval(-60),
            environment: AgentEnvironmentSummary(
                runtimeLabel: "Gemini CLI",
                authLabel: nil,
                currentModel: "gemini-2.5-pro",
                dataSourceLabel: "~/.gemini",
                updatedAt: date
            ),
            isAvailable: true
        )
        try multiCacheStore.save(
            MultiAgentSnapshot(
                generatedAt: date,
                agents: [claudeSnapshot, geminiSnapshot],
                mostRecentlyActiveAgent: .claude,
                focusedAgent: .claude,
                pet: PetProgress(level: 1, stage: .pixelKitten, currentXP: 10, nextLevelXP: 180, todayXP: 3),
                xpBreakdown: [
                    AgentXPBreakdown(agent: .claude, todayXP: 3, totalXP: 10),
                    AgentXPBreakdown(agent: .gemini, todayXP: 1, totalXP: 6),
                ],
                todaySummary: MultiAgentTodaySummary(totalSessions: 0, totalActiveMinutes: 0, totalTokenUsage: 0, totalToolCalls: 0),
                lastSevenDays: [],
                lastMonthDays: [],
                lastYearDays: []
            )
        )

        let store = UsageStore(
            cacheStore: codexCacheStore,
            multiAgentCacheStore: multiCacheStore,
            agentCacheStore: agentCacheStore,
            settingsStore: settingsStore
        )

        store.selectAgent(.gemini)
        XCTAssertEqual(store.selectedAgent, .gemini)

        store.resetSelectionToDefault()

        XCTAssertEqual(store.selectedAgent, .claude)
        XCTAssertEqual(store.focusedAgent, .claude)
    }

    private func makeUserDefaults() -> UserDefaults {
        let suiteName = "CodexTrayFeatureTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName) ?? .standard
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }
}
