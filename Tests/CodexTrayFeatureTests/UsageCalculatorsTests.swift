import XCTest
@testable import CodexTrayFeature

final class UsageCalculatorsTests: XCTestCase {
    func testHeatmapLevelClampsBetweenZeroAndFour() {
        XCTAssertEqual(HeatmapLevelCalculator.level(for: 0), 0)
        XCTAssertEqual(HeatmapLevelCalculator.level(for: 1), 0)
        XCTAssertGreaterThanOrEqual(HeatmapLevelCalculator.level(for: 35), 1)
        XCTAssertEqual(HeatmapLevelCalculator.level(for: 1000), 4)
    }

    func testAgentPanelLayoutPolicyUsesCompactStatusTitleForNonCodexAgents() {
        XCTAssertEqual(AgentPanelLayoutPolicy.statusTitle(for: .codex), "配额 / 状态")
        XCTAssertEqual(AgentPanelLayoutPolicy.statusTitle(for: .claude), "使用情况")
        XCTAssertEqual(AgentPanelLayoutPolicy.statusTitle(for: .gemini), "使用情况")
    }

    func testAgentPanelLayoutPolicyFormatsHeaderStatusWithTodayTokenForGemini() {
        let snapshot = AgentSnapshot(
            agent: .gemini,
            generatedAt: .now,
            status: AgentStatusSummary(primaryLabel: "今日会话", primaryValue: "3"),
            today: UsageMetricsDay(
                date: .now,
                dialogs: 3,
                activeMinutes: 12,
                modifiedFiles: 0,
                addedLines: 0,
                deletedLines: 0,
                tokenUsage: 14_272,
                toolCalls: 2
            ),
            lastSevenDays: [],
            lastYearDays: [],
            currentModel: "gemini-2.5-pro",
            lastActiveAt: .now,
            environment: AgentEnvironmentSummary(runtimeLabel: "Gemini CLI", dataSourceLabel: "~/.gemini"),
            isAvailable: true
        )

        XCTAssertEqual(AgentPanelLayoutPolicy.headerStatusText(for: snapshot), "Token 14.3K")
    }

