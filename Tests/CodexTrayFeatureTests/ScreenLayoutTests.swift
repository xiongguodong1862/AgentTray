import XCTest
@testable import CodexTrayFeature

final class ScreenLayoutTests: XCTestCase {
    func testPanelIsWiderThanHotspotForExpansionEffect() {
        let anchor = CGRect(x: 300, y: 900, width: 332, height: 38)
        let collapsed = ScreenLayout.collapsedPanelFrame(anchoredTo: anchor)
        let expanded = ScreenLayout.panelSize(for: .year)
        XCTAssertGreaterThan(expanded.width, collapsed.width)
        XCTAssertGreaterThan(expanded.height, collapsed.height)
    }

    func testCollapsedPanelFrameStaysCenteredOnAnchor() {
        let anchor = CGRect(x: 300, y: 900, width: 332, height: 48)
        let collapsed = ScreenLayout.collapsedPanelFrame(anchoredTo: anchor)
        let expanded = ScreenLayout.panelSize(for: .year)

        XCTAssertEqual(collapsed.midX, anchor.midX, accuracy: 0.001)
        XCTAssertLessThan(collapsed.height, expanded.height)
        XCTAssertLessThan(collapsed.width, expanded.width)
    }

    func testCollapsedIslandProvidesExtraWidthForLocalizedHeaderText() {
        XCTAssertGreaterThanOrEqual(ScreenLayout.collapsedIslandSize.width, 380)
    }

    func testExpandedPanelHeightTracksHeatmapRange() {
        let yearSize = ScreenLayout.panelSize(for: .year)
        let weekSize = ScreenLayout.panelSize(for: .week)
        let monthSize = ScreenLayout.panelSize(for: .month)

        XCTAssertEqual(yearSize.height, 560)
        XCTAssertEqual(weekSize.height, 556)
        XCTAssertEqual(monthSize.height, 724)
        XCTAssertEqual(yearSize.width, weekSize.width)
        XCTAssertEqual(weekSize.width, monthSize.width)
        XCTAssertNotEqual(yearSize.height, weekSize.height)
        XCTAssertLessThan(weekSize.height, monthSize.height)
    }

    func testAllPanelYearHeightMatchesTrimmedBaseLayout() {
        let allYearSize = ScreenLayout.panelSize(for: .year, agent: .all)

        XCTAssertEqual(allYearSize.height, 560)
    }

    func testHotspotFrameCentersWithinProvidedPrimaryScreenFrame() {
        let screenFrame = CGRect(x: 1512, y: 0, width: 1512, height: 982)
        let size = CGSize(width: 380, height: 38)

        let hotspot = ScreenLayout.hotspotFrame(screenFrame: screenFrame, size: size)

        XCTAssertEqual(hotspot.midX, screenFrame.midX, accuracy: 0.001)
        XCTAssertEqual(hotspot.maxY, screenFrame.maxY, accuracy: 0.001)
    }

    func testPanelFrameStaysWithinProvidedPrimaryScreenBounds() {
        let screenFrame = CGRect(x: 1512, y: 0, width: 1512, height: 982)
        let anchor = CGRect(x: 1512 + 20, y: 944, width: 380, height: 38)
        let panelSize = CGSize(width: 900, height: 518)

        let panel = ScreenLayout.panelFrame(anchoredTo: anchor, panelSize: panelSize, screenFrame: screenFrame)

        XCTAssertGreaterThanOrEqual(panel.minX, screenFrame.minX + 12)
        XCTAssertLessThanOrEqual(panel.maxX, screenFrame.maxX - 12)
        XCTAssertEqual(panel.maxY, screenFrame.maxY, accuracy: 0.001)
    }

    func testPreferredScreenIndexPrefersNotchedDisplay() {
        let candidates = [
            ScreenLayout.ScreenCandidate(hasNotch: false, isBuiltIn: false),
            ScreenLayout.ScreenCandidate(hasNotch: true, isBuiltIn: true),
            ScreenLayout.ScreenCandidate(hasNotch: false, isBuiltIn: true),
        ]

        XCTAssertEqual(ScreenLayout.preferredScreenIndex(candidates: candidates), 1)
    }

    func testPreferredScreenIndexFallsBackToBuiltInDisplay() {
        let candidates = [
            ScreenLayout.ScreenCandidate(hasNotch: false, isBuiltIn: false),
            ScreenLayout.ScreenCandidate(hasNotch: false, isBuiltIn: true),
        ]

        XCTAssertEqual(ScreenLayout.preferredScreenIndex(candidates: candidates), 1)
    }

    func testPreferredScreenIndexFallsBackToFirstDisplayWhenNeeded() {
        let candidates = [
            ScreenLayout.ScreenCandidate(hasNotch: false, isBuiltIn: false),
            ScreenLayout.ScreenCandidate(hasNotch: false, isBuiltIn: false),
        ]

        XCTAssertEqual(ScreenLayout.preferredScreenIndex(candidates: candidates), 0)
        XCTAssertNil(ScreenLayout.preferredScreenIndex(candidates: []))
    }
}
