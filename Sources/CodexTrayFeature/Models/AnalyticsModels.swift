import Foundation

public enum AnalyticsRange: String, Codable, CaseIterable, Identifiable, Sendable {
    case today
    case week
    case month

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .today:
            "今日"
        case .week:
            "本周"
        case .month:
            "本月"
        }
    }

    public var usesHourlyBuckets: Bool {
        self == .today
    }

    public static let defaultValue: AnalyticsRange = .today
}

public enum AgentAnalyticsTab: String, Codable, CaseIterable, Identifiable, Sendable {
    case activity
    case sessions
    case tokens
    case tools
    case changes
    case limits
    case models
    case projects

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .activity:
            "活跃趋势"
        case .sessions:
            "会话"
        case .tokens:
            "Token"
        case .tools:
            "工具"
        case .changes:
            "改动"
        case .limits:
            "配额"
        case .models:
            "模型"
        case .projects:
            "项目"
        }
    }

    public static func tabs(for agent: AgentKind) -> [AgentAnalyticsTab] {
        switch agent {
        case .codex:
            [.activity, .sessions, .tokens, .tools, .changes, .limits]
        case .claude:
            [.activity, .sessions, .tokens, .tools]
        case .gemini:
            [.activity, .sessions, .tokens, .models, .projects]
        case .all:
            []
        }
    }
}

public struct CountSeriesPoint: Codable, Equatable, Sendable, Identifiable {
    public let bucketStart: Date
    public let value: Int

    public var id: Date { bucketStart }
}

public struct HourlyActivityPoint: Codable, Equatable, Sendable, Identifiable {
    public let hour: Int
    public let activeMinutes: Int
    public let sessions: Int

    public var id: Int { hour }
}

public struct DailyActivityPoint: Codable, Equatable, Sendable, Identifiable {
    public let date: Date
    public let activeMinutes: Int
    public let sessions: Int

    public var id: Date { date }
}

public struct TimedPercentPoint: Codable, Equatable, Sendable, Identifiable {
    public let timestamp: Date
    public let percent: Double

    public var id: Date { timestamp }
}

public struct NamedCountItem: Codable, Equatable, Sendable, Identifiable {
    public let name: String
    public let count: Int
    public let ratio: Double

    public var id: String { name }
}

public struct NamedAverageItem: Codable, Equatable, Sendable, Identifiable {
    public let name: String
    public let averageValue: Double

    public var id: String { name }
}

public struct ProjectTokenSeries: Codable, Equatable, Sendable, Identifiable {
    public let projectName: String
    public let points: [CountSeriesPoint]

    public var id: String { projectName }
}

public struct SessionStatsSnapshot: Codable, Equatable, Sendable {
    public let totalSessions: Int
    public let averageTurnsPerSession: Double
    public let activeDays: Int
    public let series: [CountSeriesPoint]

    public static let empty = SessionStatsSnapshot(
        totalSessions: 0,
        averageTurnsPerSession: 0,
        activeDays: 0,
        series: []
    )
}

public struct TokenStatsSnapshot: Codable, Equatable, Sendable {
    public let totalTokens: Int
    public let averageTokensPerSession: Double
    public let inputTokens: Int
    public let outputTokens: Int
    public let reasoningTokens: Int
    public let series: [CountSeriesPoint]
    public let cumulativeSeries: [CountSeriesPoint]

    public static let empty = TokenStatsSnapshot(
        totalTokens: 0,
        averageTokensPerSession: 0,
        inputTokens: 0,
        outputTokens: 0,
        reasoningTokens: 0,
        series: [],
        cumulativeSeries: []
    )
}

public struct ToolStatsSnapshot: Codable, Equatable, Sendable {
    public let totalToolCalls: Int
    public let distinctToolCount: Int
    public let topTools: [NamedCountItem]
    public let searchSessionCount: Int
    public let nonSearchSessionCount: Int

    public static let empty = ToolStatsSnapshot(
        totalToolCalls: 0,
        distinctToolCount: 0,
        topTools: [],
        searchSessionCount: 0,
        nonSearchSessionCount: 0
    )
}

public struct ChangeStatsSnapshot: Codable, Equatable, Sendable {
    public let totalAddedLines: Int
    public let totalDeletedLines: Int
    public let totalNetLines: Int
    public let modifiedFiles: Int
    public let addedSeries: [CountSeriesPoint]
    public let deletedSeries: [CountSeriesPoint]
    public let netSeries: [CountSeriesPoint]

    public static let empty = ChangeStatsSnapshot(
        totalAddedLines: 0,
        totalDeletedLines: 0,
        totalNetLines: 0,
        modifiedFiles: 0,
        addedSeries: [],
        deletedSeries: [],
        netSeries: []
    )
}

public enum LimitWarningLevel: String, Codable, Equatable, CaseIterable, Sendable {
    case none
    case warning
    case critical
}

public struct LimitStatsSnapshot: Codable, Equatable, Sendable {
    public let primaryCurrentPercent: Double?
    public let secondaryCurrentPercent: Double?
    public let primaryResetAt: Date?
    public let secondaryResetAt: Date?
    public let primaryWarningLevel: LimitWarningLevel
    public let secondaryWarningLevel: LimitWarningLevel
    public let primarySeries: [TimedPercentPoint]
    public let secondarySeries: [TimedPercentPoint]

