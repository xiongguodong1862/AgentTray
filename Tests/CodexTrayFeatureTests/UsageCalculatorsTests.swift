import XCTest
@testable import CodexTrayFeature

final class UsageCalculatorsTests: XCTestCase {
    func testHeatmapLevelClampsBetweenZeroAndFour() {
        XCTAssertEqual(HeatmapLevelCalculator.level(for: 0), 0)
        XCTAssertEqual(HeatmapLevelCalculator.level(for: 1), 0)
        XCTAssertGreaterThanOrEqual(HeatmapLevelCalculator.level(for: 35), 1)
        XCTAssertEqual(HeatmapLevelCalculator.level(for: 1000), 4)
    }

    func testActivityTimelineMergesNearbyEventsIntoOneSession() {
        let base = Date(timeIntervalSince1970: 1_700_000_000)
        let timestamps = [
            base,
            base.addingTimeInterval(2 * 60),
            base.addingTimeInterval(4 * 60),
            base.addingTimeInterval(14 * 60),
        ]

        XCTAssertEqual(ActivityTimelineCalculator.activeMinutes(for: timestamps), 6)
    }

    func testActivityTimelineDeduplicatesDenseEventsInSameMinute() {
        let base = Date(timeIntervalSince1970: 1_699_999_980)
        let timestamps = [
            base,
            base.addingTimeInterval(10),
            base.addingTimeInterval(25),
            base.addingTimeInterval(50),
        ]

        XCTAssertEqual(ActivityTimelineCalculator.activeMinutes(for: timestamps), 1)
    }

    func testPetProgressPromotesStageWithAccumulatedXP() {
        let progress = PetProgressCalculator.progress(totalXP: 1_500, todayXP: 42)
        XCTAssertGreaterThan(progress.level, 3)
        XCTAssertEqual(progress.stage, .pixelKitten)
        XCTAssertEqual(progress.todayXP, 42)
        XCTAssertGreaterThan(progress.nextLevelXP, progress.currentXP)
    }

    func testPetProgressStartsAtLevelZeroWithoutXP() {
        let progress = PetProgressCalculator.progress(totalXP: 0, todayXP: 0)
        XCTAssertEqual(progress.level, 0)
        XCTAssertEqual(progress.stage, .cursorEgg)
        XCTAssertEqual(progress.currentXP, 0)
        XCTAssertEqual(progress.nextLevelXP, 180)
        XCTAssertEqual(progress.todayXP, 0)
    }

    func testPetProgressCurveTakesAboutSixtyDaysToReachFinalStageAtCurrentDailyXP() {
        let finalStageTargetXP = (0..<15).reduce(0) { partialResult, level in
            partialResult + PetProgressCalculator.xpNeeded(for: level)
        }

        XCTAssertEqual(finalStageTargetXP, 11_625)
    }

    func testPetProgressExplanationFormatterReturnsExpectedLevelDescriptions() {
        XCTAssertEqual(
            PetProgressExplanationFormatter.levelDescriptions(),
            [
                "Lv.0-2: 光标蛋",
                "Lv.3-5: 像素幼猫",
                "Lv.6-9: 终端猫",
                "Lv.10-14: 机甲补丁猫",
                "Lv.15+: 刘海守护猫",
            ]
        )
    }

    func testPetProgressExplanationFormatterBuildsAgentContributionDescriptions() {
        let descriptions = PetProgressExplanationFormatter.agentContributionDescriptions(
            from: [
                AgentXPBreakdown(agent: .claude, todayXP: 7, totalXP: 120),
                AgentXPBreakdown(agent: .codex, todayXP: 12, totalXP: 300),
            ]
        )

        XCTAssertEqual(
            descriptions,
            [
                "全部 Agent 近一年累计: 420 XP",
                "Codex: 今日 +12 / 近一年累计 300",
                "Claude: 今日 +7 / 近一年累计 120",
            ]
        )
    }

    func testPetProgressExplanationFormatterBuildsTooltipText() {
        let tooltip = PetProgressExplanationFormatter.tooltipText(
            from: [
                AgentXPBreakdown(agent: .codex, todayXP: 12, totalXP: 300),
            ]
        )

        XCTAssertTrue(tooltip.contains("等级名称"))
        XCTAssertTrue(tooltip.contains("经验计算"))
        XCTAssertTrue(tooltip.contains("各 Agent 贡献"))
        XCTAssertTrue(tooltip.contains("Codex: 今日 +12 / 近一年累计 300"))
    }

    func testUsageLimitProgressStyleUsesExpectedThresholdColors() {
        XCTAssertEqual(UsageLimitProgressStyle.tintHex(for: 80), "#5FE38C")
        XCTAssertEqual(UsageLimitProgressStyle.tintHex(for: 56), "#F5C46B")
        XCTAssertEqual(UsageLimitProgressStyle.tintHex(for: 20), "#FF7A6A")
        XCTAssertEqual(UsageLimitProgressStyle.tintHex(for: nil), "#556579")
    }

