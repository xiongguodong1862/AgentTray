import XCTest

final class AppBundleMetadataTests: XCTestCase {
    func testInfoPlistContainsMenuBarAppKeys() throws {
        let rootURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let plistURL = rootURL.appending(path: "AppBundle/Info.plist")
        let data = try Data(contentsOf: plistURL)
        let plist = try XCTUnwrap(
            PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        )

        XCTAssertEqual(plist["CFBundleExecutable"] as? String, "CodexTray")
        XCTAssertEqual(plist["CFBundleIdentifier"] as? String, "com.xgod.codextray")
        XCTAssertEqual(plist["CFBundlePackageType"] as? String, "APPL")
        XCTAssertEqual(plist["LSUIElement"] as? Bool, true)
    }
}