    public static let empty = LimitStatsSnapshot(
        primaryCurrentPercent: nil,
        secondaryCurrentPercent: nil,
        primaryResetAt: nil,
        secondaryResetAt: nil,
        primaryWarningLevel: .none,
        secondaryWarningLevel: .none,
        primarySeries: [],
        secondarySeries: []
    )
}

public struct ModelStatsSnapshot: Codable, Equatable, Sendable {
    public let modelUsageItems: [NamedCountItem]
    public let modelAverageTokenItems: [NamedAverageItem]
    public let dominantModelName: String?

    public static let empty = ModelStatsSnapshot(
        modelUsageItems: [],
        modelAverageTokenItems: [],
        dominantModelName: nil
    )
}

public struct ProjectStatsSnapshot: Codable, Equatable, Sendable {
    public let topProjects: [ProjectTokenSeries]
    public let projectCount: Int
    public let highestTokenProjectName: String?
    public let highestTokenProjectValue: Int

    public static let empty = ProjectStatsSnapshot(
        topProjects: [],
        projectCount: 0,
        highestTokenProjectName: nil,
        highestTokenProjectValue: 0
    )
}

public struct AgentAnalyticsSnapshot: Codable, Equatable, Sendable {
    public let selectedRangeSupported: [AnalyticsRange]
    public let activityTrendToday: [HourlyActivityPoint]
    public let activityTrendWeek: [DailyActivityPoint]
    public let activityTrendMonth: [DailyActivityPoint]
    public let sessionStatsToday: SessionStatsSnapshot
    public let sessionStatsWeek: SessionStatsSnapshot
    public let sessionStatsMonth: SessionStatsSnapshot
    public let tokenStatsToday: TokenStatsSnapshot
    public let tokenStatsWeek: TokenStatsSnapshot
    public let tokenStatsMonth: TokenStatsSnapshot
    public let toolStatsToday: ToolStatsSnapshot?
    public let toolStatsWeek: ToolStatsSnapshot?
    public let toolStatsMonth: ToolStatsSnapshot?
    public let changeStatsToday: ChangeStatsSnapshot?
    public let changeStatsWeek: ChangeStatsSnapshot?
    public let changeStatsMonth: ChangeStatsSnapshot?
    public let limitStatsToday: LimitStatsSnapshot?
    public let limitStatsWeek: LimitStatsSnapshot?
    public let limitStatsMonth: LimitStatsSnapshot?
    public let modelStatsToday: ModelStatsSnapshot?
    public let modelStatsWeek: ModelStatsSnapshot?
    public let modelStatsMonth: ModelStatsSnapshot?
    public let projectStatsToday: ProjectStatsSnapshot?
    public let projectStatsWeek: ProjectStatsSnapshot?
    public let projectStatsMonth: ProjectStatsSnapshot?

    public static let empty = AgentAnalyticsSnapshot(
        selectedRangeSupported: AnalyticsRange.allCases,
        activityTrendToday: [],
        activityTrendWeek: [],
        activityTrendMonth: [],
        sessionStatsToday: .empty,
        sessionStatsWeek: .empty,
        sessionStatsMonth: .empty,
        tokenStatsToday: .empty,
        tokenStatsWeek: .empty,
        tokenStatsMonth: .empty,
        toolStatsToday: nil,
        toolStatsWeek: nil,
        toolStatsMonth: nil,
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

    public func sessionStats(for range: AnalyticsRange) -> SessionStatsSnapshot {
        switch range {
        case .today:
            sessionStatsToday
        case .week:
            sessionStatsWeek
        case .month:
            sessionStatsMonth
        }
    }

    public func tokenStats(for range: AnalyticsRange) -> TokenStatsSnapshot {
        switch range {
        case .today:
            tokenStatsToday
        case .week:
            tokenStatsWeek
        case .month:
            tokenStatsMonth
        }
    }

    public func toolStats(for range: AnalyticsRange) -> ToolStatsSnapshot? {
        switch range {
        case .today:
            toolStatsToday
        case .week:
            toolStatsWeek
        case .month:
            toolStatsMonth
        }
    }

    public func changeStats(for range: AnalyticsRange) -> ChangeStatsSnapshot? {
        switch range {
        case .today:
            changeStatsToday
        case .week:
            changeStatsWeek
        case .month:
            changeStatsMonth
        }
    }

    public func limitStats(for range: AnalyticsRange) -> LimitStatsSnapshot? {
        switch range {
        case .today:
            limitStatsToday
        case .week:
            limitStatsWeek
        case .month:
            limitStatsMonth
        }
    }

    public func modelStats(for range: AnalyticsRange) -> ModelStatsSnapshot? {
        switch range {
        case .today:
            modelStatsToday
        case .week:
            modelStatsWeek
        case .month:
            modelStatsMonth
        }
    }

    public func projectStats(for range: AnalyticsRange) -> ProjectStatsSnapshot? {
        switch range {
        case .today:
            projectStatsToday
        case .week:
            projectStatsWeek
        case .month:
            projectStatsMonth
        }
    }
}

public enum AnalyticsWarningLevelCalculator {
    public static func level(for percent: Double?) -> LimitWarningLevel {
        guard let percent else { return .none }
        switch percent {
        case 90...:
            return .critical
        case 80..<90:
            return .warning
        default:
            return .none
        }
    }
}
