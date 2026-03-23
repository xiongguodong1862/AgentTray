import Foundation

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

    public var id: Date { date }

    public var netLines: Int {
        addedLines - deletedLines
    }

    public var activityScore: Double {
        ActivityScoreCalculator.score(
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
            deletedLines: 0
        )
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
            "光标蛋"
        case .pixelKitten:
            "像素幼猫"
        case .terminalCat:
            "终端猫"
        case .mechPatchCat:
            "机甲补丁猫"
        case .notchGuardian:
            "刘海守护猫"
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

public enum DurationFormatter {
    public static func string(for minutes: Int) -> String {
        let hours = minutes / 60
        let remainingMinutes = minutes % 60
        switch (hours, remainingMinutes) {
        case (0, _):
            return "\(remainingMinutes)分"
        case (_, 0):
            return "\(hours)小时"
        default:
            return "\(hours)小时\(remainingMinutes)分"
        }
    }
}
