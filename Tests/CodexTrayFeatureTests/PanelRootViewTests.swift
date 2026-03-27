import XCTest
@testable import CodexTrayFeature

final class PanelRootViewTests: XCTestCase {
    @MainActor
    func testLoadingStatusTextOmitsTrailingEllipsis() {
        XCTAssertEqual(PanelRootView.loadingStatusText, "数据整理中")
        XCTAssertFalse(PanelRootView.loadingStatusText.contains("..."))
    }
}
