import Foundation

public enum AgentKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case all
    case codex
    case claude
    case gemini

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .all:
            "All"
        case .codex:
            "Codex"
        case .claude:
            "Claude"
        case .gemini:
            "Gemini"
        }
    }

    public var iconSymbolName: String {
        switch self {
        case .all:
            "square.grid.2x2.fill"
        case .codex:
            "terminal.fill"
        case .claude:
            "sparkles"
        case .gemini:
            "diamond.fill"
        }
    }
}

public struct RateLimitWindow: Codable, Equatable, Sendable {
    public let usedPercent: Double
    public let windowMinutes: Int
    public let resetsAt: Date

    public var remainingPercent: Double {
        max(0, 100 - usedPercent)
    }

    public var shortLabel: String {
        "\(Int(remainingPercent.rounded()))%"
    }
}

public struct UsageMetricsDay: Codable, Equatable, Identifiable, Sendable {
    public let date: Date
    public let dialogs: Int
    public let activeMinutes: Int
    public let modifiedFiles: Int
    public let addedLines: Int
    public let deletedLines: Int
    public let tokenUsage: Int
    public let toolCalls: Int
    public let customActivityScore: Double?
    public let interactionLabel: String
    public let sourceAgents: [String]

    public var id: Date { date }

    public init(
        date: Date,
        dialogs: Int,
        activeMinutes: Int,
        modifiedFiles: Int,
        addedLines: Int,
        deletedLines: Int,
        tokenUsage: Int = 0,
        toolCalls: Int = 0,
        customActivityScore: Double? = nil,
        interactionLabel: String = "Conversation",
        sourceAgents: [String] = []
    ) {
        self.date = date
        self.dialogs = dialogs
        self.activeMinutes = activeMinutes
        self.modifiedFiles = modifiedFiles
        self.addedLines = addedLines
        self.deletedLines = deletedLines
        self.tokenUsage = tokenUsage
        self.toolCalls = toolCalls
        self.customActivityScore = customActivityScore
        self.interactionLabel = interactionLabel
        self.sourceAgents = sourceAgents
    }

    public var netLines: Int {
        addedLines - deletedLines
    }

    public var activityScore: Double {
        if let customActivityScore {
            return customActivityScore
        }
        return ActivityScoreCalculator.score(
            dialogs: dialogs,
            activeMinutes: activeMinutes,
            modifiedFiles: modifiedFiles,
            addedLines: addedLines,
            deletedLines: deletedLines
        )
    }

    public var heatmapLevel: Int {
        HeatmapLevelCalculator.level(for: activityScore)
    }

    public static func empty(for date: Date) -> UsageMetricsDay {
        UsageMetricsDay(
            date: date,
            dialogs: 0,
            activeMinutes: 0,
            modifiedFiles: 0,
            addedLines: 0,
            deletedLines: 0,
            tokenUsage: 0,
            toolCalls: 0,
            customActivityScore: nil,
            interactionLabel: AppText.text("Conversation", "对话"),
            sourceAgents: []
        )
    }
}

public struct AgentStatusSummary: Codable, Equatable, Sendable {
    public let primaryLabel: String
    public let primaryValue: String
    public let primaryProgress: Double?
    public let primaryResetAt: Date?
    public let secondaryLabel: String?
    public let secondaryValue: String?
    public let secondaryProgress: Double?
    public let secondaryResetAt: Date?

    public init(
        primaryLabel: String,
        primaryValue: String,
        primaryProgress: Double? = nil,
        primaryResetAt: Date? = nil,
        secondaryLabel: String? = nil,
        secondaryValue: String? = nil,
        secondaryProgress: Double? = nil,
        secondaryResetAt: Date? = nil
    ) {
        self.primaryLabel = primaryLabel
        self.primaryValue = primaryValue
        self.primaryProgress = primaryProgress
        self.primaryResetAt = primaryResetAt
        self.secondaryLabel = secondaryLabel
        self.secondaryValue = secondaryValue
        self.secondaryProgress = secondaryProgress
        self.secondaryResetAt = secondaryResetAt
    }
}

public struct AgentEnvironmentSummary: Codable, Equatable, Sendable {
    public let runtimeLabel: String
    public let authLabel: String?
    public let currentModel: String?
    public let dataSourceLabel: String
    public let updatedAt: Date?

