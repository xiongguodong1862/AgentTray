import Foundation
import SQLite3

enum CodexSurfaceKind: Equatable, Sendable {
    case app
    case cli
    case `extension`
    case unknown

    var label: String {
        switch self {
        case .app:
            "Codex App"
        case .cli:
            "CLI"
        case .extension:
            "Extension"
        case .unknown:
            AppText.text("Unknown", "未知")
        }
    }

    static func infer(from rawSource: String?) -> CodexSurfaceKind {
        guard let rawSource else { return .unknown }
        let source = rawSource.lowercased()
        if source.contains("vscode") || source.contains("cursor") || source.contains("windsurf") || source.contains("zed") || source.contains("jetbrains") {
            return .extension
        }
        if source.contains("app") || source.contains("desktop") || source.contains("macos") {
            return .app
        }
        if source.contains("cli") || source.contains("terminal") || source.contains("tty") {
            return .cli
        }
        return .unknown
    }
}

enum CodexAuthStoragePreference: String, Equatable, Sendable {
    case auto
    case file
    case keyring
    case unknown
}

struct CodexAuthDiscovery: Equatable, Sendable {
    let storagePreference: CodexAuthStoragePreference
    let authMode: String?
    let authFileURL: URL
    let authFileExists: Bool
    let hasAPIKeyInAuthFile: Bool
    let hasTokenSetInAuthFile: Bool
}

struct CodexInstallation: Equatable, Sendable {
    let codexHome: URL
    let sessionsRoot: URL
    let sqliteHome: URL
    let stateDatabaseURL: URL
    let surfaceKind: CodexSurfaceKind
    let auth: CodexAuthDiscovery

    var environmentInfo: CodexEnvironmentInfo {
        CodexEnvironmentInfo(
            environmentLabel: surfaceKind.label,
            authMethodLabel: authMethodLabel,
            codexHomePath: Self.displayPath(for: codexHome),
            sqliteHomePath: Self.displayPath(for: sqliteHome),
            authStorageLabel: authStorageLabel,
            authModeLabel: auth.authMode,
            authFileExists: auth.authFileExists
        )
    }

    private var authStorageLabel: String {
        return switch auth.storagePreference {
        case .auto:
            "auto"
        case .file:
            auth.authFileExists ? "file" : "file?"
        case .keyring:
            "keyring"
        case .unknown:
            auth.authFileExists ? "file" : "unknown"
        }
    }

    private var authMethodLabel: String {
        if auth.hasAPIKeyInAuthFile && !auth.hasTokenSetInAuthFile {
            return "API Key"
        }
        if auth.hasTokenSetInAuthFile || auth.authMode?.lowercased() == "chatgpt" {
            return "ChatGPT OAuth"
        }
        if auth.hasAPIKeyInAuthFile {
            return "API Key"
        }
        return AppText.text("Unknown", "未知")
    }

    private static func displayPath(for url: URL) -> String {
        let path = url.path
        let homePath = FileManager.default.homeDirectoryForCurrentUser.path
        if path == homePath {
            return "~"
        }
        if path.hasPrefix(homePath + "/") {
            return "~" + String(path.dropFirst(homePath.count))
        }
        return path
    }
}

struct CodexInstallationLocator {
    private let fileManager: FileManager
    private let environment: [String: String]
    private let homeDirectory: URL

    init(
        fileManager: FileManager = .default,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
    ) {
        self.fileManager = fileManager
        self.environment = environment
        self.homeDirectory = homeDirectory
    }

    func locate() -> CodexInstallation {
        let codexHome = resolveCodexHome()
        let configURL = codexHome.appending(path: "config.toml")
        let config = loadConfig(at: configURL)
        let sqliteHome = resolveSQLiteHome(codexHome: codexHome, configURL: configURL, config: config)
        let stateDatabaseURL = resolveStateDatabaseURL(codexHome: codexHome, sqliteHome: sqliteHome)
        let surfaceKind = discoverSurfaceKind(databaseURL: stateDatabaseURL)
        let auth = discoverAuth(codexHome: codexHome, config: config)

        return CodexInstallation(
            codexHome: codexHome,
            sessionsRoot: codexHome.appending(path: "sessions"),
            sqliteHome: sqliteHome,
            stateDatabaseURL: stateDatabaseURL,
            surfaceKind: surfaceKind,
            auth: auth
        )
    }

    private func resolveCodexHome() -> URL {
        if let configuredHome = resolvedURL(from: environment["CODEX_HOME"], relativeTo: nil) {
            return configuredHome
        }
        return homeDirectory.appending(path: ".codex")
    }

    private func resolveSQLiteHome(
        codexHome: URL,
        configURL: URL,
        config: [String: String]
    ) -> URL {
        if let configuredSQLiteHome = resolvedURL(from: environment["CODEX_SQLITE_HOME"], relativeTo: nil) {
            return configuredSQLiteHome
        }
        if let configuredSQLiteHome = resolvedURL(
            from: config["sqlite_home"],
            relativeTo: configURL.deletingLastPathComponent()
        ) {
            return configuredSQLiteHome
        }
        return codexHome
    }

