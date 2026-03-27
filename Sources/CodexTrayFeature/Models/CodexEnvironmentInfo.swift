import Foundation

public struct CodexEnvironmentInfo: Equatable, Sendable {
    public let environmentLabel: String
    public let authMethodLabel: String
    public let codexHomePath: String
    public let sqliteHomePath: String
    public let authStorageLabel: String
    public let authModeLabel: String?
    public let authFileExists: Bool

    public var summaryLine: String {
        AppText.text(
            "Environment: \(environmentLabel)  ·  Auth: \(authMethodLabel)",
            "当前环境：\(environmentLabel)  ·  认证方式：\(authMethodLabel)"
        )
    }
}