    public init(
        runtimeLabel: String,
        authLabel: String? = nil,
        currentModel: String? = nil,
        dataSourceLabel: String,
        updatedAt: Date? = nil
    ) {
        self.runtimeLabel = runtimeLabel
        self.authLabel = authLabel
        self.currentModel = currentModel
        self.dataSourceLabel = dataSourceLabel
        self.updatedAt = updatedAt
    }
}

public struct AgentSnapshot: Codable, Equatable, Sendable, Identifiable {
    public let agent: AgentKind
    public let generatedAt: Date
    public let status: AgentStatusSummary
    public let today: UsageMetricsDay
    public let lastSevenDays: [UsageMetricsDay]
    public let lastYearDays: [UsageMetricsDay]
    public let analytics: AgentAnalyticsSnapshot?
    public let currentModel: String?
    public let lastActiveAt: Date?
    public let environment: AgentEnvironmentSummary
    public let isAvailable: Bool

    public var id: AgentKind { agent }

    public init(
        agent: AgentKind,
        generatedAt: Date,
        status: AgentStatusSummary,
        today: UsageMetricsDay,
        lastSevenDays: [UsageMetricsDay],
        lastYearDays: [UsageMetricsDay],
        analytics: AgentAnalyticsSnapshot? = nil,
        currentModel: String?,
        lastActiveAt: Date?,
        environment: AgentEnvironmentSummary,
        isAvailable: Bool
    ) {
        self.agent = agent
        self.generatedAt = generatedAt
        self.status = status
        self.today = today
        self.lastSevenDays = lastSevenDays
        self.lastYearDays = lastYearDays
        self.analytics = analytics
        self.currentModel = currentModel
        self.lastActiveAt = lastActiveAt
        self.environment = environment
        self.isAvailable = isAvailable
    }
}

public struct AgentXPBreakdown: Codable, Equatable, Sendable, Identifiable {
    public let agent: AgentKind
    public let todayXP: Int
    public let totalXP: Int

    public var id: AgentKind { agent }
}

public struct MultiAgentTodaySummary: Codable, Equatable, Sendable {
    public let totalSessions: Int
    public let totalActiveMinutes: Int
    public let totalTokenUsage: Int
    public let totalToolCalls: Int

    public init(
        totalSessions: Int,
        totalActiveMinutes: Int,
        totalTokenUsage: Int,
        totalToolCalls: Int
    ) {
        self.totalSessions = totalSessions
        self.totalActiveMinutes = totalActiveMinutes
        self.totalTokenUsage = totalTokenUsage
        self.totalToolCalls = totalToolCalls
    }
}

public struct MultiAgentSnapshot: Codable, Equatable, Sendable {
    public let generatedAt: Date
    public let agents: [AgentSnapshot]
    public let mostRecentlyActiveAgent: AgentKind?
    public var focusedAgent: AgentKind
    public let pet: PetProgress
    public let xpBreakdown: [AgentXPBreakdown]
    public let todaySummary: MultiAgentTodaySummary
    public let lastSevenDays: [UsageMetricsDay]
    public let lastMonthDays: [UsageMetricsDay]
    public let lastYearDays: [UsageMetricsDay]

    public init(
        generatedAt: Date,
        agents: [AgentSnapshot],
        mostRecentlyActiveAgent: AgentKind?,
        focusedAgent: AgentKind,
        pet: PetProgress,
        xpBreakdown: [AgentXPBreakdown],
        todaySummary: MultiAgentTodaySummary,
        lastSevenDays: [UsageMetricsDay],
        lastMonthDays: [UsageMetricsDay],
        lastYearDays: [UsageMetricsDay]
    ) {
        self.generatedAt = generatedAt
        self.agents = agents
        self.mostRecentlyActiveAgent = mostRecentlyActiveAgent
        self.focusedAgent = focusedAgent
        self.pet = pet
        self.xpBreakdown = xpBreakdown
        self.todaySummary = todaySummary
        self.lastSevenDays = lastSevenDays
        self.lastMonthDays = lastMonthDays
        self.lastYearDays = lastYearDays
    }

    public func snapshot(for agent: AgentKind) -> AgentSnapshot? {
        agents.first(where: { $0.agent == agent })
    }
}

public enum PetStage: String, Codable, Equatable, CaseIterable, Sendable {
    case cursorEgg
    case pixelKitten
    case terminalCat
    case mechPatchCat
    case notchGuardian