    private func resolveStateDatabaseURL(codexHome: URL, sqliteHome: URL) -> URL {
        let preferredURL = sqliteHome.appending(path: "state_5.sqlite")
        if fileManager.fileExists(atPath: preferredURL.path) {
            return preferredURL
        }

        let legacyURL = codexHome.appending(path: "state_5.sqlite")
        if fileManager.fileExists(atPath: legacyURL.path) {
            return legacyURL
        }

        return preferredURL
    }

    private func discoverAuth(codexHome: URL, config: [String: String]) -> CodexAuthDiscovery {
        let authFileURL = codexHome.appending(path: "auth.json")
        let authFileExists = fileManager.fileExists(atPath: authFileURL.path)
        let authObject = loadAuthObject(at: authFileURL)
        let authMode = authObject?["auth_mode"] as? String
        let hasAPIKeyInAuthFile = !(authObject?["OPENAI_API_KEY"] as? String ?? "").isEmpty
        let tokens = authObject?["tokens"] as? [String: Any]
        let tokenValues: [String?] = [
            tokens?["id_token"] as? String,
            tokens?["access_token"] as? String,
            tokens?["refresh_token"] as? String,
        ]
        let hasTokenSetInAuthFile = tokenValues.contains { value in
            guard let value else { return false }
            return !value.isEmpty
        }

        let storagePreference = CodexAuthStoragePreference(
            rawValue: (config["cli_auth_credentials_store"] ?? "").lowercased()
        ) ?? (authFileExists ? .file : .unknown)

        return CodexAuthDiscovery(
            storagePreference: storagePreference,
            authMode: authMode,
            authFileURL: authFileURL,
            authFileExists: authFileExists,
            hasAPIKeyInAuthFile: hasAPIKeyInAuthFile,
            hasTokenSetInAuthFile: hasTokenSetInAuthFile
        )
    }

    private func discoverSurfaceKind(databaseURL: URL) -> CodexSurfaceKind {
        guard fileManager.fileExists(atPath: databaseURL.path) else {
            return .unknown
        }

        var database: OpaquePointer?
        let openResult = sqlite3_open_v2(databaseURL.path, &database, SQLITE_OPEN_READONLY, nil)
        guard openResult == SQLITE_OK, let database else {
            if let database {
                sqlite3_close(database)
            }
            return .unknown
        }
        defer { sqlite3_close(database) }

        let query = """
        SELECT source
        FROM threads
        WHERE source IS NOT NULL AND source != ''
        ORDER BY updated_at DESC
        LIMIT 1
        """

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, query, -1, &statement, nil) == SQLITE_OK, let statement else {
            return .unknown
        }
        defer { sqlite3_finalize(statement) }

        guard sqlite3_step(statement) == SQLITE_ROW else {
            return .unknown
        }
        guard let cString = sqlite3_column_text(statement, 0) else {
            return .unknown
        }
        return CodexSurfaceKind.infer(from: String(cString: cString))
    }

    private func loadConfig(at url: URL) -> [String: String] {
        guard let content = try? String(contentsOf: url, encoding: .utf8) else {
            return [:]
        }
        return MinimalTOMLParser.parseAssignments(content)
    }

    private func loadAuthObject(at url: URL) -> [String: Any]? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }

    private func resolvedURL(from rawValue: String?, relativeTo baseURL: URL?) -> URL? {
        guard let rawValue else { return nil }
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let expandedHome = trimmed
            .replacingOccurrences(of: "${HOME}", with: homeDirectory.path)
            .replacingOccurrences(of: "$HOME", with: homeDirectory.path)
        let expanded = NSString(string: expandedHome).expandingTildeInPath

        if expanded.hasPrefix("/") {
            return URL(fileURLWithPath: expanded).standardizedFileURL
        }

        if let baseURL {
            return baseURL.appending(path: expanded).standardizedFileURL
        }

        return URL(fileURLWithPath: expanded).standardizedFileURL
    }
}

private enum MinimalTOMLParser {
    static func parseAssignments(_ content: String) -> [String: String] {
        var assignments: [String: String] = [:]

        content.enumerateLines { rawLine, _ in
            let line = stripComment(from: rawLine).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty, !line.hasPrefix("[") else { return }
            guard let equalsIndex = line.firstIndex(of: "=") else { return }

            let key = line[..<equalsIndex].trimmingCharacters(in: .whitespacesAndNewlines)
            let rawValue = line[line.index(after: equalsIndex)...]
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !key.isEmpty else { return }

            assignments[key] = unquote(rawValue)
        }

        return assignments
    }

    private static func stripComment(from line: String) -> String {
        var insideDoubleQuotes = false
        var insideSingleQuotes = false

        for (offset, character) in line.enumerated() {
            switch character {
            case "\"" where !insideSingleQuotes:
                insideDoubleQuotes.toggle()
            case "'" where !insideDoubleQuotes:
                insideSingleQuotes.toggle()
            case "#" where !insideDoubleQuotes && !insideSingleQuotes:
                return String(line.prefix(offset))
            default:
                continue
            }
        }

        return line
    }

    private static func unquote(_ rawValue: String) -> String {
        guard rawValue.count >= 2 else { return rawValue }
        if rawValue.hasPrefix("\""), rawValue.hasSuffix("\"") {
            return String(rawValue.dropFirst().dropLast())
        }
        if rawValue.hasPrefix("'"), rawValue.hasSuffix("'") {
            return String(rawValue.dropFirst().dropLast())
        }
        return rawValue
    }
}
