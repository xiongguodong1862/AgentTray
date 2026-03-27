import XCTest
@testable import CodexTrayFeature

final class PanelRootViewTests: XCTestCase {
    @MainActor
    func testLoadingStatusTextOmitsTrailingEllipsis() {
        XCTAssertEqual(PanelRootView.loadingStatusText, "Loading data")
        XCTAssertFalse(PanelRootView.loadingStatusText.contains("..."))
    }
}