    public var displayName: String {
        switch self {
        case .cursorEgg:
            AppText.text("Kitty Egg", "喵喵蛋")
        case .pixelKitten:
            AppText.text("Pixel Kitty", "像素喵")
        case .terminalCat:
            AppText.text("Terminal Cat", "终端喵")
        case .mechPatchCat:
            AppText.text("Patch Cat", "补丁喵")
        case .notchGuardian:
            AppText.text("Notch Guardian", "守护喵")
        }
    }

    public var accentHex: String {
        switch self {
        case .cursorEgg:
            "#79D0FF"
        case .pixelKitten:
            "#75E59A"
        case .terminalCat:
            "#F5C46B"
        case .mechPatchCat:
            "#FF8B6A"
        case .notchGuardian:
            "#A4A7FF"
        }
    }
}

public struct PetProgress: Codable, Equatable, Sendable {
    public let level: Int
    public let stage: PetStage
    public let currentXP: Int
    public let nextLevelXP: Int
    public let todayXP: Int
}

public struct PetProgressBaseline: Codable, Equatable, Sendable {
    public let totalXP: Int
    public let todayXP: Int
    public let day: Date
}

public struct UsageSnapshot: Codable, Equatable, Sendable {
    public let generatedAt: Date
    public let primaryLimit: RateLimitWindow?
    public let secondaryLimit: RateLimitWindow?
    public let today: UsageMetricsDay
    public let lastSevenDays: [UsageMetricsDay]
    public let lastYearDays: [UsageMetricsDay]
    public let pet: PetProgress
    public let hasSourceData: Bool

    public static let placeholder = UsageSnapshot(
        generatedAt: .now,
        primaryLimit: nil,
        secondaryLimit: nil,
        today: .empty(for: Calendar.current.startOfDay(for: .now)),
        lastSevenDays: (0..<7).map { offset in
            let date = Calendar.current.date(byAdding: .day, value: offset - 6, to: Calendar.current.startOfDay(for: .now)) ?? .now
            return .empty(for: date)
        },
        lastYearDays: (0..<365).map { offset in
            let date = Calendar.current.date(byAdding: .day, value: offset - 364, to: Calendar.current.startOfDay(for: .now)) ?? .now
            return .empty(for: date)
        },
        pet: PetProgress(level: 0, stage: .cursorEgg, currentXP: 0, nextLevelXP: 180, todayXP: 0),
        hasSourceData: false
    )
}

public enum ActivityScoreCalculator {
    public static func score(
        dialogs: Int,
        activeMinutes: Int,
        modifiedFiles: Int,
        addedLines: Int,
        deletedLines: Int
    ) -> Double {
        let totalChangedLines = max(0, addedLines + deletedLines)
        return (3 * Double(dialogs))
            + (0.5 * Double(activeMinutes))
            + (2 * Double(modifiedFiles))
            + (1.2 * sqrt(Double(totalChangedLines)))
    }
}

public enum HeatmapLevelCalculator {
    public static func level(for score: Double) -> Int {
        guard score > 0 else { return 0 }
        let normalized = 4 * log(1 + score) / log(81)
        return max(0, min(4, Int(floor(normalized))))
    }
}

public enum ActivityTimelineCalculator {
    public static func activeMinutes(
        for timestamps: [Date],
        thresholdMinutes: Double = 5
    ) -> Int {
        let sorted = timestamps.sorted()
        guard let first = sorted.first else { return 0 }
        var activeMinuteBuckets: Set<Date> = []
        var segmentStart = first
        var previous = first

        for timestamp in sorted.dropFirst() {
            let deltaMinutes = timestamp.timeIntervalSince(previous) / 60
            if deltaMinutes <= thresholdMinutes {
                previous = timestamp
                continue
            }

            markActiveMinutes(from: segmentStart, to: previous, into: &activeMinuteBuckets)
            segmentStart = timestamp
            previous = timestamp
        }

        markActiveMinutes(from: segmentStart, to: previous, into: &activeMinuteBuckets)
        return activeMinuteBuckets.count
    }

