import Foundation

enum AppLanguage: String, CaseIterable, Identifiable, Codable, Sendable {
    case bg
    case ru

    var id: String { rawValue }

    var nativeName: String {
        switch self {
        case .bg: "Български"
        case .ru: "Русский"
        }
    }

    var flag: String {
        switch self {
        case .bg: "🇧🇬"
        case .ru: "🇷🇺"
        }
    }

    var locale: Locale {
        switch self {
        case .bg: Locale(identifier: "bg_BG")
        case .ru: Locale(identifier: "ru_RU")
        }
    }

    static var systemDefault: AppLanguage {
        let preferred = Locale.preferredLanguages.first?.lowercased() ?? ""
        return preferred.hasPrefix("ru") ? .ru : .bg
    }
}
