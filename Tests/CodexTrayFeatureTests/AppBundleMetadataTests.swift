import XCTest

final class AppBundleMetadataTests: XCTestCase {
    func testInfoPlistContainsMenuBarAppKeys() throws {
        let rootURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let plistURL = rootURL.appending(path: "AppBundle/Info.plist")
        let iconURL = rootURL.appending(path: "AppBundle/CodexTray.icns")
        let data = try Data(contentsOf: plistURL)
        let plist = try XCTUnwrap(
            PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        )

        XCTAssertEqual(plist["CFBundleDisplayName"] as? String, "AgentTray")
        XCTAssertEqual(plist["CFBundleExecutable"] as? String, "AgentTray")
        XCTAssertEqual(plist["CFBundleIdentifier"] as? String, "com.xgod.codextray")
        XCTAssertEqual(plist["CFBundleIconFile"] as? String, "CodexTray")
        XCTAssertEqual(plist["CFBundleName"] as? String, "AgentTray")
        XCTAssertEqual(plist["CFBundlePackageType"] as? String, "APPL")
        XCTAssertEqual(plist["LSUIElement"] as? Bool, true)
        XCTAssertTrue(FileManager.default.fileExists(atPath: iconURL.path()))
    }
}