    func testAgentPanelLayoutPolicyFormatsRecentAverageTokensPerSessionFromLastSevenDays() {
        let snapshot = AgentSnapshot(
            agent: .claude,
            generatedAt: .now,
            status: AgentStatusSummary(primaryLabel: "今日 Token", primaryValue: "2.5K"),
            today: UsageMetricsDay.empty(for: .now),
            lastSevenDays: [
                UsageMetricsDay(
                    date: .now,
                    dialogs: 2,
                    activeMinutes: 10,
                    modifiedFiles: 0,
                    addedLines: 0,
                    deletedLines: 0,
                    tokenUsage: 3_000
                ),
                UsageMetricsDay(
                    date: .now.addingTimeInterval(-86_400),
                    dialogs: 1,
                    activeMinutes: 8,
                    modifiedFiles: 0,
                    addedLines: 0,
                    deletedLines: 0,
                    tokenUsage: 1_500
                )
            ],
            lastYearDays: [],
            currentModel: "claude-sonnet-4-5",
            lastActiveAt: .now,
            environment: AgentEnvironmentSummary(runtimeLabel: "Claude Code", dataSourceLabel: "~/.claude/projects"),
            isAvailable: true
        )

        XCTAssertEqual(AgentPanelLayoutPolicy.recentAverageTokensPerSessionText(for: snapshot), "1.5K")
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
                "Lv.0-2: 喵喵蛋",
                "Lv.3-5: 像素喵",
                "Lv.6-9: 终端喵",
                "Lv.10-14: 补丁喵",
                "Lv.15+: 守护喵",
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

    func testPetStatusFormatterReturnsRestingLineWithoutTodayXP() {
        let progress = PetProgress(level: 2, stage: .cursorEgg, currentXP: 40, nextLevelXP: 350, todayXP: 0)

        XCTAssertEqual(PetStatusFormatter.statusLine(for: progress), "打个小盹，等你开始今天的冒险")
        XCTAssertEqual(PetStatusFormatter.indicatorHex(for: progress), "#A0AEC0")
    }

    func testPetStatusFormatterReturnsGuardianLineForHighLevelPet() {
        let progress = PetProgress(level: 15, stage: .notchGuardian, currentXP: 18, nextLevelXP: 1_455, todayXP: 12)

        XCTAssertEqual(PetStatusFormatter.statusLine(for: progress), "守护模式在线，正在盯着你的进度")
        XCTAssertEqual(PetStatusFormatter.indicatorHex(for: progress), "#A4A7FF")
    }

    func testPetStatusFormatterUsesFasterBlinkForHigherStages() {
        XCTAssertGreaterThan(PetStatusFormatter.blinkInterval(for: PetProgress(level: 3, stage: .pixelKitten, currentXP: 0, nextLevelXP: 1, todayXP: 1)), 3)
        XCTAssertLessThan(PetStatusFormatter.blinkInterval(for: PetProgress(level: 15, stage: .notchGuardian, currentXP: 0, nextLevelXP: 1, todayXP: 1)), 2.2)
    }

    func testPetInteractionStyleReturnsZeroOffsetWhenNotHovered() {
        XCTAssertEqual(
            PetInteractionStyle.lookOffset(panelLocation: nil, avatarFrame: CGRect(x: 100, y: 100, width: 58, height: 58)),
            .zero
        )
    }

    func testPetInteractionStyleClampsLookOffsetWithinExpectedRange() {
        let offset = PetInteractionStyle.lookOffset(
            panelLocation: CGPoint(x: 999, y: -100),
            avatarFrame: CGRect(x: 100, y: 100, width: 58, height: 58)
        )

        XCTAssertEqual(offset.width, 7.4, accuracy: 0.001)
        XCTAssertEqual(offset.height, -5.2, accuracy: 0.001)
    }

    func testPetInteractionStyleUsesPanelCoordinatesRelativeToAvatarFrame() {
        let offset = PetInteractionStyle.lookOffset(
            panelLocation: CGPoint(x: 158, y: 129),
            avatarFrame: CGRect(x: 100, y: 100, width: 58, height: 58)
        )

        XCTAssertEqual(offset.width, 0.975, accuracy: 0.001)
        XCTAssertEqual(offset.height, 0, accuracy: 0.001)
    }

    func testPetInteractionStyleTriggersTapEasterEggForRapidTaps() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let tapDates = [
            now.addingTimeInterval(-2.0),
            now.addingTimeInterval(-1.4),
            now.addingTimeInterval(-0.9),
            now.addingTimeInterval(-0.3),
        ]

        XCTAssertTrue(PetInteractionStyle.shouldTriggerTapEasterEgg(tapDates: tapDates, now: now))
    }

    func testPetInteractionStyleIgnoresOldTapsForTapEasterEgg() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let tapDates = [
            now.addingTimeInterval(-3.0),
            now.addingTimeInterval(-2.7),
            now.addingTimeInterval(-1.0),
            now.addingTimeInterval(-0.2),
        ]

