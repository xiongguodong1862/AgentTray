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

        XCTAssertEqual(yearSize.height, 518)
        XCTAssertEqual(weekSize.height, 514)
        XCTAssertEqual(monthSize.height, 682)
        XCTAssertEqual(yearSize.width, weekSize.width)
        XCTAssertEqual(weekSize.width, monthSize.width)
        XCTAssertNotEqual(yearSize.height, weekSize.height)
        XCTAssertLessThan(weekSize.height, monthSize.height)
    }
}