    private static func markActiveMinutes(
        from start: Date,
        to end: Date,
        into buckets: inout Set<Date>
    ) {
        var calendar = Calendar.current
        calendar.timeZone = .current

        let startMinute = calendar.dateInterval(of: .minute, for: start)?.start ?? start
        let endMinute = calendar.dateInterval(of: .minute, for: end)?.start ?? end
        var currentMinute = startMinute

        while currentMinute <= endMinute {
            buckets.insert(currentMinute)
            guard let nextMinute = calendar.date(byAdding: .minute, value: 1, to: currentMinute) else {
                break
            }
            currentMinute = nextMinute
        }
    }
}

public enum PetProgressCalculator {
    public static func xpNeeded(for level: Int) -> Int {
        180 + (level * 85)
    }

    public static func stage(for level: Int) -> PetStage {
        switch level {
        case ..<3:
            .cursorEgg
        case 3..<6:
            .pixelKitten
        case 6..<10:
            .terminalCat
        case 10..<15:
            .mechPatchCat
        default:
            .notchGuardian
        }
    }

    public static func progress(totalXP: Int, todayXP: Int) -> PetProgress {
        var level = 0
        var remainingXP = max(0, totalXP)

        while remainingXP >= xpNeeded(for: level) {
            remainingXP -= xpNeeded(for: level)
            level += 1
        }

        return PetProgress(
            level: level,
            stage: stage(for: level),
            currentXP: remainingXP,
            nextLevelXP: xpNeeded(for: level),
            todayXP: max(0, todayXP)
        )
    }
}

public enum PetProgressExplanationFormatter {
    public static func levelDescriptions() -> [String] {
        [
            "Lv.0-2: \(PetStage.cursorEgg.displayName)",
            "Lv.3-5: \(PetStage.pixelKitten.displayName)",
            "Lv.6-9: \(PetStage.terminalCat.displayName)",
            "Lv.10-14: \(PetStage.mechPatchCat.displayName)",
            "Lv.15+: \(PetStage.notchGuardian.displayName)",
        ]
    }

    public static func xpFormulaDescription() -> String {
        AppText.text(
            "Daily XP = round(3×sessions + 0.5×active minutes + 2×modified files + 1.2×sqrt(added lines + deleted lines))",
            "单日 XP = round(3×会话数 + 0.5×活跃分钟 + 2×修改文件数 + 1.2×sqrt(新增行数+删除行数))"
        )
    }

    public static func progressRuleDescription() -> String {
        AppText.text(
            "Total pet XP only counts XP earned after you first opened the app.",
            "宠物总经验按首次打开应用后的新增 XP 累计计算。"
        )
    }

    public static func agentContributionDescriptions(from entries: [AgentXPBreakdown]) -> [String] {
        guard entries.isEmpty == false else {
            return [AppText.text("No agent XP available yet", "暂无可统计的 Agent 经验")]
        }

        let sortedEntries = entries.sorted { lhs, rhs in
            if lhs.totalXP == rhs.totalXP {
                return lhs.agent.displayName < rhs.agent.displayName
            }
            return lhs.totalXP > rhs.totalXP
        }
        let totalXP = sortedEntries.reduce(0) { $0 + $1.totalXP }
        let detailLines = sortedEntries.map {
            AppText.text(
                "\($0.agent.displayName): Today +\($0.todayXP) / Last year total \($0.totalXP)",
                "\($0.agent.displayName): 今日 +\($0.todayXP) / 近一年累计 \($0.totalXP)"
            )
        }
        return [AppText.text("All agents, last year total: \(totalXP) XP", "全部 Agent 近一年累计: \(totalXP) XP")] + detailLines
    }

    public static func tooltipText(from entries: [AgentXPBreakdown]) -> String {
        (
            [AppText.text("Level Names", "等级名称")]
            + levelDescriptions()
            + ["", AppText.text("XP Formula", "经验计算"), xpFormulaDescription(), progressRuleDescription(), "", AppText.text("Agent Contribution", "各 Agent 贡献")]
            + agentContributionDescriptions(from: entries)
        )
        .joined(separator: "\n")
    }
}

public enum DurationFormatter {
    public static func string(for minutes: Int) -> String {
        let hours = minutes / 60
        let remainingMinutes = minutes % 60
        switch (hours, remainingMinutes) {
        case (0, _):
            return AppText.text("\(remainingMinutes)m", "\(remainingMinutes)分")
        case (_, 0):
            return AppText.text("\(hours)h", "\(hours)小时")
        default:
            return AppText.text("\(hours)h \(remainingMinutes)m", "\(hours)小时\(remainingMinutes)分")
        }
    }
}