    func testUsageLimitProgressStyleClampsProgressRatio() {
        XCTAssertEqual(UsageLimitProgressStyle.progressValue(for: 80), 0.8, accuracy: 0.0001)
        XCTAssertEqual(UsageLimitProgressStyle.progressValue(for: -10), 0, accuracy: 0.0001)
        XCTAssertEqual(UsageLimitProgressStyle.progressValue(for: 140), 1, accuracy: 0.0001)
        XCTAssertEqual(UsageLimitProgressStyle.progressValue(for: nil), 0, accuracy: 0.0001)
    }

    func testUsageDisplayFormatterFormatsNetChangeWithSign() {
        XCTAssertEqual(UsageDisplayFormatter.netChangeLabel(for: 12), "+12")
        XCTAssertEqual(UsageDisplayFormatter.netChangeLabel(for: 0), "0")
        XCTAssertEqual(UsageDisplayFormatter.netChangeLabel(for: -8), "-8")
    }

    func testUsageDisplayFormatterFormatsHeatmapTooltipText() {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.timeZone = TimeZone(secondsFromGMT: 8 * 60 * 60)
        formatter.dateFormat = "yyyy年M月d日"
        let day = UsageMetricsDay(
            date: Date(timeIntervalSince1970: 1_711_244_800),
            dialogs: 3,
            activeMinutes: 42,
            modifiedFiles: 6,
            addedLines: 150,
            deletedLines: 22
        )

        XCTAssertEqual(
            UsageDisplayFormatter.heatmapTooltipText(for: day, dateFormatter: formatter),
            """
            2024年3月24日
            3 次对话
            活跃 42分
            """
        )
    }

    func testUsageDisplayFormatterFormatsHeatmapTooltipTextForZeroMetrics() {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.timeZone = TimeZone(secondsFromGMT: 8 * 60 * 60)
        formatter.dateFormat = "yyyy年M月d日"
        let day = UsageMetricsDay.empty(for: Date(timeIntervalSince1970: 1_711_244_800))

        XCTAssertEqual(
            UsageDisplayFormatter.heatmapTooltipText(for: day, dateFormatter: formatter),
            """
            2024年3月24日
            0 次对话
            活跃 0分
            """
        )
    }

    func testUsageDisplayFormatterFormatsResetHint() {
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let timeZone = TimeZone(secondsFromGMT: 8 * 60 * 60) ?? .current
        XCTAssertEqual(UsageDisplayFormatter.resetHint(for: date, timeZone: timeZone), "11/15 06:13 重置")
        XCTAssertNil(UsageDisplayFormatter.resetHint(for: nil))
    }

    func testHeatmapLabelFormatterShowsMonthOnlyOnFirstWeekColumn() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 8 * 60 * 60) ?? .current
        calendar.firstWeekday = 2

        let aprilFirstWeek = [
            date(2024, 4, 1, calendar: calendar),
            date(2024, 4, 2, calendar: calendar),
            date(2024, 4, 3, calendar: calendar),
            date(2024, 4, 4, calendar: calendar),
            date(2024, 4, 5, calendar: calendar),
            date(2024, 4, 6, calendar: calendar),
            date(2024, 4, 7, calendar: calendar),
        ]
        let aprilSecondWeek = [
            date(2024, 4, 8, calendar: calendar),
            date(2024, 4, 9, calendar: calendar),
            date(2024, 4, 10, calendar: calendar),
            date(2024, 4, 11, calendar: calendar),
            date(2024, 4, 12, calendar: calendar),
            date(2024, 4, 13, calendar: calendar),
            date(2024, 4, 14, calendar: calendar),
        ]
        let mayBoundaryWeek = [
            date(2024, 4, 29, calendar: calendar),
            date(2024, 4, 30, calendar: calendar),
            date(2024, 5, 1, calendar: calendar),
            date(2024, 5, 2, calendar: calendar),
            date(2024, 5, 3, calendar: calendar),
            date(2024, 5, 4, calendar: calendar),
            date(2024, 5, 5, calendar: calendar),
        ]

        XCTAssertEqual(
            HeatmapLabelFormatter.yearMonthLabel(for: aprilFirstWeek, previousWeek: nil, calendar: calendar),
            "4月"
        )
        XCTAssertEqual(
            HeatmapLabelFormatter.yearMonthLabel(for: aprilSecondWeek, previousWeek: aprilFirstWeek, calendar: calendar),
            ""
        )
        XCTAssertEqual(
            HeatmapLabelFormatter.yearMonthLabel(for: mayBoundaryWeek, previousWeek: aprilSecondWeek, calendar: calendar),
            "5月"
        )
    }

    private func date(_ year: Int, _ month: Int, _ day: Int, calendar: Calendar) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day)) ?? .now
    }
}
