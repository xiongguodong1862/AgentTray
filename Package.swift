// swift-tools-version: 6.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "CodexTray",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .executable(name: "CodexTray", targets: ["CodexTray"]),
        .library(name: "CodexTrayFeature", targets: ["CodexTrayFeature"]),
    ],
    targets: [
        .executableTarget(
            name: "CodexTray",
            dependencies: ["CodexTrayFeature"]
        ),
        .target(
            name: "CodexTrayFeature",
            linkerSettings: [
                .linkedLibrary("sqlite3"),
            ]
        ),
        .testTarget(
            name: "CodexTrayFeatureTests",
            dependencies: ["CodexTrayFeature"]
        ),
    ]
)
