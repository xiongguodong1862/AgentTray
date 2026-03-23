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

    func testUsageDisplayFormatterFormatsResetHint() {
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let timeZone = TimeZone(secondsFromGMT: 8 * 60 * 60) ?? .current
        XCTAssertEqual(UsageDisplayFormatter.resetHint(for: date, timeZone: timeZone), "11/15 06:13 重置")
        XCTAssertNil(UsageDisplayFormatter.resetHint(for: nil))
    }
}