        XCTAssertFalse(PetInteractionStyle.shouldTriggerTapEasterEgg(tapDates: tapDates, now: now))
    }

    func testPetAnimationPlaybackCoordinatorReturnsNoAnimationWithoutStoredState() {
        let progress = PetProgress(level: 4, stage: .pixelKitten, currentXP: 20, nextLevelXP: 435, todayXP: 8)

        XCTAssertEqual(PetAnimationPlaybackCoordinator.pendingAnimations(current: progress, stored: nil), [])
    }

    func testPetAnimationPlaybackCoordinatorReturnsLevelUpAnimation() {
        let progress = PetProgress(level: 5, stage: .pixelKitten, currentXP: 20, nextLevelXP: 520, todayXP: 8)
        let stored = PetAnimationPlaybackState(
            presentedLevel: 4,
            presentedStage: .pixelKitten
        )

        XCTAssertEqual(
            PetAnimationPlaybackCoordinator.pendingAnimations(current: progress, stored: stored),
            [.levelUp(level: 5)]
        )
    }

    func testPetAnimationPlaybackCoordinatorReturnsEvolutionThenLevelUp() {
        let progress = PetProgress(level: 6, stage: .terminalCat, currentXP: 10, nextLevelXP: 690, todayXP: 12)
        let stored = PetAnimationPlaybackState(
            presentedLevel: 5,
            presentedStage: .pixelKitten
        )

        XCTAssertEqual(
            PetAnimationPlaybackCoordinator.pendingAnimations(current: progress, stored: stored),
            [
                .evolution(from: .pixelKitten, to: .terminalCat),
                .levelUp(level: 6),
            ]
        )
    }

    func testPetTapReactionUsesStageSpecificLabels() {
        XCTAssertEqual(PetTapReaction.squint.label(for: .cursorEgg), "蛋壳眨眨")
        XCTAssertEqual(PetTapReaction.tailFlick.label(for: .terminalCat), "终端甩尾")
    }

    func testPetEasterEggUsesStageSpecificLabels() {
        XCTAssertEqual(PetEasterEgg.hoverNuzzle.label(for: .cursorEgg), "轻轻蹭壳")
        XCTAssertEqual(PetEasterEgg.tapOverload.label(for: .mechPatchCat), "动力过载!")
    }

    func testPetPreviewFactoryCreatesExpectedPreviewMilestones() {
        let previous = PetPreviewFactory.progress(for: 4, todayXP: 10)
        let next = PetPreviewFactory.progress(for: 6, todayXP: 10)

        XCTAssertEqual(
            PetPreviewFactory.previewMilestones(from: previous, to: next),
            [
                .evolution(from: .pixelKitten, to: .terminalCat),
                .levelUp(level: 6),
            ]
        )
    }

    func testPetDialogueLibraryProvidesAtLeastTwentyMessages() {
        let progress = PetProgress(level: 4, stage: .pixelKitten, currentXP: 29, nextLevelXP: 520, todayXP: 120)

        XCTAssertGreaterThanOrEqual(PetDialogueLibrary.messages(for: progress).count, 20)
    }

    func testPetDialogueLibraryRotatesMessagesByTick() {
        let progress = PetProgress(level: 4, stage: .pixelKitten, currentXP: 29, nextLevelXP: 520, todayXP: 120)

        XCTAssertNotEqual(
            PetDialogueLibrary.message(for: progress, tick: 0),
            PetDialogueLibrary.message(for: progress, tick: 1)
        )
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

    func testUsageDisplayFormatterFormatsHeatmapTooltipTextWithCompactTokenValue() {
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
            deletedLines: 22,
            tokenUsage: 3_200
        )

        XCTAssertEqual(
            UsageDisplayFormatter.heatmapTooltipText(for: day, dateFormatter: formatter),
            """
            2024年3月24日
            3 次对话
            活跃 42分
            Token 3.2K
            """
        )
    }

    func testUsageDisplayFormatterFormatsResetHint() {
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let timeZone = TimeZone(secondsFromGMT: 8 * 60 * 60) ?? .current
        XCTAssertEqual(UsageDisplayFormatter.resetHint(for: date, timeZone: timeZone), "11/15 06:13 重置")
        XCTAssertNil(UsageDisplayFormatter.resetHint(for: nil))
    }

    func testUsageDisplayFormatterFormatsResetDetailWithRemainingDuration() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let resetAt = now.addingTimeInterval((4 * 60 * 60) + (54 * 60))
        let timeZone = TimeZone(secondsFromGMT: 8 * 60 * 60) ?? .current

        XCTAssertEqual(
            UsageDisplayFormatter.resetDetail(for: resetAt, relativeTo: now, timeZone: timeZone),
            "11/15 11:07 重置 | 剩余 4小时54分"
        )
        XCTAssertNil(UsageDisplayFormatter.resetDetail(for: nil, relativeTo: now, timeZone: timeZone))
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
