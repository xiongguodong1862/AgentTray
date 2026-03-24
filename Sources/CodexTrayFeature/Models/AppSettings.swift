import Combine
import Foundation
import SwiftUI

struct AppSettings: Codable, Equatable, Sendable {
    var defaultAgent: DefaultAgentPreference
    var defaultHeatmapRange: HeatmapRange
    var refreshInterval: RefreshIntervalOption
    var showsHotspot: Bool
    var themeTint: ThemeTintPreset
    var heatmapColor: HeatmapColorPreset

    init(
        defaultAgent: DefaultAgentPreference = .all,
        defaultHeatmapRange: HeatmapRange = .year,
        refreshInterval: RefreshIntervalOption = .oneMinute,
        showsHotspot: Bool = true,
        themeTint: ThemeTintPreset = .deepBlue,
        heatmapColor: HeatmapColorPreset = .emerald
    ) {
        self.defaultAgent = defaultAgent
        self.defaultHeatmapRange = defaultHeatmapRange
        self.refreshInterval = refreshInterval
        self.showsHotspot = showsHotspot
        self.themeTint = themeTint
        self.heatmapColor = heatmapColor
    }
}

enum DefaultAgentPreference: String, CaseIterable, Codable, Identifiable, Sendable, CustomStringConvertible {
    case all
    case codex
    case claude
    case gemini
    case followRecent

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all:
            "全部"
        case .codex:
            "Codex"
        case .claude:
            "Claude"
        case .gemini:
            "Gemini"
        case .followRecent:
            "跟随最近活跃"
        }
    }

    func resolve(mostRecentlyActive recent: AgentKind?) -> AgentKind {
        switch self {
        case .all:
            .all
        case .codex:
            .codex
        case .claude:
            .claude
        case .gemini:
            .gemini
        case .followRecent:
            recent ?? .all
        }
    }

    var description: String { title }

    static func options(for availableAgents: [AgentKind]) -> [DefaultAgentPreference] {
        var options: [DefaultAgentPreference] = [.all]
        if availableAgents.contains(.codex) {
            options.append(.codex)
        }
        if availableAgents.contains(.claude) {
            options.append(.claude)
        }
        if availableAgents.contains(.gemini) {
            options.append(.gemini)
        }
        options.append(.followRecent)
        return options
    }
}

enum RefreshIntervalOption: String, CaseIterable, Codable, Identifiable, Sendable, CustomStringConvertible {
    case thirtySeconds
    case oneMinute
    case fiveMinutes
    case panelOpenOnly

    var id: String { rawValue }

    var title: String {
        switch self {
        case .thirtySeconds:
            "30 秒"
        case .oneMinute:
            "1 分钟"
        case .fiveMinutes:
            "5 分钟"
        case .panelOpenOnly:
            "仅打开面板时"
        }
    }

    var timeInterval: TimeInterval? {
        switch self {
        case .thirtySeconds:
            30
        case .oneMinute:
            60
        case .fiveMinutes:
            300
        case .panelOpenOnly:
            nil
        }
    }

    var description: String { title }
}

enum ThemeTintPreset: String, CaseIterable, Codable, Identifiable, Sendable {
    case classicDeepBlue
    case deepBlue
    case slate
    case cyanSky
    case iceMint

    var id: String { rawValue }

    var title: String {
        switch self {
        case .classicDeepBlue:
            "经典深蓝"
        case .deepBlue:
            "深蓝"
        case .slate:
            "岩灰"
        case .cyanSky:
            "晴空"
        case .iceMint:
            "冰青"
        }
    }

    var hex: String {
        switch self {
        case .classicDeepBlue:
            "#102942"
        case .deepBlue:
            "#2D7FF9"
        case .slate:
            "#6E8197"
        case .cyanSky:
            "#27C2D8"
        case .iceMint:
            "#7FD3C5"
        }
    }

    var gradientHexes: [String] {
        switch self {
        case .classicDeepBlue:
            ["#000000", "#000000", "#071321", "#0B1D31", "#102942"]
        case .deepBlue:
            ["#000000", "#000000", "#0C1A2B", "#132D49", "#1B4470"]
        case .slate:
            ["#000000", "#000000", "#11161D", "#1E2732", "#2D3947"]
        case .cyanSky:
            ["#000000", "#000000", "#081922", "#0F2D3B", "#17485A"]
        case .iceMint:
            ["#000000", "#000000", "#0A1617", "#122629", "#1A393D"]
        }
    }
}

