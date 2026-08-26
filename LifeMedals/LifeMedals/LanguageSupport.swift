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
    private static let englishBundle: Bundle? = {
        guard let path = Bundle.main.path(forResource: "en", ofType: "lproj") else {
            return nil
        }
        return Bundle(path: path)
    }()

    /// Resolves Chinese source strings that travel through ordinary `String`
    /// properties. SwiftUI only localizes string literals automatically, so
    /// shared components and service feedback need this explicit lookup.
    static func text(_ chinese: String) -> String {
        guard AppLanguage.current == .english else { return chinese }
        return englishBundle?.localizedString(
            forKey: chinese,
            value: chinese,
            table: nil
        ) ?? chinese
    }

    static func text(_ chinese: String, english: String) -> String {
        AppLanguage.current == .english ? english : chinese
    }

    static func date(
        _ date: Date,
        dateStyle: DateFormatter.Style,
        timeStyle: DateFormatter.Style = .none
    ) -> String {
        let formatter = DateFormatter()
        formatter.locale = AppLanguage.current.locale
        formatter.dateStyle = dateStyle
        formatter.timeStyle = timeStyle
        return formatter.string(from: date)
    }

    static func monthAndDay(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = AppLanguage.current.locale
        formatter.setLocalizedDateFormatFromTemplate("MMMd")
        return formatter.string(from: date)
    }
}
