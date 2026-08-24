import Foundation

enum AppLanguage: String, CaseIterable, Identifiable {
    case simplifiedChinese = "zh-Hans"
    case english = "en"

    static let storageKey = "appLanguage"

    var id: String { rawValue }

    var locale: Locale {
        Locale(identifier: rawValue)
    }

    var nativeName: String {
        switch self {
        case .simplifiedChinese: "简体中文"
        case .english: "English"
        }
    }

    var localizedName: String {
        switch self {
        case .simplifiedChinese: L10n.text("简体中文", english: "Simplified Chinese")
        case .english: "English"
        }
    }

    static var current: AppLanguage {
        guard
            let storedValue = UserDefaults.standard.string(forKey: storageKey),
            let language = AppLanguage(rawValue: storedValue)
        else {
            return .simplifiedChinese
        }
        return language
    }
}

enum L10n {
    static func text(_ chinese: String, english: String) -> String {
        AppLanguage.current == .english ? english : chinese
    }
}
