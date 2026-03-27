import Foundation

enum AppLanguage: String, CaseIterable, Codable, Identifiable, Sendable, CustomStringConvertible {
    case english
    case chinese

    var id: String { rawValue }

    var title: String {
        switch self {
        case .english:
            "English"
        case .chinese:
            "中文"
        }
    }

    var localeIdentifier: String {
        switch self {
        case .english:
            "en_US"
        case .chinese:
            "zh_CN"
        }
    }

    var description: String { title }
}

enum AppText {
    private static let storageKey = "CodexTray.app-language"

    static func setLanguage(_ language: AppLanguage) {
        UserDefaults.standard.set(language.rawValue, forKey: storageKey)
    }

    static var currentLanguage: AppLanguage {
        guard
            let rawValue = UserDefaults.standard.string(forKey: storageKey),
            let language = AppLanguage(rawValue: rawValue)
        else {
            return .english
        }
        return language
    }

    static func text(_ english: String, _ chinese: String) -> String {
        switch currentLanguage {
        case .english:
            english
        case .chinese:
            chinese
        }
    }

    static var locale: Locale {
        Locale(identifier: currentLanguage.localeIdentifier)
    }

    static var isEnglish: Bool {
        currentLanguage == .english
    }
}