enum HeatmapColorPreset: String, CaseIterable, Codable, Identifiable, Sendable {
    case emerald
    case aqua
    case sky
    case lemon
    case rose
    case coral

    var id: String { rawValue }

    var title: String {
        switch self {
        case .emerald:
            "翠绿"
        case .aqua:
            "青蓝"
        case .sky:
            "天蓝"
        case .lemon:
            "柠黄"
        case .rose:
            "玫红"
        case .coral:
            "珊瑚"
        }
    }

    var hex: String {
        switch self {
        case .emerald:
            "#3FE6A1"
        case .aqua:
            "#3DE4FF"
        case .sky:
            "#58A6FF"
        case .lemon:
            "#FFD84D"
        case .rose:
            "#FF6EA8"
        case .coral:
            "#FF8A65"
        }
    }

    var gradientHexes: [String] {
        [
            ColorHex.blend("#243341", hex, ratio: 0.14),
            ColorHex.blend("#243341", hex, ratio: 0.34),
            ColorHex.blend("#243341", hex, ratio: 0.56),
            ColorHex.blend("#243341", hex, ratio: 0.78),
            ColorHex.blend(hex, "#FFFFFF", ratio: 0.06),
        ]
    }
}

@MainActor
final class AppSettingsStore: ObservableObject {
    @Published private(set) var settings: AppSettings
    @Published private(set) var panelPresentationSequence = 0

    private let userDefaults: UserDefaults
    private let storageKey: String

    init(
        userDefaults: UserDefaults = .standard,
        storageKey: String = "CodexTray.app-settings"
    ) {
        self.userDefaults = userDefaults
        self.storageKey = storageKey

        if let data = userDefaults.data(forKey: storageKey),
           let decoded = try? JSONDecoder().decode(AppSettings.self, from: data) {
            settings = decoded
        } else {
            settings = AppSettings()
        }
    }

    func updateDefaultAgent(_ value: DefaultAgentPreference) {
        update { $0.defaultAgent = value }
    }

    func updateDefaultHeatmapRange(_ value: HeatmapRange) {
        update { $0.defaultHeatmapRange = value }
    }

    func updateRefreshInterval(_ value: RefreshIntervalOption) {
        update { $0.refreshInterval = value }
    }

    func updateShowsHotspot(_ value: Bool) {
        update { $0.showsHotspot = value }
    }

    func updateThemeTint(_ value: ThemeTintPreset) {
        withAnimation(.easeInOut(duration: 0.35)) {
            update { $0.themeTint = value }
        }
    }

    func updateHeatmapColor(_ value: HeatmapColorPreset) {
        withAnimation(.easeInOut(duration: 0.35)) {
            update { $0.heatmapColor = value }
        }
    }

    private func update(_ mutate: (inout AppSettings) -> Void) {
        var next = settings
        mutate(&next)
        settings = next
        save()
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(settings) else { return }
        userDefaults.set(data, forKey: storageKey)
    }

    func markPanelPresented() {
        panelPresentationSequence += 1
    }
}

enum ColorHex {
    static func blend(_ fromHex: String, _ toHex: String, ratio: Double) -> String {
        let from = rgbComponents(hex: fromHex)
        let to = rgbComponents(hex: toHex)
        let clamped = max(0, min(1, ratio))
        let red = interpolate(from.red, to.red, ratio: clamped)
        let green = interpolate(from.green, to.green, ratio: clamped)
        let blue = interpolate(from.blue, to.blue, ratio: clamped)
        return hexString(red: red, green: green, blue: blue)
    }

    private static func interpolate(_ start: Double, _ end: Double, ratio: Double) -> Double {
        start + ((end - start) * ratio)
    }

    private static func rgbComponents(hex: String) -> (red: Double, green: Double, blue: Double) {
        let cleaned = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var integer: UInt64 = 0
        Scanner(string: cleaned).scanHexInt64(&integer)
        let red = Double((integer >> 16) & 0xFF) / 255
        let green = Double((integer >> 8) & 0xFF) / 255
        let blue = Double(integer & 0xFF) / 255
        return (red, green, blue)
    }

    private static func hexString(red: Double, green: Double, blue: Double) -> String {
        let r = Int(round(max(0, min(1, red)) * 255))
        let g = Int(round(max(0, min(1, green)) * 255))
        let b = Int(round(max(0, min(1, blue)) * 255))
        return String(format: "#%02X%02X%02X", r, g, b)
    }
}
